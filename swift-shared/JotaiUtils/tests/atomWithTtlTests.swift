import Jotai
import JotaiUtils
import XCTest

class AtomWithTtlTests: XCTestCase {
  @MainActor
  func testAtomWithTtl_happy() async throws {
    let store = JotaiStore()
    var counter = 0
    let testAtom = atomWithTtl(ttlS: 0.002) { getter in
      counter += 1
      return ""
    }
    _ = store.get(atom: testAtom)
    XCTAssertEqual(counter, 1)
    try await Task.sleep(for: .milliseconds(1))
    _ = store.get(atom: testAtom)
    XCTAssertEqual(counter, 1)
    try await Task.sleep(for: .milliseconds(2))
    _ = store.get(atom: testAtom)
    XCTAssertEqual(counter, 2)
  }
}
