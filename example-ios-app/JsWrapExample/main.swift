import JavaScriptCore
import JsWrap
import Log

// TODO: get path location via env var bazel
// print(ProcessInfo.processInfo.environment)

let jsName = "index"
let jsFile = "\(jsName).js"
let dirPath = "example-ios-app/JsWrapExample"
let path = "JsWrapExample.runfiles/_main/\(dirPath)/\(jsName)"
func loadJsFile() -> String? {
  // print(Bundle.main.resourcePath)
  guard let jsPath = Bundle.main.path(forResource: path, ofType: "js") else {
    log("WARN: Unable to read resource files.")
    return nil
  }

  guard let jsContents = try? String(contentsOfFile: jsPath, encoding: String.Encoding.utf8)
  else {
    log("WARN: Could not read: \(jsPath)")
    return nil
  }
  return jsContents
}
let jsContents = loadJsFile()

let context: JSContext = getJsContext()

struct User: Codable {
  public let id: Int
}

var capitalCity = ["Nepal": "Kathmandu", "Italy": "Rome", "England": "London"]
context["capitalCity"] = JSValue(object: capitalCity, in: context)
context["structs"] = JSValue(object: User(id: 1), in: context)

context.evaluateScript(jsContents, withSourceURL: URL(filePath: "\(dirPath)/\(jsFile)"))

let thing: JSValue? = context["thing"]
if let thing = thing {
  log("thing", thing)
}
let subscribe: JSValue? = context["subscribe"]
if let subscribe = subscribe {
  let f: @convention(block) (String, String) -> Void = { arg, name in
    log("subscribe", arg, name)
  }
  let jsCallback: JSValue = JSValue(object: f, in: context)
  subscribe.call(withArguments: ["sub", jsCallback])
}

let seconds = 2.0
try? await Task.sleep(nanoseconds: UInt64(seconds * Double(NSEC_PER_SEC)))
log("end")
