import JavaScriptCore
import Log

struct Example {
  let context: JSContext

  init(context: JSContext, capitalCities: [String: String]) {
    self.context = context
    context["capitalCity"] = capitalCities
  }

  lazy var capitalCity: [String: String] = {
    return context["capitalCity"]!.toDictionary() as! [String: String]
  }()

  lazy var now: Date = {
    return context["now"]!.toDate()
  }()

  func thing(text: String) -> String {
    return context["thing"]!.call(withArguments: [text])!.toString()
  }

  func thingSafe(text: String) -> String? {
    guard let thing: JSValue = context["thing"] else { return nil }
    let result = thing.call(withArguments: [text])
    return result?.toString()
  }

  func subscribe(key: String, f: @escaping (String, String) -> Void) {
    let callback: @convention(block) (String, String) -> Void = { arg, name in
      return f(arg, name)
    }
    let jsCallback: JSValue = JSValue(object: callback, in: context)
    context["subscribe"]!.call(withArguments: [key, jsCallback])
  }
}
