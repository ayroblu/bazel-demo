import JavaScriptCore

let seconds = 2.0
struct User: Codable {
  let id: Int
}
func run() async {
  let context = getJsContext()
  if let context = context {
    let thing: JSValue? = context["thing"]
    context["hi"] = JSValue(object: User(id: 1), in: context)
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
  }

  try? await Task.sleep(nanoseconds: UInt64(seconds * Double(NSEC_PER_SEC)))
}
await run()
log("end")
