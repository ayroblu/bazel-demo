import Jotai
import JotaiUtils
import XCTest

class AtomFamilyTests: XCTestCase {
  @MainActor
  func testAtomFamily_happy() {
    let store = JotaiStore()
    let testAtom = atomFamily { (key: String) in PrimitiveAtom(0) }
    store.set(atom: testAtom("2"), value: 2)
    XCTAssertEqual(store.get(atom: testAtom("0")), 0)
    XCTAssertEqual(store.get(atom: testAtom("2")), 2)
  }
}
