import Collections
import Log
import Synchronization

public nonisolated final class AsyncQueue: Sendable {
  let queue: Mutex<Deque<() -> Task<(), Error>>> = Mutex([])
  public init() {}

  public func enqueue(f: (@Sendable @escaping () -> Task<(), Error>)) {
    let isEmpty = queue.withLock { $0.isEmpty }
    queue.withLock {
      $0.append(f)
    }
    if isEmpty {
      Task {
        try await runNext(f: f)
      }
    }
  }

  private func runNext(f: (() -> Task<(), Error>)) async throws {
    let task = f()
    await tryLog("AsyncQueue error:") { try await task.value }
    queue.withLock {
      _ = $0.popFirst()
    }
    guard let f = queue.withLock({ $0.first }) else { return }
    try await runNext(f: f)
  }
}
