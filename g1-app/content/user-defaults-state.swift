import Foundation
import jotai

@propertyWrapper
class PublishedState<T> {
  let state: PersistWithDefaultState<T>

  @Published var value: T

  init(state: PersistWithDefaultState<T>) {
    self.state = state
    value = state.get()
  }

  var wrappedValue: T {
    get { value }
    set {
      state.set(newValue)
      value = newValue
    }
  }
}

@MainActor
func userDefaultsAtom<T>(state: PersistWithDefaultState<T>) -> Atom<T> {
  return Atom({ state.get() }, { value in state.set(value) })
}
@MainActor
let notifDirectPushAtom = userDefaultsAtom(state: notifDurationSecondsState)
@MainActor
let notifDurationSecondsAtom = userDefaultsAtom(state: notifDurationSecondsState)
@MainActor
let notifConfigCalendarAtom = userDefaultsAtom(state: notifConfigCalendarState)
@MainActor
let notifConfigCallAtom = userDefaultsAtom(state: notifConfigCallState)
@MainActor
let notifConfigMsgAtom = userDefaultsAtom(state: notifConfigMsgState)
@MainActor
let notifConfigIosMailAtom = userDefaultsAtom(state: notifConfigIosMailState)
@MainActor
let notifConfigAppsAtom = userDefaultsAtom(state: notifConfigAppsState)
// @propertyWrapper
// struct PersistedState<T> {
//   private var value: T
//   private let subject = PassthroughSubject<T, Never>()

//   init(wrappedValue: T) {
//     self.value = wrappedValue
//   }

//   var wrappedValue: T {
//     get { value }
//     set {
//       value = newValue
//       subject.send(newValue)
//     }
//   }

//   var projectedValue: AnyPublisher<T, Never> {
//     subject.eraseToAnyPublisher()
//   }

//   var binding: Binding<T> {
//     Binding(
//       get: { self.value },
//       set: { newValue in self.wrappedValue = newValue }
//     )
//   }
// }

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
