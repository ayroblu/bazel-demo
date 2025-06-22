import Foundation
import g1protocol
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

@MainActor
func getNotifConfig() throws -> Device.Notify.NotifConfig {
  let apps = notifConfigAppsState.get() ? try fetchNotifApps() : []
  return Device.Notify.NotifConfig(
    calendar: notifConfigCalendarState.get(),
    call: notifConfigCallState.get(),
    msg: notifConfigMsgState.get(),
    iosMail: notifConfigIosMailState.get(),
    apps: apps.map { app in (app.id, app.name) },
  )
}
// struct NotifApp {
//   let id: String
//   let name: String
// }

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
func notifConfigAtom<T>(state: PersistWithDefaultState<T>) -> WritableAtom<T, T, Void> {
  return userDefaultsAtom(state: state) {
    manager.sendNotifConfig()
  }
}
var notifDirectPush: Bool {
  JotaiStore.shared.get(atom: notifDirectPushAtom)
}
var notifDurationSeconds: UInt8 {
  JotaiStore.shared.get(atom: notifDurationSecondsAtom)
}
let notifDirectPushAtom = notifConfigAtom(state: notifDirectPushState)
let notifDurationSecondsAtom = userDefaultsAtom(state: notifDurationSecondsState)
let notifDurationSecondsDoubleAtom = DoubleUInt8CastAtom(atom: notifDurationSecondsAtom)
func notifAllowlistAtom<T>(state: PersistWithDefaultState<T>) -> WritableAtom<T, T, Void> {
  return userDefaultsAtom(state: state) {
    manager.sendAllowNotifs()
  }
}
let notifConfigCalendarAtom = notifAllowlistAtom(state: notifConfigCalendarState)
let notifConfigCallAtom = notifAllowlistAtom(state: notifConfigCallState)
let notifConfigMsgAtom = notifAllowlistAtom(state: notifConfigMsgState)
let notifConfigIosMailAtom = notifAllowlistAtom(state: notifConfigIosMailState)
let notifConfigAppsAtom = notifAllowlistAtom(state: notifConfigAppsState)

func DoubleUInt8CastAtom(atom: PrimitiveAtom<UInt8>, onSet: ((Setter, UInt8) -> Void)? = nil)
  -> WritableAtom<
    Double, Double, Void
  >
{
  return WritableAtom(
    { getter in Double(getter.get(atom: atom)) },
    { (setter, value) in
      setter.set(atom: atom, value: UInt8(value))
      onSet?(setter, UInt8(value))
    })
}
func DoubleUInt8CastAtom(atom: WritableAtom<UInt8, UInt8, Void>, onSet: ((Setter, UInt8) -> Void)? = nil)
  -> WritableAtom<
    Double, Double, Void
  >
{
  return WritableAtom(
    { getter in Double(getter.get(atom: atom)) },
    { (setter, value) in
      setter.set(atom: atom, value: UInt8(value))
      onSet?(setter, UInt8(value))
    })
}
