import DateUtils
import Log
import Sworm
import XCTest
import db_test_lib

@testable import LogDb

class LogDbTests: DbTestCase {
  override var dbName: String { "logdb.sqlite" }

  func testDb_migrations() throws {
    try validateMigrations(migrations: migrations)
  }

  func setupTest() throws {
    let testDb = try createDatabase(migrations: migrations)
    db = testDb
  }

  func testDb_Success() async throws {
    try setupTest()
    let initialLogs = try selectLog()!
    XCTAssertEqual(initialLogs.count, 0)
    let _ = try insertLog(date: Date().add(by: .day, value: -8), key: "I", text: "first")
    try await Task.sleep(for: .milliseconds(1))
    let _ = try insertLog(date: Date(), key: "I", text: "second")
    let logs = try selectLog()!
    XCTAssertEqual(logs.count, 2)
    XCTAssertEqual(logs[0].text, "second")
    XCTAssertEqual(logs[1].text, "first")
    // DropOldLog
    try dropOldLog()
    let cleanedLogs = try selectLog()!
    XCTAssertEqual(cleanedLogs.count, 1)
  }

  func testSingleLog_Success() throws {
    try setupTest()
    let initialLogs = try selectLog()!
    XCTAssertEqual(initialLogs.count, 0)
    let slog = SingleLog()
    slog("first")
    slog("second")
    let logs = try selectLog()!
    XCTAssertEqual(logs.count, 1)
    XCTAssertEqual(logs[0].text, "second")
  }

  func testDeleteAllLog_Success() throws {
    try setupTest()
    let _ = try insertLog(date: Date(), key: "I", text: "first")
    let _ = try insertLog(date: Date(), key: "I", text: "second")
    let logs = try selectLog()!
    XCTAssertEqual(logs.count, 2)
    try deleteAllLogs()
    let newLogs = try selectLog()!
    XCTAssertEqual(newLogs.count, 0)
  }

  func testLogDbEffect() throws {
    try setupTest()
    let effects: [LogEffect] = [
      logDbEffect
    ]
    registerLogEffects(effects: effects)
    log("Something")
    let logs = try selectLog()!
    XCTAssertEqual(logs.count, 1)
    XCTAssertEqual(logs[0].text, "I: Something")
  }
}
