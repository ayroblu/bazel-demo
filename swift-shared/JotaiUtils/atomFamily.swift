import Foundation
import Jotai

@MainActor
public func atomFamily<Key: Hashable, Value: AnyObject>(
  _ f: @MainActor @escaping (Key) -> Value
) -> (Key) -> Value {
  var mapTable = [Key: Value]()
  return { (key: Key) in
    if let result = mapTable[key] {
      return result
    }
    let result = f(key)
    mapTable[key] = result
    return result
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

// @MainActor
// public func atomFamily<Key: Identifiable, Value: AnyObject>(
//   _ f: @MainActor @escaping (Key) -> Value
// ) -> (Key)
//   -> Value where Key.ID: StringOrUUIDIdentifiable
// {
//   var mapTable = [Key.ID: Value]()
//   let lock = NSLock()
//   return { (key: Key) in
//     lock.lock()
//     defer { lock.unlock() }
//     if let result = mapTable[key.id] {
//       return result
//     }
//     let result = f(key)
//     mapTable[key.id] = result
//     return result
//   }
// }
// public protocol StringOrUUIDIdentifiable {}
// extension String: StringOrUUIDIdentifiable {}
// extension UUID: StringOrUUIDIdentifiable {}
