import CoreServices
import Foundation

nonisolated func scanApplications() -> [Candidate] {
  var paths: [String] = []
  for root in applicationDirectories {
    collectApplications(in: root, depth: 0, into: &paths)
  }
  paths.append("/System/Library/CoreServices/Finder.app")
  paths += spotlightApplications()

  var seenPaths = Set<String>()
  var seenBundleIds = Set<String>()
  return paths.compactMap { path in
    guard seenPaths.insert((path as NSString).resolvingSymlinksInPath).inserted else { return nil }
    let info = NSDictionary(contentsOfFile: path + "/Contents/Info.plist")
    if let bundleId = info?["CFBundleIdentifier"] as? String {
      guard seenBundleIds.insert(bundleId).inserted else { return nil }
    }
    let fileName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    let displayName = FileManager.default.displayName(atPath: path)
    let name = displayName.hasSuffix(".app") ? fileName : displayName
    return Candidate(item: fileItem(path: path, title: name), names: searchNames(name, fileName))
  }
}

private nonisolated let applicationDirectories = [
  "/Applications", "/System/Applications", NSHomeDirectory() + "/Applications",
  "/System/Library/CoreServices/Applications",
]

private nonisolated func collectApplications(
  in directory: String, depth: Int, into paths: inout [String]
) {
  guard let items = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
    return
  }
  for item in items where !item.hasPrefix(".") {
    let path = directory + "/" + item
    if item.hasSuffix(".app") {
      paths.append(path)
    } else if depth < 2, isDirectory(path) {
      collectApplications(in: path, depth: depth + 1, into: &paths)
    }
  }
}

private nonisolated func isDirectory(_ path: String) -> Bool {
  var isDirectory: ObjCBool = false
  return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
    && isDirectory.boolValue
}

private nonisolated func spotlightApplications() -> [String] {
  let query = MDQueryCreate(
    kCFAllocatorDefault, "kMDItemContentType == \"com.apple.application-bundle\"" as CFString,
    nil, nil)!
  MDQuerySetSearchScope(query, [kMDQueryScopeComputer] as [CFString] as CFArray, 0)
  MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue))
  return (0..<MDQueryGetResultCount(query)).compactMap { index in
    let item = unsafeBitCast(MDQueryGetResultAtIndex(query, index), to: MDItem.self)
    guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String, isStandaloneApp(path)
    else { return nil }
    return path
  }
}

private nonisolated func isStandaloneApp(_ path: String) -> Bool {
  !path.hasPrefix("/System/") && !path.hasPrefix("/private/")
    && !excludedPathParts.contains { path.contains($0) }
}

private nonisolated let excludedPathParts = [".app/", "/Library/", "/.", "/node_modules/"]
