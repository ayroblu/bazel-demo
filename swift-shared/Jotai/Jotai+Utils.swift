import Foundation

public enum AsyncState<T: Equatable>: Equatable {
  case pending(id: UUID = UUID())
  case resolved(data: T)

  public static func == (lhs: AsyncState<T>, rhs: AsyncState<T>) -> Bool {
    switch (lhs, rhs) {
    case let (.pending(id1), .pending(id2)):
      return id1 == id2
    case let (.resolved(data1), .resolved(data2)):
      return data1 == data2
    default:
      return false
    }
  }
}

public func asyncAtom<T: Equatable>(ttlS: Double? = nil, _ f: @escaping (Getter) async -> T) -> Atom<AsyncState<T>> {
  let dataAtom = PrimitiveAtom<AsyncState<T>>(.pending())
  var skipSet = false
  return Atom(ttlS: ttlS) { (getter) in
    if skipSet {
      skipSet = false
    } else {
      let pending: AsyncState<T> = .pending()
      getter.store.set(atom: dataAtom, value: pending)
      Task { @MainActor in
        let result = await f(getter)
        skipSet = true
        getter.store.set(atom: dataAtom) { prevValue in
          prevValue == pending ? .resolved(data: result) : prevValue
        }
      }
    }
    return getter.get(atom: dataAtom)
  }
}

// public func atomFamily<Key: AnyObject, Value: AnyObject>(_ f: @escaping (Key) -> Value) -> (Key) ->
//   Value
// {
//   let mapTable = NSMapTable<Key, Value>.weakToWeakObjects()
//   return { (key: Key) in
//     if let result = mapTable.object(forKey: key) {
//       return result
//     }
//     let result = f(key)
//     mapTable.setObject(result, forKey: key)
//     return result
//   }
// }

// public func atomFamily<Key: Identifiable, Value: AnyObject>(_ f: @escaping (Key) -> Value) -> (Key)
//   -> Value where Key.ID == String
// {
//   let mapTable = NSMapTable<NSString, Value>.strongToWeakObjects()
//   return { (key: Key) in
//     if let result = mapTable.object(forKey: NSString(string: key.id)) {
//       return result
//     }
//     let result = f(key)
//     mapTable.setObject(result, forKey: NSString(string: key.id))
//     return result
//   }
// }

public func atomFamily<Key: Identifiable, Value: AnyObject>(_ f: @escaping (Key) -> Value) -> (Key)
  -> Value where Key.ID == String
{
  var mapTable = [String: Value]()
  return { (key: Key) in
    if let result = mapTable[key.id] {
      return result
    }
    let result = f(key)
    mapTable[key.id] = result
    return result
  }
}
