import Foundation

public func asyncAll<T>(_ closures: [() async -> T]) async -> [T] {
  await withTaskGroup(of: (Int, T).self) { group in
    for (index, closure) in closures.enumerated() {
      group.addTask {
        let result = await closure()
        return (index, result)
      }
    }

    var results = [Item<T>?](repeating: nil, count: closures.count)
    for await (index, result) in group {
      results[index] = Item(result: result)
    }
    return results.compactMap { $0 }.map { $0.result }
  }
}

private struct Item<T> {
  let result: T
}
