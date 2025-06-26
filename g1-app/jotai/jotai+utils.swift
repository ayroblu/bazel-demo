import Foundation

public enum AsyncState<T: Equatable>: Equatable {
  case pending
  case resolved(data: T)

  public static func == (lhs: AsyncState<T>, rhs: AsyncState<T>) -> Bool {
    switch (lhs, rhs) {
    case (.pending, .pending):
      return true
    case let (.resolved(data1), .resolved(data2)):
      return data1 == data2
    default:
      return false
    }
  }
}

public func asyncAtom<T: Equatable>(_ f: @escaping (Getter) async -> T) -> Atom<AsyncState<T>> {
  let dataAtom = PrimitiveAtom<AsyncState<T>>(.pending)
  return Atom { (getter) in
    getter.store.set(atom: dataAtom, value: .pending)
    Task { @MainActor in
      let result = await f(getter)
      getter.store.set(atom: dataAtom, value: .resolved(data: result))
    }
    return getter.get(atom: dataAtom)
  }
}

public func atomFamily<Key: AnyObject, Value: AnyObject>(_ f: @escaping (Key) -> Value) -> (Key) -> Value {
  let mapTable = NSMapTable<Key, Value>.weakToWeakObjects()
  return { (key: Key) in
    if let result = mapTable.object(forKey: key) {
      return result
    }
    let result = f(key)
    mapTable.setObject(result, forKey: key)
    return result
  }
}
