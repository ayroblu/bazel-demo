import JavaScriptCore

let path = "bin.runfiles/_main/example-ios-app/js-wrap/index"
func getJsContext() -> JSContext? {
  let context: JSContext = JSContext()
  guard
    let commonJSPath = Bundle.main.path(
      forResource: path, ofType: "js")
  else {
    print("Unable to read resource files.")
    return nil
  }
  do {
    let logHandler: @convention(block) (String) -> Void = { arg in
      print(arg)
    }
    context["console"]?["log"] = logHandler
    let common = try String(contentsOfFile: commonJSPath, encoding: String.Encoding.utf8)
    _ = context.evaluateScript(common)
  } catch {
    print("Error while processing script file: \(error)")
  }

  return context
}
