import SwiftUI
import XCTest

@testable import Jotai

class JotaiSwiftUITests: XCTestCase {
  func testJotaiSwiftUi() {
    let view = ExampleView()
    XCTAssertEqual(view.value, 2)
    store.set(atom: testAtom, value: 3)
    XCTAssertEqual(view.value, 3)
  }

  func setupView(store: JotaiStore) -> ExampleView {
    return ExampleView()
  }
}

let store = JotaiStore()
let testAtom = PrimitiveAtom(2)
let testToggleAtom = PrimitiveAtom(true)

struct ExampleView: View {
  @AtomValue(testAtom, store: store) var value: Int
  @AtomState(testToggleAtom, store: store) var isOn: Bool

  var body: some View {
    VStack {
      Text("value: \(value)")
      Toggle(isOn: $isOn) {
        Text("Toggle")
      }
    }
  }
}
