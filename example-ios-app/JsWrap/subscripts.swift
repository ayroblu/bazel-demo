import JavaScriptCore

// https://christiantietze.de/posts/2020/06/javascriptcore-subscript-swift/
extension JSContext {
  public subscript(_ key: NSString) -> JSValue? {
    get { return objectForKeyedSubscript(key) }
  }

  public subscript(_ key: NSString) -> Any? {
    get { return objectForKeyedSubscript(key) }
    set { setObject(newValue, forKeyedSubscript: key) }
  }
}

extension JSValue {
  public subscript(_ key: NSString) -> JSValue? {
    get { return objectForKeyedSubscript(key) }
  }

  public subscript(_ key: NSString) -> Any? {
    get { return objectForKeyedSubscript(key) }
    set { setObject(newValue, forKeyedSubscript: key) }
  }
}
