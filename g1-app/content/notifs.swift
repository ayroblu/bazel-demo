import Foundation

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
