import FileUtils
import XCTest

@testable import Sworm

open class DbTestCase: XCTestCase {
  open var dbName: String { fatalError("Subclasses must override the 'dbName' property") }

  override public func setUpWithError() throws {
    var isDir: ObjCBool = false
    if !fm.fileExists(atPath: tempDirPath, isDirectory: &isDir) || !isDir.boolValue {
      try fm.createDirectory(
        atPath: tempDirPath, withIntermediateDirectories: true, attributes: nil)
    }
  }
  override public func tearDownWithError() throws {
    try rm(tempDir / dbName)
  }
}

extension DbTestCase {
  public func validateMigrations(migrations: [Migration]) throws {
    var lastDate: Date?
    for (i, mig) in migrations.enumerated() {
      if let lastDate {
        if mig.id <= lastDate {
          throw DbTestError.invalidDateMigration(index: i, date: mig.id)
        }
      }
      lastDate = mig.id
    }
    let noMigDb = try Database(name: dbName, dirPath: tempDir, migrations: [])
    var prevSchemaSql: String = try noMigDb.schema()
    for i in 1...migrations.count {
      let partialMigrations = Array(migrations.prefix(i))
      let db = try Database(name: dbName, dirPath: tempDir, migrations: partialMigrations)
      let schemaSql = try db.schema()
      if prevSchemaSql == schemaSql {
        print(schemaSql)
        throw DbTestError.noSchemaChange
      }
      let lastMigration = partialMigrations.last!
      for step in lastMigration.migrations.reversed() {
        try db.executeOnly(simpleQuery(statement: step.rollback))
        if step.isIdempotent {
          // Validate rollbacks are idemptotent
          try db.executeOnly(simpleQuery(statement: step.rollback))
        }
      }
      let rollbackSchemaSql = try db.schema()
      if prevSchemaSql != rollbackSchemaSql {
        throw DbTestError.invalidRollback
      }

      // Rerun the migrations to catch up
      for step in lastMigration.migrations {
        try db.executeOnly(simpleQuery(statement: step.step))
      }

      prevSchemaSql = schemaSql
    }

    // migrations don't run twice
    let _ = try createDatabase(migrations: migrations)
  }
}

extension DbTestCase {
  public func createDatabase(migrations: [Migration]) throws -> Database {
    return try Database(name: dbName, dirPath: tempDir, migrations: migrations)
  }
}

extension Database {
  func schema() throws -> String {
    let rows = try execute(selectSchema)
    return rows.map { $0.sql }.joined(separator: "\n")
  }
}

public enum DbTestError: Error {
  case noSchemaChange
  case invalidDateMigration(index: Int, date: Date)
  case invalidRollback
}

let fm = FileManager.default
let tempDir = fm.temporaryDirectory / (Bundle.main.bundleIdentifier ?? "__unknown__")
let tempDirPath: String = tempDir.path

struct Schema {
  let sql: String
}
let selectSchema = SwormSelectable(
  statement: "SELECT sql FROM sqlite_master WHERE type='table' ORDER BY sql;", columns: [.text],
  parse: { datatypes in
    return Schema(sql: try parseAny(String.self, datatypes[0]))
  })
