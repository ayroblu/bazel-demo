import DateUtils
import Foundation
import Jotai
import Sworm
import XCTest
import db_test_lib

@testable import KVCache

@MainActor
class KVCacheDbTests: DbTestCase {
  override var dbName: String { "kvcache.sqlite" }

  func testDb_migrations() throws {
    try validateMigrations(migrations: migrations)
  }

  func setupTest() throws -> JotaiStore {
    let store = JotaiStore()
    let testDb = try createDatabase(migrations: migrations)
    db = testDb
    XCTAssertEqual(getCacheItem(key: key, store: store), nil)
    return store
  }

  func testDb_Success() async throws {
    let store = try setupTest()
    try setItem(key: key, value: data, ttl: Date().addingTimeInterval(100), store: store)
    XCTAssertEqual(getCacheItem(key: key, store: store), data)
  }

  func testDb_SetMultipleTimes() async throws {
    let store = try setupTest()
    let date = Date().addingTimeInterval(100)
    try setItem(key: key, value: data, ttl: date, store: store)
    try setItem(key: key, value: data, ttl: date, store: store)
    try setItem(key: key, value: data, ttl: date, store: store)
    XCTAssertEqual(getCacheItem(key: key, store: store), data)
  }

  func testDb_DeleteItemByKey() async throws {
    let store = try setupTest()
    try setItem(key: key, value: data, ttl: Date().addingTimeInterval(100), store: store)
    XCTAssertEqual(getCacheItem(key: key, store: store), data)
    try deleteItemByKey(key, store: store)
    XCTAssertEqual(getCacheItem(key: key, store: store), nil)
  }

  func testDb_TtlOut() async throws {
    let store = try setupTest()
    try setItem(key: key, value: data, ttl: Date().addingTimeInterval(-100), store: store)
    XCTAssertEqual(getCacheItem(key: key, store: store), nil)
  }

  func testDb_DeleteExpiredItems() async throws {
    let store = try setupTest()
    try setItem(key: key, value: data, ttl: Date().addingTimeInterval(-100), store: store)
    XCTAssertNotEqual(try selectItemByKey(key), nil)
    try deleteExpiredItems()
    XCTAssertEqual(try selectItemByKey(key), nil)
  }
}
let key = "key"
let data = Data([0x56])
