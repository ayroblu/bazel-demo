import CryptoKit
import Foundation
import Log
import Network

/// Makes a pair of Foundation streams (an L2CAP channel's) look like a
/// datagram carrier: each datagram travels as `[u16 length][sealed bytes]`.
///
/// The DTLS carriers get their encryption from the network stack; a stream
/// has none, and bluetooth link encryption would require an OS-level bond the
/// app never makes. So every datagram is sealed with ChaChaPoly under a key
/// derived from the two devices' pairing secret - which, unlike the wifi
/// path's baked-in key, actually authenticates the peer. The nonce is random
/// per datagram and travels in the sealed box.
///
/// An L2CAP channel is credit-based: when the peer stops draining, writes
/// stop being accepted. Audio must not queue behind that, so the write buffer
/// is capped at a few frames and newer datagrams are dropped while it is
/// full - the same late-is-worthless policy the datagram links get for free.
nonisolated final class StreamDatagramCarrier: NSObject, DatagramCarrier, StreamDelegate,
  @unchecked Sendable
{
  private let input: InputStream
  private let output: OutputStream
  private let key: SymmetricKey
  private let label: String
  private let lock = NSLock()

  private var onOpen: (@Sendable () -> Void)?
  private var onDatagram: (@Sendable (Data) -> Void)?
  private var onFailed: (@Sendable (String) -> Void)?

  private var inputOpen = false
  private var outputOpen = false
  private var didOpen = false
  private var cancelled = false
  private var readBuffer = Data()
  private var writeBuffer = Data()
  private var droppedWrites = 0
  private var loggedDropAt: Date?

  private let maxFrameBytes = 4096
  private let maxWriteBufferBytes = 2048

  init(input: InputStream, output: OutputStream, secret: Data, label: String) {
    self.input = input
    self.output = output
    self.label = label
    key = HKDF<SHA256>.deriveKey(
      inputKeyMaterial: SymmetricKey(data: secret),
      info: Data("local-call-app.l2cap-audio.v1".utf8),
      outputByteCount: 32)
  }

  var carrierDescription: String { label }
  var remoteEndpoint: NWEndpoint? { nil }

  func setHandlers(
    onOpen: @escaping @Sendable () -> Void,
    onDatagram: @escaping @Sendable (Data) -> Void,
    onFailed: @escaping @Sendable (String) -> Void
  ) {
    lock.lock()
    self.onOpen = onOpen
    self.onDatagram = onDatagram
    self.onFailed = onFailed
    lock.unlock()
  }

  /// Streams need a run loop; the main one is the only one guaranteed to keep
  /// running, and the traffic is 20ms opus frames, not bulk data.
  func start(queue: DispatchQueue) {
    DispatchQueue.main.async { [self] in
      input.delegate = self
      output.delegate = self
      input.schedule(in: .main, forMode: .default)
      output.schedule(in: .main, forMode: .default)
      input.open()
      output.open()
    }
  }

  func cancel() {
    lock.lock()
    cancelled = true
    onOpen = nil
    onDatagram = nil
    onFailed = nil
    lock.unlock()
    DispatchQueue.main.async { [self] in
      input.delegate = nil
      output.delegate = nil
      input.close()
      output.close()
      input.remove(from: .main, forMode: .default)
      output.remove(from: .main, forMode: .default)
    }
  }

  func send(_ datagram: Data, completion: @escaping @Sendable (Error?) -> Void) {
    guard let sealed = try? ChaChaPoly.seal(datagram, using: key).combined else {
      completion(CarrierError.sealFailed)
      return
    }
    var frame = Data([UInt8((sealed.count >> 8) & 0xff), UInt8(sealed.count & 0xff)])
    frame.append(sealed)
    DispatchQueue.main.async { [self] in
      lock.lock()
      let full = writeBuffer.count + frame.count > maxWriteBufferBytes
      if full {
        droppedWrites += 1
        let shouldLog = shouldLogDropLocked()
        lock.unlock()
        if shouldLog {
          log("stream carrier write buffer full, dropping", label)
        }
        completion(nil)
        return
      }
      writeBuffer.append(frame)
      lock.unlock()
      drainWrites()
      completion(nil)
    }
  }

  func stream(_ stream: Stream, handle event: Stream.Event) {
    switch event {
    case .openCompleted:
      lock.lock()
      if stream === input { inputOpen = true }
      if stream === output { outputOpen = true }
      let opens = inputOpen && outputOpen && !didOpen
      if opens { didOpen = true }
      let handler = onOpen
      lock.unlock()
      if opens {
        log("stream carrier open", label)
        handler?()
      }
    case .hasBytesAvailable:
      readAvailable()
    case .hasSpaceAvailable:
      drainWrites()
    case .errorOccurred:
      fail("stream error \(String(describing: stream.streamError))")
    case .endEncountered:
      fail("stream ended")
    default:
      break
    }
  }

  private func readAvailable() {
    var chunk = [UInt8](repeating: 0, count: 4096)
    while input.hasBytesAvailable {
      let count = input.read(&chunk, maxLength: chunk.count)
      if count < 0 {
        fail("stream read failed \(String(describing: input.streamError))")
        return
      }
      if count == 0 { break }
      lock.lock()
      readBuffer.append(contentsOf: chunk[0..<count])
      lock.unlock()
    }
    deliverFrames()
  }

  private func deliverFrames() {
    while true {
      lock.lock()
      guard readBuffer.count >= 2 else {
        lock.unlock()
        return
      }
      let bytes = [UInt8](readBuffer.prefix(2))
      let length = Int(bytes[0]) << 8 | Int(bytes[1])
      guard length > 0, length <= maxFrameBytes else {
        lock.unlock()
        fail("stream framing corrupt length \(length)")
        return
      }
      guard readBuffer.count >= 2 + length else {
        lock.unlock()
        return
      }
      // Data keeps its slice indices after removeFirst, so all offsets have
      // to be relative to startIndex rather than zero.
      let start = readBuffer.startIndex
      let sealed = readBuffer.subdata(in: (start + 2)..<(start + 2 + length))
      readBuffer.removeFirst(2 + length)
      let handler = onDatagram
      lock.unlock()
      guard let box = try? ChaChaPoly.SealedBox(combined: sealed),
        let datagram = try? ChaChaPoly.open(box, using: key)
      else {
        // An unopenable box means the other side holds a different pairing
        // secret; nothing later on the stream can be trusted to frame right.
        fail("stream datagram unsealable")
        return
      }
      handler?(datagram)
    }
  }

  private func drainWrites() {
    lock.lock()
    guard didOpen, !writeBuffer.isEmpty else {
      lock.unlock()
      return
    }
    var buffer = writeBuffer
    lock.unlock()
    while !buffer.isEmpty, output.hasSpaceAvailable {
      let written = buffer.withUnsafeBytes { raw in
        output.write(raw.bindMemory(to: UInt8.self).baseAddress!, maxLength: buffer.count)
      }
      if written < 0 {
        fail("stream write failed \(String(describing: output.streamError))")
        return
      }
      if written == 0 { break }
      buffer.removeFirst(written)
    }
    lock.lock()
    writeBuffer = buffer
    lock.unlock()
  }

  private func fail(_ reason: String) {
    lock.lock()
    guard !cancelled else {
      lock.unlock()
      return
    }
    cancelled = true
    let handler = onFailed
    onOpen = nil
    onDatagram = nil
    onFailed = nil
    lock.unlock()
    handler?(reason)
  }

  private func shouldLogDropLocked() -> Bool {
    let now = Date()
    guard let loggedDropAt, now.timeIntervalSince(loggedDropAt) < 5 else {
      self.loggedDropAt = now
      return true
    }
    return false
  }

  enum CarrierError: Error {
    case sealFailed
  }
}
