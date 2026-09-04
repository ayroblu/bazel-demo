import Foundation
import Log
import MultipeerConnectivity

/// Drives the call transport without a UI, so two processes on one machine
/// can call each other. It replaces the microphone with a tone generator and
/// the speaker with a byte counter, so neither end needs audio hardware or a
/// screen. See harness/README.md.
public func runCallHarness() -> Never {
  // Line buffered so `harness > log` stays readable while it runs.
  setvbuf(stdout, nil, _IOLBF, 0)
  let arguments = HarnessArguments()
  log("harness starting", arguments.name, arguments.role, "seconds", arguments.seconds)
  let harness = CallHarness(arguments: arguments)
  harness.start()
  RunLoop.main.run()
  exit(0)
}

struct HarnessArguments {
  var name = deviceName
  var role = "caller"
  var seconds = 15.0

  init() {
    var iterator = CommandLine.arguments.dropFirst().makeIterator()
    while let flag = iterator.next() {
      let value = iterator.next()
      switch flag {
      case "--name":
        name = value ?? name
      case "--role":
        role = value ?? role
      case "--seconds":
        seconds = value.flatMap(Double.init) ?? seconds
      default:
        log("harness ignoring unknown argument", flag)
      }
    }
  }
}

final class CallHarness {
  private let arguments: HarnessArguments
  private let multipeer: MultipeerManager
  private let received = ReceivedAudio()
  private var send: (@Sendable (Data) -> Void)?
  private var toneTimer: Timer?
  private var tonePhase = 0.0
  private var startedAt = Date()

  init(arguments: HarnessArguments) {
    self.arguments = arguments
    multipeer = MultipeerManager(name: arguments.name)
  }

  func start() {
    let received = received
    multipeer.onAudioData = { data in
      received.add(data)
    }
    send = multipeer.makeSender()
    multipeer.onCallStarted = { [weak self] in
      self?.startTone()
    }
    multipeer.onCallEnded = { [weak self] in
      guard let self else { return }
      log(
        "harness call ended after", String(format: "%.1fs", Date().timeIntervalSince(startedAt)),
        multipeer.callStateSummary(), received.summary())
      stopTone()
      exit(1)
    }
    multipeer.startDiscovery()
    Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.tick()
      }
    }
    Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self, self.multipeer.connectedPeer != nil else { return }
        log("harness stats", self.multipeer.callStateSummary(), self.received.summary())
      }
    }
  }

  /// Discovery, invites and answers are all driven from one poll so the
  /// harness needs no view layer.
  private func tick() {
    if multipeer.connectedPeer != nil {
      if Date().timeIntervalSince(startedAt) > arguments.seconds {
        log("harness reached time limit, call survived", multipeer.callStateSummary())
        exit(0)
      }
      return
    }
    if let invite = multipeer.pendingInvite {
      log("harness accepting invite", invite.peer.displayName)
      multipeer.respond(invite: invite, accept: true)
      return
    }
    guard arguments.role == "caller", multipeer.connectingPeer == nil,
      let peer = multipeer.discoveredPeers.first
    else { return }
    log("harness inviting", peer.displayName)
    multipeer.invite(peer: peer)
  }

  /// 100ms of a 440Hz tone at the real transport format and rate, which is
  /// what the microphone tap would produce.
  private func startTone() {
    startedAt = Date()
    received.reset()
    stopTone()
    log("harness call connected, sending tone")
    toneTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.sendTone()
      }
    }
  }

  private func sendTone() {
    let frames = 1600
    var samples = [Int16](repeating: 0, count: frames)
    for index in 0..<frames {
      tonePhase += 2 * Double.pi * 440 / 16000
      samples[index] = Int16(sin(tonePhase) * 8000)
    }
    send?(samples.withUnsafeBytes { Data($0) })
  }

  private func stopTone() {
    toneTimer?.invalidate()
    toneTimer = nil
  }
}

nonisolated final class ReceivedAudio: @unchecked Sendable {
  private let lock = NSLock()
  private var bytes = 0
  private var firstAt: Date?
  private var lastAt: Date?
  private var longestGap = 0.0

  func add(_ data: Data) {
    let now = Date()
    lock.lock()
    bytes += data.count
    if firstAt == nil {
      firstAt = now
    }
    if let lastAt {
      longestGap = max(longestGap, now.timeIntervalSince(lastAt))
    }
    lastAt = now
    lock.unlock()
  }

  func reset() {
    lock.lock()
    bytes = 0
    firstAt = nil
    lastAt = nil
    longestGap = 0
    lock.unlock()
  }

  /// Bytes plus the worst silence, which is what a stalling link looks like
  /// before it drops entirely.
  func summary() -> String {
    lock.lock()
    defer { lock.unlock() }
    let seconds = firstAt.map { (lastAt ?? $0).timeIntervalSince($0) } ?? 0
    guard seconds >= 1 else {
      return String(format: "recv=%dkB longestGap=%.1fs", bytes / 1024, longestGap)
    }
    return String(
      format: "recv=%dkB rate=%.1fkB/s longestGap=%.1fs", bytes / 1024, Double(bytes) / seconds / 1024,
      longestGap)
  }
}
