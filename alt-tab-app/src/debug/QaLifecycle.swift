#if DEBUG
import Cocoa
import Security

/// Lifecycle QA keeps the real app, storage and UI. Permission replies and request effects
/// stay in memory. Opt-in only, for a UUID-scoped live QA session.
enum QaLifecycle {
    static let session = CommandLine.arguments.first { $0.hasPrefix("--qa-lifecycle-session=") }
        .flatMap { UUID(uuidString: String($0.dropFirst("--qa-lifecycle-session=".count)))?.uuidString }
    static var enabled: Bool { session != nil }
    static var finishedLaunching = false
    static var actions = [String]()
    static var launchCount = 0
    private static let permissionLock = NSLock()
    private static var permissionValues: [Bool] = {
        let mode = CommandLine.arguments.first { $0.hasPrefix("--qa-permissions=") }
            .map { String($0.dropFirst("--qa-permissions=".count)) } ?? "granted"
        switch mode {
        case "new": return [false, false, true, true]
        case "denied": return [false, false, false, false]
        case "screen": return [true, false, false, false]
        case "accessibility": return [false, true, false, false]
        default: return [true, true, false, false]
        }
    }()

    static func permission(_ index: Int) -> Bool {
        permissionLock.lock()
        defer { permissionLock.unlock() }
        return permissionValues[index]
    }

    static func recordPermissionRequest(_ service: String, prompt: Bool) {
        actions.append("\(prompt ? "permissionPrompt" : "permissionPane"):\(service)")
        permissionLock.lock()
        permissionValues[service == "kTCCServiceAccessibility" ? 2 : 3] = false
        permissionLock.unlock()
    }

    static var restartArguments: [String] {
        let mode = permission(0) ? (permission(1) ? "granted" : "screen") : (permission(1) ? "accessibility" : "denied")
        return CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("--qa-permissions=") } + ["--qa-permissions=\(mode)"]
    }

    struct Request: Decodable {
        let action: String
        var completed: Bool?
        var text: String?
        var key: String?
        var value: String?
        var accessibility: Bool?
        var screenRecording: Bool?
    }

    struct Surface: Codable {
        let name: String
        let number: Int
        let texts: [String]
        let buttons: [String]
        let width: Double
        let height: Double
        let layoutIssues: [String]
    }

    struct Snapshot: Codable {
        let session: String
        let pid: Int32
        let ready: Bool
        let launchCount: Int
        let accessibility: String
        let screenRecording: String
        let axEntryAbsent: Bool?
        let screenEntryAbsent: Bool?
        let permissionsMocked: Bool
        let completed: Bool
        let switcher: Bool
        let actions: [String]
        let surfaces: [Surface]
        let error: String?
    }

    static func command(_ raw: String) -> Codable? {
        guard enabled, raw.hasPrefix("--qa-lifecycle=") else { return nil }
        guard let data = Data(base64Encoded: String(raw.dropFirst("--qa-lifecycle=".count))),
              let request = try? JSONDecoder().decode(Request.self, from: data) else { return snapshot("Malformed lifecycle request") }
        do {
            try execute(request)
            return snapshot(nil)
        } catch { return snapshot(String(describing: error)) }
    }

    private static func execute(_ r: Request) throws {
        switch r.action {
        case "state": break
        case "seed": try seed(r)
        case "startup": App.replayFirstLaunchForQa()
        case "permissions":
            permissionLock.lock()
            if let value = r.accessibility { permissionValues[0] = value }
            if let value = r.screenRecording { permissionValues[1] = value }
            permissionLock.unlock()
            SystemPermissions.checkPermissionsSoon()
        case "open-permissions": App.showPermissionsWindow()
        case "open-settings": App.showSettingsWindow()
        case "request-accessibility": AccessibilityPermission.request()
        case "request-screen": ScreenRecordingPermission.request()
        case "skip-screen": ScreenRecordingPermission.waive()
        case "unskip-screen": ScreenRecordingPermission.unwaive()
        case "click": try click(r.text ?? "")
        case "preference":
            guard let key = r.key, let value = r.value, ["appearanceStyle", "appearanceSize", "shortcutStyle", "screenRecordingPermissionSkipped"].contains(key) else { throw QaError("Unsupported preference") }
            Preferences.set(key, value)
        case "close": closeSurfaces()
        default: throw QaError("Unknown lifecycle action")
        }
    }

    private static func seed(_ r: Request) throws {
        App.hideUi()
        closeSurfaces()
        OnboardingPopover.closeForQa()
        Preferences.set("settingsWindowShownOnFirstLaunch", r.completed == false ? "false" : "true", false)
        Preferences.remove("onboardingShortcutUsed", false)
        actions.removeAll(keepingCapacity: true)
        guard UserDefaults.standard.synchronize() else { throw QaError("Could not persist QA fixture") }
    }

    static func closeSurfaces() {
        for window in NSApp.windows where window is SettingsWindow { window.close() }
    }

    private static func click(_ text: String) throws {
        let matches = NSApp.windows.filter(\.isVisible).compactMap(\.contentView).flatMap(controls).filter { $0.title == text && $0.isEnabled }
        guard matches.count == 1 else { throw QaError("Expected one visible button ‘\(text)’, got \(matches.count)") }
        matches[0].performClick(nil)
    }

    private static func controls(_ view: NSView) -> [NSButton] {
        guard !view.isHidden else { return [] }
        if let button = view as? NSButton { return [button] }
        return view.subviews.flatMap(controls)
    }

    private static func texts(_ view: NSView) -> [String] {
        guard !view.isHidden else { return [] }
        let own = (view as? NSTextField).map { [$0.stringValue] } ?? []
        return own + view.subviews.flatMap(texts)
    }

    private static func layoutIssues(_ view: NSView, _ root: NSView) -> [String] {
        guard !view.isHidden else { return [] }
        var issues = [String]()
        if view is NSTextField || view is NSButton {
            let frame = view.convert(view.bounds, to: root)
            if frame.width <= 0 || frame.height <= 0 || !root.bounds.insetBy(dx: -1, dy: -1).contains(frame) {
                issues.append("\(type(of: view)): \(frame), root: \(root.bounds)")
            }
        }
        return issues + view.subviews.flatMap { layoutIssues($0, root) }
    }

    static func snapshot(_ error: String?) -> Snapshot {
        let surfaces = NSApp.windows.filter { $0.isVisible && !($0 is QAMenu) }.map { window -> Surface in
            let buttons = window.contentView.map(controls) ?? []
            return Surface(name: OnboardingPopover.ownsForQa(window) ? "OnboardingPopover" : String(describing: type(of: window)), number: window.windowNumber,
                texts: window.contentView.map(texts) ?? [], buttons: buttons.map(\.title),
                width: window.frame.width, height: window.frame.height,
                layoutIssues: window.contentView.map { layoutIssues($0, $0) } ?? [])
        }
        guard SystemPermissions.preStartupPermissionsPassed else {
            return Snapshot(session: session!, pid: getpid(), ready: false, launchCount: 0,
                accessibility: String(describing: AccessibilityPermission.status), screenRecording: String(describing: ScreenRecordingPermission.status),
                axEntryAbsent: SystemPermissions.hasNoEntry("kTCCServiceAccessibility"), screenEntryAbsent: SystemPermissions.hasNoEntry("kTCCServiceScreenCapture"),
                permissionsMocked: true,
                completed: false, switcher: false, actions: actions, surfaces: surfaces, error: error)
        }
        return Snapshot(session: session!, pid: getpid(), ready: finishedLaunching, launchCount: launchCount,
            accessibility: String(describing: AccessibilityPermission.status), screenRecording: String(describing: ScreenRecordingPermission.status),
            axEntryAbsent: SystemPermissions.hasNoEntry("kTCCServiceAccessibility"), screenEntryAbsent: SystemPermissions.hasNoEntry("kTCCServiceScreenCapture"),
            permissionsMocked: true,
            completed: Preferences.settingsWindowShownOnFirstLaunch, switcher: TilesPanel.shared?.isVisible == true,
            actions: actions, surfaces: surfaces, error: error)
    }

    struct QaError: Error, CustomStringConvertible {
        let description: String
        init(_ text: String) { description = text }
    }
}
#endif
