import Foundation
import Sworm

let dbName = "kvcache.sqlite"
let migrations: [Migration] = [
  Migration(
    id: Date(fromISO8601String: "2025-09-18T10:33:54.032Z"),
    migrations: [
      MigrationStep(
        step: """
          CREATE TABLE kvcache(
            key TEXT PRIMARY KEY,
            value BLOB NOT NULL,
            ttl INTEGER NOT NULL
          )
          """,
        rollback: """
          DROP TABLE IF EXISTS kvcache
          """),
      MigrationStep(
        step: """
          CREATE INDEX idx_kvcache_ttl ON kvcache(ttl);
          """,
        rollback: """
          DROP INDEX IF EXISTS idx_kvcache_ttl
          """),
    ])
]
var db: Database?

func setItemExecutable(key: String, value: Data, ttl: Date) -> SwormExecutable {
  return SwormExecutable(
    statement: """
      INSERT INTO kvcache (key, value, ttl)
        VALUES (?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET
          value = excluded.value,
          ttl   = excluded.ttl;
      """, values: [key, value, ttl])
}

struct CacheValueModel: Equatable {
  let key: String
  let value: Data
  let ttl: Date
}
func selectCacheItem(key: String) -> SwormSelectable<CacheValueModel> {
  return SwormSelectable(
    statement: "SELECT key, value, ttl FROM kvcache WHERE key = ?;", values: [key],
    columns: [.text, .blob, .date],
    parse: { datatypes in
      return CacheValueModel(
        key: try parseAny(String.self, datatypes[0]),
        value: try parseAny(Data.self, datatypes[1]),
        ttl: try parseAny(Date.self, datatypes[2]),
      )
    })
}
func deleteExpiredItemsExecutable() -> SwormExecutable {
  return SwormExecutable(
    statement: """
      DELETE FROM kvcache WHERE ttl < (unixepoch('subsec') * 1000);
      """)
}
func deleteItemByKeyExecutable(_ key: String) -> SwormExecutable {
  return SwormExecutable(
    statement: "DELETE FROM kvcache WHERE key = ?;", values: [key])
}
