import Foundation
import Jotai
import JotaiUtils
import Log
import Sworm

public func initKvCache() {
  db = try? Database(name: dbName, migrations: migrations)
  try? deleteExpiredItems()
}

// Not sure why this is necessary? swift compiler crash
@MainActor
public func getWithCache(
  key: String, f: () async throws -> (Data, Date), store: JotaiStore = JotaiStore.shared
) async throws -> Data {
  if let item = getCacheItem(key: key, store: store) {
    return item
  }
  let (data, ttl) = try await f()
  try setItem(key: key, value: data, ttl: ttl, store: store)
  return data
}

func getCacheItem(key: String, store: JotaiStore) -> Data? {
  guard let item = store.get(atom: selectCacheItemAtom(key)) else { return nil }
  if item.ttl < Date() { return nil }
  return item.value
}
let selectCacheItemAtom = atomFamily { (key: String) in
  Atom { getter in
    return tryLog("selectCacheItemAtom(\(key))") { try selectItemByKey(key) }
  }
}
func setItem(key: String, value: Data, ttl: Date, store: JotaiStore) throws {
  guard let db else { return }
  try db.executeOnly(setItemExecutable(key: key, value: value, ttl: ttl))
  store.invalidate(atom: selectCacheItemAtom(key))
}
func selectItemByKey(_ key: String) throws -> CacheValueModel? {
  return (try db?.execute(selectCacheItem(key: key)))?.first
}
func deleteItemByKey(_ key: String, store: JotaiStore) throws {
  guard let db else { return }
  try db.executeOnly(deleteItemByKeyExecutable(key))
  store.invalidate(atom: selectCacheItemAtom(key))
}
func deleteExpiredItems() throws {
  guard let db else { return }
  try db.executeOnly(deleteExpiredItemsExecutable())
}
