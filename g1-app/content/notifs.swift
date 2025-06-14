import Foundation
import jotai

func onNewNotif(manager: ConnectionManager, data: Data) async throws {
  let notif = try JSONDecoder().decode(NewNotif.self, from: data)
  let appInfo = notif.whitelist_app_add
  try await insertOrUpdateNotifApp(id: appInfo.app_identifier, name: appInfo.display_name)
  manager.sendAllowNotifs()
}
struct NewNotif: Codable {
  let whitelist_app_add: NotifAppInfo
}
struct NotifAppInfo: Codable {
  let app_identifier: String  // com.ayroblu.g1-app
  let display_name: String  // G1 Bazel App
}

func getNotifConfig() -> NotifConfig {
  return NotifConfig(
    calendar: notifConfigCalendarState.get(),
    call: notifConfigCallState.get(),
    msg: notifConfigMsgState.get(),
    iosMail: notifConfigIosMailState.get(),
    apps: notifConfigAppsState.get()
  )
}
struct NotifConfig {
  let calendar: Bool
  let call: Bool
  let msg: Bool
  let iosMail: Bool
  let apps: Bool
}
// struct NotifApp {
//   let id: String
//   let name: String
// }

@MainActor
func userDefaultsAtom<T>(state: PersistWithDefaultState<T>, f: (() -> Void)? = nil)
  -> WritableAtom<T, T, Void>
{
  let dataAtom = PrimitiveAtom(state.get())
  return WritableAtom(
    { getter in getter.get(atom: dataAtom) },
    { (setter, value) in
      state.set(value)
      setter.set(atom: dataAtom, value: value)
      f?()
    })
}
@MainActor
func notifConfigAtom<T>(state: PersistWithDefaultState<T>) -> WritableAtom<T, T, Void> {
  return userDefaultsAtom(state: state) {
    manager.sendNotifConfig()
  }
}
@MainActor
var notifDirectPush: Bool {
  JotaiStore.shared.get(atom: notifDirectPushAtom)
}
@MainActor
var notifDurationSeconds: UInt8 {
  JotaiStore.shared.get(atom: notifDurationSecondsAtom)
}
@MainActor
let notifDirectPushAtom = notifConfigAtom(state: notifDirectPushState)
@MainActor
let notifDurationSecondsAtom = userDefaultsAtom(state: notifDurationSecondsState)
@MainActor
let notifDurationSecondsDoubleAtom = DoubleUInt8CastAtom(atom: notifDurationSecondsAtom)
@MainActor
func notifAllowlistAtom<T>(state: PersistWithDefaultState<T>) -> WritableAtom<T, T, Void> {
  return userDefaultsAtom(state: state) {
    manager.sendAllowNotifs()
  }
}
@MainActor
let notifConfigCalendarAtom = notifAllowlistAtom(state: notifConfigCalendarState)
@MainActor
let notifConfigCallAtom = notifAllowlistAtom(state: notifConfigCallState)
@MainActor
let notifConfigMsgAtom = notifAllowlistAtom(state: notifConfigMsgState)
@MainActor
let notifConfigIosMailAtom = notifAllowlistAtom(state: notifConfigIosMailState)
@MainActor
let notifConfigAppsAtom = notifAllowlistAtom(state: notifConfigAppsState)

@MainActor
func DoubleUInt8CastAtom(atom: WritableAtom<UInt8, UInt8, Void>) -> WritableAtom<
  Double, Double, Void
> {
  return WritableAtom(
    { getter in Double(getter.get(atom: atom)) },
    { (setter, value) in setter.set(atom: atom, value: UInt8(value)) })
}
