import SwiftUI
import XCTest

@testable import Jotai

class JotaiSwiftUITests: XCTestCase {
  @MainActor
  func testJotaiSwiftUi() {
    let view = ExampleView()
    XCTAssertEqual(view.value, 2)
    store.set(atom: testAtom, value: 3)
    XCTAssertEqual(view.value, 3)
  }

  @MainActor
  func setupView(store: JotaiStore) -> ExampleView {
    return ExampleView()
  }
}

@MainActor private let store = JotaiStore()
@MainActor private let testAtom = PrimitiveAtom(2)
@MainActor private let testToggleAtom = PrimitiveAtom(true)

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
