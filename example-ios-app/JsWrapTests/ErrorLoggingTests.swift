import JavaScriptCore
import JsWrap
import XCTest

class ErrorLoggingTests: XCTestCase {
  func testErrorLoggingWorks() {
    let (context, errorSpy) = setup()
    XCTAssertEqual(errorSpy.calls.count, 0)
    context["run"]!.call(withArguments: [])
    XCTAssertEqual(errorSpy.calls.count, 1)
    AssertStringContains(errorSpy.calls[0][0] as! String, "index.js:2")
    let errorRegex = /TypeError: key is not a function.*\n  run@file:.*index.js:2:6/
    AssertStringMatch((errorSpy.calls[0][0] as! String), errorRegex)
  }

  private func setup() -> (JSContext, Spy<()>) {
    let errorSpy = Spy { args in }
    let context = getJsContext(onException: { errorText in errorSpy.call(errorText) })
    context.evaluateScript(
      """
      function run(key) {
        key()
      }
      """, withSourceURL: URL(filePath: "index.js"))
    return (context, errorSpy)
  }
}

class Spy<R> {
  var calls: [[Any]] = []
  var f: (_ args: Any...) -> R
  init(f: @escaping (_ args: Any...) -> R) {
    self.f = f
  }

  func call(_ args: Any...) -> R {
    return call(args: args)
  }
  func call(args: [Any]) -> R {
    calls.append(args)
    return f(args)
  }
}

func AssertStringContains(_ originalString: String, _ substring: String) {
  let why = "could not find \"\(substring)\" in \"\(originalString)\""
  XCTAssertTrue(
    originalString.contains(substring), why)
}
func AssertStringMatch(_ originalString: String, _ regex: Regex<Substring>) {
  let why = "could not match \(regex) in \"\(originalString)\""

  let result = try? regex.firstMatch(in: originalString)
  XCTAssertTrue(result != nil, why)
}
