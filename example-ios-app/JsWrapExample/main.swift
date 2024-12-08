import JavaScriptCore
import JsWrap
import Log

let jsContents = loadJsFile()

let context: JSContext = getJsContext()

struct User: Codable {
  let id: Int
}

let capitalCity = ["Nepal": "Kathmandu", "Italy": "Rome", "England": "London"]
context["structs"] = JSValue(object: User(id: 1), in: context)
var example = Example(context: context, capitalCities: capitalCity)

let start = CFAbsoluteTimeGetCurrent()
context.evaluateScript(jsContents, withSourceURL: URL(filePath: "\(dirPath)/\(jsFile)"))
let duration = CFAbsoluteTimeGetCurrent() - start
log("Execution time: \(duration) seconds")

log("NZ", example.capitalCity["NZ"]!)

log("thing", example.thing(text: "text"))

example.subscribe(key: "sub") { arg, name in
  log("subscribe", arg, name)
}

let seconds = 2.0
try? await Task.sleep(nanoseconds: UInt64(seconds * Double(NSEC_PER_SEC)))
log("end")
