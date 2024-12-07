import Foundation
import JavaScriptCore
import Log

public func getJsContext() -> JSContext {
  let context: JSContext = JSContext()
  let logHandler: @convention(block) () -> Void = { () in
    guard let args = JSContext.currentArguments() else { return }
    log(["console.log:"] + args)
  }
  context["console"]?["log"] = logHandler
  context.exceptionHandler = { context, exception in
    guard let exception = exception else { return }
    log("ERR:", exception)
    if let stack: JSValue = exception["stack"] {
      log("ERR:  ", stack)
    }
  }
  setupTimers(jsContext: context)

  // TODO:
  // - Errors - stack traces
  // - tests
  // - passing dicts + primitives
  // - passing structs
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
