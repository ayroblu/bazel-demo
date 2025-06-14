import Foundation

struct Persist<T> {
  let key: String
  func get() -> T? {
    return UserDefaults.standard.object(forKey: key) as? T
  }
  func set(_ value: T) {
    UserDefaults.standard.set(value, forKey: key)
  }
}
struct PersistWithDefaultState<T> {
  let key: String
  let defaultValue: T
  func get() -> T {
    return UserDefaults.standard.object(forKey: key) as? T ?? defaultValue
  }
  func set(_ value: T) {
    UserDefaults.standard.set(value, forKey: key)
  }
}

let notifDirectPushState = PersistWithDefaultState<Bool>(
  key: "notif-direct-push", defaultValue: true)
let notifDurationSecondsState = PersistWithDefaultState<UInt8>(
  key: "notif-duration-seconds", defaultValue: 10)

let notifConfigCalendarState = PersistWithDefaultState<Bool>(
  key: "notif-config-calendar", defaultValue: true)
let notifConfigCallState = PersistWithDefaultState<Bool>(
  key: "notif-config-call", defaultValue: true)
let notifConfigMsgState = PersistWithDefaultState<Bool>(key: "notif-config-msg", defaultValue: true)
let notifConfigIosMailState = PersistWithDefaultState<Bool>(
  key: "notif-config-ios-mail", defaultValue: true)
let notifConfigAppsState = PersistWithDefaultState<Bool>(
  key: "notif-config-apps", defaultValue: true)

let reminderListsState = Persist<[String]>(key: "reminder-lists")

let userLatState = Persist<Double>(key: "user-lat")
let userLngState = Persist<Double>(key: "user-lng")
