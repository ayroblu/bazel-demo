import Foundation
import Log
import Sworm

@MainActor
public func initLogDb() {
  db = try? Database(name: dbName, migrations: migrations)
  try? dropOldLog()
}

let dbName = "logs.sqlite"
let migrations: [Migration] = [
  Migration(
    id: Date(fromISO8601String: "2025-09-07T18:59:02.014Z"),
    migrations: [
      MigrationStep(
        step: """
          CREATE TABLE log(
            id INTEGER PRIMARY KEY,
            key TEXT NOT NULL,
            text TEXT NOT NULL,
            created_at INTEGER DEFAULT (unixepoch('subsec') * 1000)
          )
          """,
        rollback: """
          DROP TABLE IF EXISTS log
          """)
    ])
]
nonisolated(unsafe) var db: Database?

func insertLogExecutable(date: Date, key: String, text: String) -> SwormSelectable<LogIdModel> {
  return SwormSelectable(
    statement: "INSERT INTO log (key, text, created_at) VALUES (?, ?, ?) RETURNING id;",
    values: [key, text, date],
    columns: [.long],
    parse: { datatypes in
      return LogIdModel(
        id: try parseAny(Int64.self, datatypes[0]),
      )
    })
}
public struct LogIdModel: Sendable, Identifiable {
  public let id: Int64
}

func selectLogSelectable() -> SwormSelectable<LogModel> {
  return SwormSelectable(
    statement: "SELECT id, text, created_at FROM log ORDER BY created_at DESC;",
    columns: [.long, .text, .date],
    parse: { datatypes in
      return LogModel(
        id: try parseAny(Int64.self, datatypes[0]),
        text: try parseAny(String.self, datatypes[1]),
        createdAt: try parseAny(Date.self, datatypes[2]),
      )
    })
}
public struct LogModel: Identifiable, Equatable {
  public let id: Int64
  public let text: String
  public let createdAt: Date
}

func dropOldLogExecutable() -> SwormExecutable {
  return SwormExecutable(
    statement: "DELETE FROM log WHERE created_at < strftime('%s', 'now', '-7 days') * 1000;")
}

func deleteLogByIdExecutable(_ id: Int64) -> SwormExecutable {
  return SwormExecutable(statement: "DELETE FROM log WHERE id = ?;", values: [id])
}

func deleteAllExecutable() -> SwormExecutable {
  return SwormExecutable(statement: "DELETE FROM log;")
}

public func selectLog() throws -> [LogModel]? {
  return try db?.execute(selectLogSelectable())
}
public func insertLog(date: Date, key: String, text: String) throws -> LogIdModel? {
  let result = try db?.execute(insertLogExecutable(date: date, key: key, text: text))
  return result?.first
}
public func dropOldLog() throws {
  try db?.executeOnly(dropOldLogExecutable())
}
public func deleteLogById(_ id: Int64) throws {
  try db?.executeOnly(deleteLogByIdExecutable(id))
}
public func deleteAllLogs() throws {
  try db?.executeOnly(deleteAllExecutable())
}
