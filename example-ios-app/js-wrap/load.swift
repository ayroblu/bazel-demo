import JavaScriptCore

let context: JSContext? = {
  let context = JSContext()
  print(Bundle.main.resourceURL)
  guard let commonJSPath = Bundle.main.path(forResource: "index", ofType: "js") else {
    print("Unable to read resource files.")
    return nil
  }
  do {
    let common = try String(contentsOfFile: commonJSPath, encoding: String.Encoding.utf8)
    _ = context?.evaluateScript(common)
  } catch {
    print("Error while processing script file: \(error)")
  }

  return context
}()
