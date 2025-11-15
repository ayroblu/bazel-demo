import FileUtils
import Foundation

extension Database {
  func createManagementTable() throws {
    let createTableString = """
      CREATE TABLE IF NOT EXISTS _sworm (
        id INTEGER PRIMARY KEY NOT NULL,
        last_migration INTEGER NOT NULL
      );
      """

    try executeOnly(simpleQuery(statement: createTableString))
  }

  func runMigrations(migrations: [Migration]) throws {
    let pendingMigrations = try getPendingMigrations(migrations: migrations)
    for mig in pendingMigrations {
      var rollbacks: [String] = []
      for step in mig.migrations {
        do {
          try executeOnly(simpleQuery(statement: step.step))
          rollbacks.append(step.rollback)
        } catch {
          print("Migration error", step, error)
          for rollback in rollbacks.reversed() {
            try executeOnly(simpleQuery(statement: rollback))
          }
          throw error
        }
      }
      try executeOnly(updateLastMigration(mig.id))
    }
  }

  private func getPendingMigrations(migrations: [Migration]) throws -> [Migration] {
    guard let date = try getLastMigration() else { return migrations }
    return Array(migrations.drop { mig in mig.id <= date })
  }

  private func getLastMigration() throws -> Date? {
    let metadata = (try execute(migrationQuery())).first
    if let metadata {
      return metadata.lastMigration
    } else {
      let insertMetadata: SwormExecutable = simpleQuery(
        statement: "INSERT OR IGNORE INTO _sworm(id, last_migration) VALUES (1, 0)")
      try executeOnly(insertMetadata)
      return nil
    }
  }
}

public struct Migration: Sendable {
  public let id: Date
  let migrations: [MigrationStep]

  public init(id: Date, migrations: [MigrationStep]) {
    self.id = id
    self.migrations = migrations
  }
}
public struct MigrationStep: Sendable {
  let step: String
  let rollback: String
  let isIdempotent: Bool

  public init(step: String, rollback: String, isIdempotent: Bool = true) {
    self.step = step
    self.rollback = rollback
    self.isIdempotent = isIdempotent
  }
}

func simpleQuery(statement: String) -> SwormExecutable {
  return SwormExecutable(statement: statement)
}

struct SwormMetadata {
  let lastMigration: Date
}

func migrationQuery() -> SwormSelectable<SwormMetadata> {
  func parse(datatypes: [Any]) throws -> SwormMetadata {
    return SwormMetadata(lastMigration: try parseAny(Date.self, datatypes[0]))
  }
  return SwormSelectable(
    statement: "SELECT last_migration FROM _sworm;",
    columns: [.date], parse: parse)

}
func updateLastMigration(_ value: Date) -> SwormExecutable {
  return SwormExecutable(statement: "UPDATE _sworm SET last_migration = ?", values: [value])
}
