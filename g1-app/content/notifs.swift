import Foundation
import Jotai
import Log
import g1protocol

func onNewNotif(data: Data) async throws {
  let notif = try JSONDecoder().decode(NewNotif.self, from: data)
  let appInfo = notif.whitelist_app_add
  try await insertOrUpdateNotifApp(id: appInfo.app_identifier, name: appInfo.display_name)
  log("Inserted \(appInfo.app_identifier)")
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

var notifDirectPush: Bool {
  JotaiStore.shared.get(atom: notifDirectPushAtom)
}
var notifDurationSeconds: UInt8 {
  JotaiStore.shared.get(atom: notifDurationSecondsAtom)
}
