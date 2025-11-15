import XCTest

@testable import Jotai

class JotaiTests: XCTestCase {
  @MainActor
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

  @MainActor
  func testJotaiSelectorLazy() {
    let store = JotaiStore()
    var bCallCounter = 0
    let aAtom = PrimitiveAtom(0)
    let bAtom = Atom { getter in
      bCallCounter += 1
      return getter.get(atom: aAtom) > 1
    }

    XCTAssertEqual(bCallCounter, 0)
    XCTAssertEqual(store.get(atom: bAtom), false)
    XCTAssertEqual(bCallCounter, 1)
    store.set(atom: aAtom, value: 1)
    XCTAssertEqual(bCallCounter, 1)
    XCTAssertEqual(store.get(atom: bAtom), false)
    XCTAssertEqual(bCallCounter, 2)
  }

  @MainActor
  func testJotaiSelectorEagerWhenSubbed() {
    let store = JotaiStore()
    var bCallCounter = 0
    let aAtom = PrimitiveAtom(0)
    let bAtom = Atom { getter in
      bCallCounter += 1
      return getter.get(atom: aAtom) > 1
    }
    var bSubCounter = 0
    let disposeB = store.sub(atom: bAtom) { bSubCounter += 1 }

    XCTAssertEqual(bCallCounter, 1)
    XCTAssertEqual(bSubCounter, 0)
    XCTAssertEqual(store.get(atom: bAtom), false)
    XCTAssertEqual(bCallCounter, 1)
    XCTAssertEqual(bSubCounter, 0)

    // b is still the same, so sub doesn't change
    store.set(atom: aAtom) { prev in prev + 1 }
    XCTAssertEqual(bCallCounter, 2)
    XCTAssertEqual(bSubCounter, 0)

    // b changed
    store.set(atom: aAtom) { prev in prev + 1 }
    XCTAssertEqual(bCallCounter, 3)
    XCTAssertEqual(bSubCounter, 1)

    // once disposed, resume lazy behaviour
    disposeB()
    store.set(atom: aAtom) { prev in prev + 1 }
    XCTAssertEqual(bCallCounter, 3)
    XCTAssertEqual(bSubCounter, 1)
  }

  @MainActor
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
    XCTAssertEqual(aSubCounter, 0)
    XCTAssertEqual(bSubCounter, 0)
    XCTAssertEqual(cSubCounter, 0)

    // Same value, is cached, no new evaluations
    store.set(atom: aAtom, value: 1)
    XCTAssertEqual(store.get(atom: cAtom), "false")
    XCTAssertEqual(bCallCounter, 1)
    XCTAssertEqual(cCallCounter, 1)
    XCTAssertEqual(aSubCounter, 0)
    XCTAssertEqual(bSubCounter, 0)
    XCTAssertEqual(cSubCounter, 0)

    store.set(atom: aAtom) { prev in prev + 1 }
    XCTAssertEqual(bCallCounter, 2)
    XCTAssertEqual(cCallCounter, 2)
    XCTAssertEqual(aSubCounter, 1)
    XCTAssertEqual(bSubCounter, 1)
    XCTAssertEqual(cSubCounter, 1)
    XCTAssertEqual(store.get(atom: cAtom), "true")

    store.set(atom: aAtom) { prev in prev + 1 }
    // Only child was reevaluated, cAtom is cached
    XCTAssertEqual(store.get(atom: cAtom), "true")
    XCTAssertEqual(bCallCounter, 3)
    XCTAssertEqual(cCallCounter, 2)
    XCTAssertEqual(aSubCounter, 2)
    XCTAssertEqual(bSubCounter, 1)  // same value, so subscription doesn't update
    XCTAssertEqual(cSubCounter, 1)

    disposeA()
    disposeB()
    disposeC()
    store.set(atom: aAtom) { prev in prev + 1 }
    XCTAssertEqual(store.get(atom: cAtom), "true")
    XCTAssertEqual(bCallCounter, 4)
    XCTAssertEqual(cCallCounter, 2)
    XCTAssertEqual(aSubCounter, 2)
    XCTAssertEqual(bSubCounter, 1)
    XCTAssertEqual(cSubCounter, 1)
  }

  @MainActor
  func testJotaiInvalidate() {
    let store = JotaiStore()
    var value = 0
    var counterA = 0
    var counterB = 0
    var counterC = 0
    var counterD = 0
    let aAtom = Atom { getter in
      counterA += 1
      return value
    }
    let bAtom = Atom { getter in
      counterB += 1
      return getter.get(atom: aAtom)
    }
    let cAtom = Atom { getter in
      counterC += 1
      return getter.get(atom: aAtom)
    }
    let dAtom = Atom { getter in
      counterD += 1
      return getter.get(atom: aAtom)
    }
    XCTAssertEqual(store.get(atom: bAtom), value)
    XCTAssertEqual(store.get(atom: cAtom), value)
    var dCalledCounter = 0
    let _ = store.sub(atom: dAtom) {
      dCalledCounter += 1
    }

    value += 1
    XCTAssertEqual(store.get(atom: bAtom), 0)
    XCTAssertEqual(counterA, 1)
    XCTAssertEqual(counterB, 1)
    XCTAssertEqual(counterC, 1)
    XCTAssertEqual(counterD, 1)
    XCTAssertEqual(dCalledCounter, 0)

    store.invalidate(atom: aAtom)
    // Ideally would test passing 1 second as well
    XCTAssertEqual(store.get(atom: bAtom), value)
    XCTAssertEqual(counterA, 2)
    XCTAssertEqual(counterB, 2)
    XCTAssertEqual(counterC, 1)
    XCTAssertEqual(counterD, 2)
    XCTAssertEqual(dCalledCounter, 1)
  }

  @MainActor
  func testJotaiWriteThrough() {
    let store = JotaiStore()
    var getCounter = 0
    let aAtom = PrimitiveAtom(0)
    let bAtom = WritableAtom(
      { getter in
        getCounter += 1
        return getter.get(atom: aAtom)
      },
      { setter, newValue in
        return setter.set(atom: aAtom, value: newValue)
      })

    XCTAssertEqual(getCounter, 0)
    XCTAssertEqual(store.get(atom: bAtom), 0)
    XCTAssertEqual(getCounter, 1)
    store.set(atom: bAtom, value: 1)
    XCTAssertEqual(getCounter, 1)
    XCTAssertEqual(store.get(atom: bAtom), 1)
    XCTAssertEqual(getCounter, 2)
  }
}
