import Foundation
import Log

nonisolated final class BlockBox: NSObject, @unchecked Sendable {
  let block: () -> Void
  init(_ block: @escaping () -> Void) {
    self.block = block
  }
}

/// One run loop thread owns all stream IO, so bytes never travel through the
/// main thread or an audio render thread.
nonisolated final class StreamThread: NSObject, @unchecked Sendable {
  static let shared = StreamThread()
  private let lock = NSLock()
  private var thread: Thread?

  private func runLoopThread() -> Thread {
    lock.lock()
    defer { lock.unlock() }
    if let thread {
      return thread
    }
    let ready = DispatchSemaphore(value: 0)
    let thread = Thread {
      RunLoop.current.add(NSMachPort(), forMode: .default)
      ready.signal()
      while !Thread.current.isCancelled {
        RunLoop.current.run(mode: .default, before: .distantFuture)
      }
    }
    thread.name = "call-audio-stream"
    thread.qualityOfService = .userInitiated
    thread.start()
    ready.wait()
    self.thread = thread
    return thread
  }

  func run(_ block: @escaping () -> Void) {
    perform(
      #selector(runBlock(_:)), on: runLoopThread(), with: BlockBox(block), waitUntilDone: false)
  }

  @objc private func runBlock(_ box: BlockBox) {
    box.block()
  }
}

struct AudioStreamStats: Sendable {
  var bytesSent = 0
  var bytesDropped = 0
  var bytesReceived = 0
  var lastSendAt: Date?
  var lastReceiveAt: Date?
  var isOutputOpen = false
  var isInputOpen = false
}

/// Writes captured audio to the peer over an `MCSession` byte stream. Audio
/// is queued from the capture thread and written on the stream thread; the
/// queue is capped because anything older than that is stale by the time it
/// would reach the wire.
nonisolated final class AudioOutputStream: NSObject, StreamDelegate, @unchecked Sendable {
  private let stream: OutputStream
  private let peerName: String
  private let lock = NSLock()
  private var pending = Data()
  private var isOpen = false
  private var bytesSent = 0
  private var bytesDropped = 0
  private var lastSendAt: Date?
  private var loggedDropAt: Date?
  private var onClosed: (@Sendable (String) -> Void)?

  /// 200ms of 16kHz mono Int16 audio.
  private let maxPendingBytes = 6400

  init(stream: OutputStream, peerName: String) {
    self.stream = stream
    self.peerName = peerName
    super.init()
    StreamThread.shared.run { [weak self] in
      guard let self else { return }
      self.stream.delegate = self
      self.stream.schedule(in: .current, forMode: .default)
      self.stream.open()
    }
  }

  func setOnClosed(_ handler: (@Sendable (String) -> Void)?) {
    lock.lock()
    onClosed = handler
    lock.unlock()
  }

  private func notifyClosed(_ reason: String) {
    lock.lock()
    isOpen = false
    let handler = onClosed
    lock.unlock()
    handler?(reason)
  }

  /// Captures self so the stream cannot outlive its delegate, which the
  /// Foundation streams hold unowned.
  func close() {
    setOnClosed(nil)
    StreamThread.shared.run { [self] in
      stream.close()
      stream.remove(from: .current, forMode: .default)
      stream.delegate = nil
    }
  }

  func send(_ data: Data) {
    lock.lock()
    pending.append(data)
    var dropped = 0
    if pending.count > maxPendingBytes {
      dropped = pending.count - maxPendingBytes
      pending.removeFirst(dropped)
      bytesDropped += dropped
    }
    let shouldLogDrop = dropped > 0 && shouldLogDropLocked()
    lock.unlock()
    if shouldLogDrop {
      log("audio stream send queue full, dropping", dropped, "bytes")
    }
    StreamThread.shared.run { [weak self] in
      self?.drain()
    }
  }

  private func shouldLogDropLocked() -> Bool {
    let now = Date()
    guard let loggedDropAt, now.timeIntervalSince(loggedDropAt) < 5 else {
      self.loggedDropAt = now
      return true
    }
    return false
  }

  func stats() -> (sent: Int, dropped: Int, lastSendAt: Date?, isOpen: Bool) {
    lock.lock()
    defer { lock.unlock() }
    return (bytesSent, bytesDropped, lastSendAt, isOpen)
  }

  private func drain() {
    lock.lock()
    let isOpen = isOpen
    lock.unlock()
    guard isOpen else { return }
    while stream.hasSpaceAvailable {
      lock.lock()
      let chunk = pending
      pending = Data()
      lock.unlock()
      guard !chunk.isEmpty else { return }
      let written = chunk.withUnsafeBytes { raw -> Int in
        guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
        return stream.write(base, maxLength: chunk.count)
      }
      if written <= 0 {
        log("audio stream write failed", peerName, written, String(describing: stream.streamError))
        lock.lock()
        pending = chunk + pending
        lock.unlock()
        return
      }
      lock.lock()
      bytesSent += written
      lastSendAt = Date()
      let isPartial = written < chunk.count
      if isPartial {
        pending = chunk.suffix(from: chunk.startIndex + written) + pending
      }
      lock.unlock()
      if isPartial {
        return
      }
    }
  }

  func stream(_ stream: Stream, handle event: Stream.Event) {
    switch event {
    case .openCompleted:
      lock.lock()
      isOpen = true
      lock.unlock()
      log("audio stream out opened", peerName)
      drain()
    case .hasSpaceAvailable:
      drain()
    case .errorOccurred:
      let reason = "out error \(String(describing: stream.streamError))"
      log("audio stream out error", peerName, reason)
      notifyClosed(reason)
    case .endEncountered:
      log("audio stream out ended", peerName)
      notifyClosed("out ended")
    default:
      break
    }
  }
}

/// Reads the peer's audio off an `MCSession` byte stream. The stream carries
/// a raw 16kHz mono Int16 sample run, so reads are handed on as-is except for
/// a trailing odd byte, which is held back until its pair arrives.
nonisolated final class AudioInputStream: NSObject, StreamDelegate, @unchecked Sendable {
  private let stream: InputStream
  private let peerName: String
  private let onData: @Sendable (Data) -> Void
  private var scratch = [UInt8](repeating: 0, count: 4096)
  private var leftover: UInt8?
  private let lock = NSLock()
  private var bytesReceived = 0
  private var lastReceiveAt: Date?
  private var isOpen = false
  private var onClosed: (@Sendable (String) -> Void)?

  init(stream: InputStream, peerName: String, onData: @escaping @Sendable (Data) -> Void) {
    self.stream = stream
    self.peerName = peerName
    self.onData = onData
    super.init()
    StreamThread.shared.run { [weak self] in
      guard let self else { return }
      self.stream.delegate = self
      self.stream.schedule(in: .current, forMode: .default)
      self.stream.open()
    }
  }

  func setOnClosed(_ handler: (@Sendable (String) -> Void)?) {
    lock.lock()
    onClosed = handler
    lock.unlock()
  }

  private func notifyClosed(_ reason: String) {
    lock.lock()
    isOpen = false
    let handler = onClosed
    lock.unlock()
    handler?(reason)
  }

  /// Captures self so the stream cannot outlive its delegate, which the
  /// Foundation streams hold unowned.
  func close() {
    setOnClosed(nil)
    StreamThread.shared.run { [self] in
      stream.close()
      stream.remove(from: .current, forMode: .default)
      stream.delegate = nil
    }
  }

  func stats() -> (received: Int, lastReceiveAt: Date?, isOpen: Bool) {
    lock.lock()
    defer { lock.unlock() }
    return (bytesReceived, lastReceiveAt, isOpen)
  }

  private func readAvailable() {
    while stream.hasBytesAvailable {
      let count = stream.read(&scratch, maxLength: scratch.count)
      guard count > 0 else {
        if count < 0 {
          log("audio stream read failed", peerName, String(describing: stream.streamError))
        }
        return
      }
      lock.lock()
      bytesReceived += count
      lastReceiveAt = Date()
      lock.unlock()
      var data = Data()
      if let leftover {
        data.append(leftover)
        self.leftover = nil
      }
      data.append(contentsOf: scratch[0..<count])
      if data.count % 2 == 1 {
        leftover = data.removeLast()
      }
      if !data.isEmpty {
        onData(data)
      }
    }
  }

  func stream(_ stream: Stream, handle event: Stream.Event) {
    switch event {
    case .openCompleted:
      lock.lock()
      isOpen = true
      lock.unlock()
      log("audio stream in opened", peerName)
    case .hasBytesAvailable:
      readAvailable()
    case .errorOccurred:
      let reason = "in error \(String(describing: stream.streamError))"
      log("audio stream in error", peerName, reason)
      notifyClosed(reason)
    case .endEncountered:
      log("audio stream in ended", peerName)
      notifyClosed("in ended")
    default:
      break
    }
  }
}

/// The capture thread writes here; the stream behind it is swapped on the
/// main actor as calls come and go.
nonisolated final class AudioStreamSink: @unchecked Sendable {
  private let lock = NSLock()
  private var stream: AudioOutputStream?

  func set(_ stream: AudioOutputStream?) {
    lock.lock()
    self.stream = stream
    lock.unlock()
  }

  func send(_ data: Data) {
    lock.lock()
    let stream = stream
    lock.unlock()
    stream?.send(data)
  }
}
