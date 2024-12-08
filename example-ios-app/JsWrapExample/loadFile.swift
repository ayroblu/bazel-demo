import Log
import Foundation

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
