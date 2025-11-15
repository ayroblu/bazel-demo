import Jotai
import JotaiUtils
import XCTest

class AsyncAtomTests: XCTestCase {
  @MainActor
  func testAsyncAtom_happy() async throws {
    let store = JotaiStore()
    let counterAtom = PrimitiveAtom(0)
    var numCalls = 0
    let testAtom = asyncAtom { getter async throws in
      numCalls += 1
      try await Task.sleep(for: .milliseconds(1))
      return getter.get(atom: counterAtom)
    }
    let result = try await store.get(atom: testAtom.task).value
    XCTAssertEqual(result, 0)
    XCTAssertEqual(numCalls, 1)
    _ = try await store.get(atom: testAtom.task).value
    XCTAssertEqual(numCalls, 1)
    store.set(atom: counterAtom, value: 1)
    let result2 = try await store.get(atom: testAtom.task).value
    XCTAssertEqual(result2, 1)
    XCTAssertEqual(store.get(atom: testAtom.resolved), 1)
  }

  @MainActor
  func testAsyncAtom_ttlS() async throws {
    let store = JotaiStore()
    let counterAtom = PrimitiveAtom(0)
    var numCalls = 0
    let testAtom = asyncAtom(ttlS: 0.005) { getter async throws in
      numCalls += 1
      try await Task.sleep(for: .milliseconds(1))
      return getter.get(atom: counterAtom)
    }
    let result = try await store.get(atom: testAtom.task).value
    XCTAssertEqual(result, 0)
    XCTAssertEqual(numCalls, 1)
    _ = try await store.get(atom: testAtom.task).value
    XCTAssertEqual(numCalls, 1)

    try await Task.sleep(for: .milliseconds(5))
    _ = try await store.get(atom: testAtom.task).value
    XCTAssertEqual(numCalls, 2)
  }
}

extension String: @retroactive Identifiable {
  public var id: String { self }
}
