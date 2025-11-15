import Foundation

public func asyncAll<T: Sendable>(
  _ closures: [@Sendable () async throws -> T],
  maxConcurrent: Int = 50,
) async throws -> [T] {
  var results = [Item<T>?](repeating: nil, count: closures.count)

  try await withThrowingTaskGroup(of: (Int, T).self) { group in
    var nextIndex = 0

    // Seed the first batch
    let initial = min(maxConcurrent, closures.count)
    for i in 0..<initial {
      group.addTask {
        let result = try await closures[i]()
        return (i, result)
      }
      nextIndex += 1
    }

    // As each task finishes, add the next one until all are scheduled
    while let (i, value) = try await group.next() {
      // results[i] = value
      results[i] = Item(result: value)

      if nextIndex < closures.count {
        let current = nextIndex
        group.addTask {
          let result = try await closures[current]()
          return (current, result)
        }
        nextIndex += 1
      }
    }
  }

  return results.map { $0!.result }
}
public func asyncAll<T: Sendable>(
  _ closures: [@Sendable () async -> T],
  maxConcurrent: Int = 50
) async -> [T] {
  var results = [Item<T>?](repeating: nil, count: closures.count)

  await withTaskGroup(of: (Int, T).self) { group in
    var nextIndex = 0

    // Seed the first batch
    let initial = min(maxConcurrent, closures.count)
    for i in 0..<initial {
      group.addTask {
        let result = await closures[i]()
        return (i, result)
      }
      nextIndex += 1
    }

    // As each task finishes, add the next one until all are scheduled
    while let (i, value) = await group.next() {
      // results[i] = value
      results[i] = Item(result: value)

      if nextIndex < closures.count {
        let current = nextIndex
        group.addTask {
          let result = await closures[current]()
          return (current, result)
        }
        nextIndex += 1
      }
    }
  }

  // Force unwrap is safe since all slots are filled
  return results.map { $0!.result }
}

public func asyncAll(
  _ closures: [@Sendable () async -> Void],
  maxConcurrent: Int = 50,
) async {
  await withTaskGroup(of: Void.self) { group in
    var runningTasks = 0

    for closure in closures {
      // Wait if we've reached the concurrency limit
      while runningTasks >= maxConcurrent {
        await group.next()
        runningTasks -= 1
      }

      runningTasks += 1
      group.addTask {
        await closure()
      }
    }

    await group.waitForAll()
  }
}

public func asyncAll(
  _ closures: [@Sendable () async throws -> Void],
  maxConcurrent: Int = 50,
) async throws {
  try await withThrowingTaskGroup(of: Void.self) { group in
    var runningTasks = 0

    for closure in closures {
      // Wait if we've reached the concurrency limit
      while runningTasks >= maxConcurrent {
        try await group.next()
        runningTasks -= 1
      }

      runningTasks += 1
      group.addTask {
        try await closure()
      }
    }

    try await group.waitForAll()
  }
}

private struct Item<T> {
  let result: T
}
