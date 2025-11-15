import Synchronization

public final class SyncDict<Key: Hashable & Sendable, Value: Sendable>: Sendable {
  let mutexDict = Mutex([Key: Value]())

  public init() {}

  public subscript(_ key: Key) -> Value? {
    get {
      mutexDict.withLock {
        $0[key]
      }
    }
    set {
      mutexDict.withLock {
        $0[key] = newValue
      }
    }
  }
}
