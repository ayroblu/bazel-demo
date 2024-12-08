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

  return context
}

func setupTimers(jsContext: JSContext) {
  var counter = 0
  func getId() -> Int {
    let key = counter
    counter += 1
    return key
  }
  // https://stackoverflow.com/questions/55131532/difference-between-dispatchsourcetimer-timer-and-asyncafter
  var intervalTimers = [Int: DispatchSourceTimer]()
  var timeoutTimers = [Int: DispatchSourceTimer]()
  let setTimeout: @convention(block) (JSValue, Int) -> Int = { callback, delayMs in
    let key = getId()
    let timer = DispatchSource.makeTimerSource()
    timer.schedule(deadline: .now() + .milliseconds(delayMs))
    timer.setEventHandler {
      intervalTimers.removeValue(forKey: key)
      callback.call(withArguments: [])
    }
    timer.activate()
    timeoutTimers[key] = timer
    return key
  }
  jsContext["setTimeout"] = setTimeout
  let clearTimeout: @convention(block) (Int) -> Void = { key in
    timeoutTimers.removeValue(forKey: key)?.cancel()
  }
  jsContext["clearTimeout"] = clearTimeout

  let setInterval: @convention(block) (JSValue, Int) -> Int = { callback, intervalMs in
    let key = getId()
    let timer = DispatchSource.makeTimerSource()
    timer.schedule(
      deadline: .now() + .milliseconds(intervalMs), repeating: .milliseconds(intervalMs))
    timer.setEventHandler {
      intervalTimers.removeValue(forKey: key)
      callback.call(withArguments: [])
    }
    timer.activate()
    intervalTimers[key] = timer
    return key
  }
  jsContext["setInterval"] = setInterval
  let clearInterval: @convention(block) (Int) -> Void = { key in
    intervalTimers.removeValue(forKey: key)?.cancel()
  }
  jsContext["clearInterval"] = clearInterval
}
