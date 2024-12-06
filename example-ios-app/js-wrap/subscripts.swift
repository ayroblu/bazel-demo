import JavaScriptCore

extension JSContext {
  subscript(_ key: NSString) -> JSValue? {
    get { return objectForKeyedSubscript(key) }
  }

  subscript(_ key: NSString) -> Any? {
    get { return objectForKeyedSubscript(key) }
    set { setObject(newValue, forKeyedSubscript: key) }
  }
}

extension JSValue {
  subscript(_ key: NSString) -> JSValue? {
    get { return objectForKeyedSubscript(key) }
  }

  subscript(_ key: NSString) -> Any? {
    get { return objectForKeyedSubscript(key) }
    set { setObject(newValue, forKeyedSubscript: key) }
  }
}
