import JavaScriptCore
import JsWrap
import XCTest

class SetTimeoutTests: XCTestCase {
  func testSetTimeoutWorks() {
    let context = setup()
    XCTAssertEqual(context["result1"]!.toBool(), false)
    XCTAssertEqual(context["result2"]!.toBool(), false)
    context["run"]!.call(withArguments: [])
    XCTAssertEqual(context["result1"]!.toBool(), true)
    XCTAssertEqual(context["result2"]!.toBool(), false)
    wait(delayMs: 10)
    XCTAssertEqual(context["result2"]!.toBool(), true)
  }

  func testClearTimeoutWorks() {
    let context = setup()
    XCTAssertEqual(context["result1"]!.toBool(), false)
    XCTAssertEqual(context["result2"]!.toBool(), false)
    XCTAssertEqual(context["result3"]!.toBool(), false)
    context["run"]!.call(withArguments: [])
    XCTAssertEqual(context["result1"]!.toBool(), true)
    XCTAssertEqual(context["result2"]!.toBool(), false)
    XCTAssertEqual(context["result3"]!.toBool(), false)
    context["clear"]!.call(withArguments: [])
    XCTAssertEqual(context["result3"]!.toBool(), true)
    wait(delayMs: 10)
    XCTAssertEqual(context["result2"]!.toBool(), false)
  }

  private func setup() -> JSContext {
    let context = getJsContext()
    context.evaluateScript(
      """
      result1 = false
      result2 = false
      result3 = false
      let timeoutId;
      function run() {
        result1 = true
        timeoutId = setTimeout(() => {
          result2 = true
        }, 10)
      }
      function clear() {
        result3 = true
        clearTimeout(timeoutId)
      }
      """, withSourceURL: URL(filePath: "index.js"))
    return context
  }

  private func wait(delayMs: Int) {
    let expectation = expectation(description: "Test")

    let timer = DispatchSource.makeTimerSource()
    timer.schedule(deadline: .now() + .milliseconds(delayMs))
    timer.setEventHandler {
      expectation.fulfill()
    }
    timer.activate()
    waitForExpectations(timeout: 1)
  }
}
