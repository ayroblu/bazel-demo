import Foundation
import JavaScriptCore

func getJsContext() -> JSContext? {
  let jsContents = loadJsFile()

  let context = setupJsContext()

  context.evaluateScript(jsContents)

  return context
}

let path = "bin.runfiles/_main/example-ios-app/js-wrap/index"
func loadJsFile() -> String? {
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

func setupJsContext() -> JSContext {
  let context: JSContext = JSContext()
  let logHandler: @convention(block) (String) -> Void = { arg in
    log("console.log: \(arg)")
  }
  context["console"]?["log"] = logHandler
  context.exceptionHandler = { context, exception in
    guard let exception = exception else { return }
    log("ERR: \(exception)")
  }
  setupTimers(jsContext: context)
  return context
}

func setupTimers(jsContext: JSContext) {
  var counter = 0
  func getId() -> Int {
    let key = counter
    counter += 1
    return key
  }
  // For correctness probably should have two time dicts
  var timers = [Int: Timer]()
  let setTimeout: @convention(block) (JSValue, Double) -> Int = { callback, delayMs in
    let delaySecs = delayMs / 1000.0
    let key = getId()
    let work = DispatchWorkItem {
      timers.removeValue(forKey: key)
      callback.call(withArguments: [])
    }
    DispatchQueue.main.async {
      let timer = Timer.scheduledTimer(withTimeInterval: delaySecs, repeats: false) { timer in
        work.perform()
      }
      timers[key] = timer
    }
    return key
  }
  jsContext["setTimeout"] = setTimeout
  let clearTimeout: @convention(block) (Int) -> Void = { key in
    timers.removeValue(forKey: key)?.invalidate()
  }
  jsContext["clearTimeout"] = clearTimeout

  let setInterval: @convention(block) (JSValue, Double) -> Int = { callback, intervalMs in
    let intervalSecs = intervalMs / 1000.0
    let key = getId()
    let work = DispatchWorkItem {
      timers.removeValue(forKey: key)
      callback.call(withArguments: [])
    }
    DispatchQueue.main.async {
      let timer = Timer.scheduledTimer(withTimeInterval: intervalSecs, repeats: true) { _ in
        work.perform()
      }
      timers[key] = timer
    }
    return key
  }
  jsContext["setInterval"] = setInterval
  let clearInterval: @convention(block) (Int) -> Void = { key in
    timers.removeValue(forKey: key)?.invalidate()
  }
  jsContext["clearInterval"] = clearInterval
}
