import XCTest

@testable import Jotai

class JotaiTests: XCTestCase {
  func testJotaiBasic() {
    let store = JotaiStore()
    var callCounter = 0
    let atom = Atom { getter in
      callCounter += 1
      return 1
    }
    XCTAssertEqual(store.get(atom: atom), 1)
    XCTAssertEqual(store.get(atom: atom), 1)
    XCTAssertEqual(callCounter, 1)
  }

  func testJotaiNestedDep() {
    let store = JotaiStore()
    var bCallCounter = 0
    var cCallCounter = 0
    let aAtom = PrimitiveAtom(1)
    let bAtom = Atom { getter in
      bCallCounter += 1
      return getter.get(atom: aAtom) > 1
    }
    let cAtom = Atom { getter in
      cCallCounter += 1
      return getter.get(atom: bAtom) ? "true" : "false"
    }
    var aSubCounter = 0
    var bSubCounter = 0
    var cSubCounter = 0
    let disposeA = store.sub(atom: aAtom) { aSubCounter += 1 }
    let disposeB = store.sub(atom: bAtom) { bSubCounter += 1 }
    let disposeC = store.sub(atom: cAtom) { cSubCounter += 1 }

    XCTAssertEqual(aSubCounter, 0)
    XCTAssertEqual(bSubCounter, 0)
    XCTAssertEqual(cSubCounter, 0)

    XCTAssertEqual(store.get(atom: cAtom), "false")
    XCTAssertEqual(bCallCounter, 1)
    XCTAssertEqual(cCallCounter, 1)
    XCTAssertEqual(aSubCounter, 1)
    XCTAssertEqual(bSubCounter, 1)
    XCTAssertEqual(cSubCounter, 1)

    // Same value, is cached, no new evaluations
    store.set(atom: aAtom, value: 1)
    XCTAssertEqual(store.get(atom: cAtom), "false")
    XCTAssertEqual(bCallCounter, 1)
    XCTAssertEqual(cCallCounter, 1)
    XCTAssertEqual(aSubCounter, 1)
    XCTAssertEqual(bSubCounter, 1)
    XCTAssertEqual(cSubCounter, 1)

    store.set(atom: aAtom) { prev in prev + 1 }
    // Expect atom evaluations to be lazy
    XCTAssertEqual(bCallCounter, 1)
    XCTAssertEqual(cCallCounter, 1)
    XCTAssertEqual(aSubCounter, 2)
    XCTAssertEqual(bSubCounter, 1)
    XCTAssertEqual(cSubCounter, 1)

    XCTAssertEqual(store.get(atom: cAtom), "true")
    XCTAssertEqual(bCallCounter, 2)
    XCTAssertEqual(cCallCounter, 2)
    XCTAssertEqual(aSubCounter, 2)
    XCTAssertEqual(bSubCounter, 2)
    XCTAssertEqual(cSubCounter, 2)

    store.set(atom: aAtom) { prev in prev + 1 }
    // Only child was reevaluated, cAtom is cached
    XCTAssertEqual(store.get(atom: cAtom), "true")
    XCTAssertEqual(bCallCounter, 3)
    XCTAssertEqual(cCallCounter, 2)
    XCTAssertEqual(aSubCounter, 3)
    XCTAssertEqual(bSubCounter, 2)  // same value, so subscription doesn't update
    XCTAssertEqual(cSubCounter, 2)

    disposeA()
    disposeB()
    disposeC()
    store.set(atom: aAtom) { prev in prev + 1 }
    XCTAssertEqual(store.get(atom: cAtom), "true")
    XCTAssertEqual(bCallCounter, 4)
    XCTAssertEqual(cCallCounter, 2)
    XCTAssertEqual(aSubCounter, 3)
    XCTAssertEqual(bSubCounter, 2)
    XCTAssertEqual(cSubCounter, 2)

  }
}
