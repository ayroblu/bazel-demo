import Jotai
import Log
import Synchronization
import XCTest
import db_test_lib

@testable import LogDb
@testable import LogUi

class LogAtomTests: DbTestCase {
  override var dbName: String { "logatom.sqlite" }

  @MainActor
  func setupTest() throws {
    let testDb = try createDatabase(migrations: migrations)
    db = testDb
    defaultStore = JotaiStore()
    let effects: [LogEffect] = [
      logAtomEffect
    ]
    registerLogEffects(effects: effects)
  }

  @MainActor
  func testLogAtomEffect() async throws {
    try setupTest()
    log("Something")
    var logs = defaultStore.get(atom: selectLogsAtom)
    XCTAssertEqual(logs.count, 1)
    XCTAssertEqual(logs[0].text, "I: Something")
    log("Something2")
    try await Task.sleep(for: .milliseconds(1))
    logs = defaultStore.get(atom: selectLogsAtom)
    XCTAssertEqual(logs.count, 2)
    try deleteAllLogsAndInvalidate()
    logs = defaultStore.get(atom: selectLogsAtom)
    XCTAssertEqual(logs.count, 0)
  }
}
