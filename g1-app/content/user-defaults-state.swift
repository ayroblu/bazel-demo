import Foundation

// @propertyWrapper
// struct StatePersisted<T> {
//   let state: Persist<T>

//   var wrappedValue: T {
//     get { state.get() }
//     set { state.set(newValue) }
//   }
// }
@propertyWrapper
class PublishedState<T> {
  let state: PersistWithDefaultState<T>

  @Published var value: T

  init(state: PersistWithDefaultState<T>, defaultValue: T) {
    self.state = state
    value = state.get(defaultValue: defaultValue)
  }

  var wrappedValue: T {
    get { value }
    set {
      state.set(newValue)
      value = newValue
    }
  }
}

// struct Persist<T> {
//   let key: String
//   func get() -> T? {
//     return UserDefaults.standard.object(forKey: key) as? T
//   }
//   func set(_ value: T) {
//     UserDefaults.standard.set(value, forKey: key)
//   }
// }
struct PersistWithDefaultState<T> {
  let key: String
  func get(defaultValue: T) -> T {
    return UserDefaults.standard.object(forKey: key) as? T ?? defaultValue
  }
  func set(_ value: T) {
    UserDefaults.standard.set(value, forKey: key)
  }
}
let notifDirectPushState = PersistWithDefaultState<Bool>(key: "notif-direct-push")
let notifDurationSecondsState = PersistWithDefaultState<UInt8>(key: "notif-duration-seconds")

struct ReminderListsState {
  static let key = "reminder-lists"
  typealias StateType = [String]
  static func get() -> StateType? {
    return UserDefaults.standard.object(forKey: key) as? StateType
  }
  static func set(_ value: StateType) {
    UserDefaults.standard.set(value, forKey: key)
  }
}

struct UserLatState {
  static let key = "user-lat"
  typealias StateType = Double
  static func get() -> StateType? {
    return UserDefaults.standard.object(forKey: key) as? StateType
  }
  static func set(_ value: StateType) {
    UserDefaults.standard.set(value, forKey: key)
  }
}
struct UserLngState {
  static let key = "user-lng"
  typealias StateType = Double
  static func get() -> StateType? {
    return UserDefaults.standard.object(forKey: key) as? StateType
  }
  static func set(_ value: StateType) {
    UserDefaults.standard.set(value, forKey: key)
  }
}
