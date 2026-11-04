import Foundation

nonisolated func scanSettingsPanes() -> [Candidate] {
  let urls =
    (try? FileManager.default.contentsOfDirectory(
      at: extensionsDirectory, includingPropertiesForKeys: nil)) ?? []
  return urls.compactMap { url in
    guard url.pathExtension == "appex",
      let info = NSDictionary(contentsOf: url.appending(path: "Contents/Info.plist"))
        as? [String: Any],
      let attributes = info["EXAppExtensionAttributes"] as? [String: Any],
      attributes["EXExtensionPointIdentifier"] as? String == "com.apple.Settings.extension.ui",
      (attributes["SettingsExtensionAttributes"] as? [String: Any])?[
        "allowsXAppleSystemPreferencesURLScheme"] as? Bool == true,
      let bundleId = info["CFBundleIdentifier"] as? String,
      let name = paneNames[bundleId] ?? localizedName(of: url)
    else { return nil }
    let item = ResultItem(
      id: "settings:" + bundleId, title: name, subtitle: "System Settings", icon: .file(url.path),
      action: .open(URL(string: "x-apple.systempreferences:" + bundleId)!))
    return Candidate(item: item, names: searchNames(name))
  }
}

private nonisolated let extensionsDirectory = URL(
  fileURLWithPath: "/System/Library/ExtensionKit/Extensions")

private nonisolated let paneNames = [
  "com.apple.Battery-Settings.extension": "Battery",
  "com.apple.HeadphoneSettings": "Headphones",
  "com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension": "VPN",
  "com.apple.SecurityImprovements-Settings.extension": "Background Security Improvements",
  "com.apple.Touch-ID-Settings.extension": "Touch ID & Password",
  "com.apple.systempreferences.AppleIDSettings": "Apple Account",
]

private nonisolated func localizedName(of appex: URL) -> String? {
  guard
    let table = NSDictionary(
      contentsOf: appex.appending(path: "Contents/Resources/InfoPlist.loctable"))
      as? [String: [String: Any]],
    let localization = Bundle.preferredLocalizations(from: Array(table.keys)).first
  else { return nil }
  return table[localization]?["CFBundleDisplayName"] as? String
}
