import FileUtils
import Sworm
import XCTest
import db_test_lib

class DbTests: DbTestCase {
  override var dbName: String { "sworm.sqlite" }

  func testDb_migrations() throws {
    try validateMigrations(migrations: migrations)
  }

  func testDb_Success() throws {
    let db = try createDatabase(migrations: migrations)
    try db.executeOnly(insertUser(name: "my name"))
    let users = try db.execute(selectUser())
    XCTAssertEqual(users.count, 1)
    let user = users.first!
    XCTAssertEqual(user.id, 1)
    XCTAssertEqual(user.name, "my name")
  }
}

let migrations: [Migration] = [
  Migration(
    id: Date(fromISO8601String: "2025-09-01T00:40:02.014Z"),
    migrations: [
      MigrationStep(
        step: """
          CREATE TABLE user(
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            created_at INTEGER DEFAULT (unixepoch('subsec') * 1000)
          )
          """,
        rollback: """
          DROP TABLE IF EXISTS user
          """)
    ])
]

func insertUser(name: String) -> SwormExecutable {
  return SwormExecutable(statement: "INSERT INTO User (name) VALUES (?);", values: [name])
}
struct User {
  let id: Int64
  let name: String
  let createdAt: Date
}
func selectUser() -> SwormSelectable<User> {
  return SwormSelectable(
    statement: "SELECT id, name, created_at FROM User;", columns: [.long, .text, .date],
    parse: { datatypes in
      return User(
        id: try parseAny(Int64.self, datatypes[0]),
        name: try parseAny(String.self, datatypes[1]),
        createdAt: try parseAny(Date.self, datatypes[2]),
      )
    })
}
