import XCTest

@testable import g1protocol

class CommandsTests: XCTestCase {
  func testCmdListeners() {
    addListeners()
    for cmd in Cmd.allCases {
      XCTAssertNotNil(listeners[cmd], "Missing: \(cmd)")
    }
  }
}
