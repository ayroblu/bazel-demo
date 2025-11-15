import Foundation

public struct Persist<T> {
  let key: String
  public init(key: String) {
    self.key = key
  }
  public func get() -> T? {
    return UserDefaults.standard.object(forKey: key) as? T
  }
  public func set(_ value: T?) {
    if let value {
      UserDefaults.standard.set(value, forKey: key)
    } else {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }
}
public struct PersistCodable<T: Codable> {
  let key: String
  public init(key: String) {
    self.key = key
  }
  public func get() throws -> T? {
    guard let data = UserDefaults.standard.value(forKey: key) as? Data else { return nil }
    return try PropertyListDecoder().decode(T.self, from: data)
  }
  public func set(_ value: T?) throws {
    if let value {
      UserDefaults.standard.set(try PropertyListEncoder().encode(value), forKey: key)
    } else {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }
}
public struct PersistWithDefaultState<T> {
  let key: String
  let defaultValue: T
  public init(key: String, defaultValue: T) {
    self.key = key
    self.defaultValue = defaultValue
  }
  public func get() -> T {
    return UserDefaults.standard.object(forKey: key) as? T ?? defaultValue
  }
  public func set(_ value: T?) {
    if let value {
      UserDefaults.standard.set(value, forKey: key)
    } else {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }
}
public struct PersistCodableWithDefaultState<T: Codable> {
  let key: String
  let defaultValue: T
  public init(key: String, defaultValue: T) {
    self.key = key
    self.defaultValue = defaultValue
  }
  public func get() throws -> T {
    guard let data = UserDefaults.standard.value(forKey: key) as? Data else { return defaultValue }
    return try PropertyListDecoder().decode(T.self, from: data)
  }
  public func set(_ value: T?) throws {
    if let value {
      UserDefaults.standard.set(try PropertyListEncoder().encode(value), forKey: key)
    } else {
      UserDefaults.standard.removeObject(forKey: key)
    }
  }
}
public struct PersistEnumWithDefaultState<T: RawRepresentable> {
  let key: String
  let defaultValue: T
  public init(key: String, defaultValue: T) {
    self.key = key
    self.defaultValue = defaultValue
  }
  public func get() -> T {
    guard let saved = UserDefaults.standard.object(forKey: key) as? T.RawValue else {
      return defaultValue
    }
    return T(rawValue: saved) ?? defaultValue
  }
  public func set(_ value: T) {
    UserDefaults.standard.set(value.rawValue, forKey: key)
  }
}
