import Cocoa
import Foundation

enum FeedbackKind: Hashable {
    case bug
    case enhancement

    var apiValue: String {
        switch self {
        case .bug: return "bug"
        case .enhancement: return "enhancement"
        }
    }
}

private struct Draft {
    var title: String = ""
    var body: String = ""
}

class FeedbackWindow: NSWindow {
    // Mirror of the caps in server
    // Counted in UTF-16 code units to match the server's String.length check.
    // Keep in sync with the server constants; the server is still the source of truth.
    static let titleMaxLength = 256
    static let bodyMaxLength = 64 * 1024
    static var shared: FeedbackWindow?
    var kind: FeedbackKind = .bug
    var issueTitle: TextArea!
    var body: TextArea!
    var sendButton: NSButton!
    /// Per-kind in-memory drafts. Survive close/reopen so a half-written report isn't lost when
    /// the user steps away. Only cleared when the matching kind submits successfully (server 201).
    private var drafts: [FeedbackKind: Draft] = [:]
    /// Tracks whether the visible content is the form (true) or the kind picker (false). Used to
    /// know whether issueTitle / body reflect the current user-visible input.
    private var formIsVisible = false
    /// Sentinel for in-flight POSTs — `sendCallback` sets it before firing the request, the
    /// completion handler bumps it back to false. Used to avoid double-submits and to decide
    /// whether the error alert is still relevant when a response finally arrives.
    private var isSubmitting = false
    override var canBecomeKey: Bool { SecondaryWindows.canBecomeKey }

    convenience init() {
        self.init(contentRect: .zero, styleMask: [.titled, .miniaturizable, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        setupWindow()
        setFrameAutosaveNameSafely("FeedbackWindow")
        Self.shared = self
        reset()
    }

    /// Returns the window to the kind picker. Drafts are NOT cleared — they're only wiped by a
    /// successful POST. Called from init and from `App.showFeedbackPanel` on each reopen.
    func reset() {
        captureCurrentDraft()
        kind = .bug
        showKindPicker()
    }

    private func setupWindow() {
        applySecondaryWindowChrome(NSLocalizedString("Send feedback", comment: ""))
    }

    // MARK: - Draft management

    /// Snapshot the currently-edited textareas into `drafts[kind]`. No-op when the kind picker
    /// is visible (issueTitle/body may still be live but they belong to a now-detached form view
    /// — saving them again would be redundant but harmless; we skip for clarity).
    private func captureCurrentDraft() {
        guard formIsVisible, let issueTitle = issueTitle, let body = body else { return }
        drafts[kind] = Draft(title: issueTitle.stringValue, body: body.stringValue)
    }

    // MARK: - Kind picker (state A)

    private func showKindPicker() {
        formIsVisible = false
        let header = MascotMessageView(title: NSLocalizedString("Send feedback", comment: ""),
            message: NSLocalizedString("Help improve AltTab", comment: ""))

        let bug = FeedbackKindCard(
            symbol: .ladybug,
            iconTint: .systemRed,
            title: NSLocalizedString("Report a bug", comment: ""),
            target: self,
            action: #selector(selectBug))
        let enhancement = FeedbackKindCard(
            symbol: .lightbulb,
            iconTint: .systemOrange,
            title: NSLocalizedString("Suggest a change", comment: ""),
            target: self,
            action: #selector(selectEnhancement))
        let cards = NSStackView(views: [bug, enhancement])
        cards.translatesAutoresizingMaskIntoConstraints = false
        cards.spacing = GridView.interPadding
        cards.orientation = .horizontal
        cards.distribution = .fillEqually

        let discussionsLink = HyperlinkLabel(
            NSLocalizedString("View existing discussions", comment: "") + " →",
            App.repository + "/issues")

        let view = GridView([
            [header],
            [cards],
            [discussionsLink],
        ])
        view.cell(atColumnIndex: 0, rowIndex: 2).xPlacement = .center
        contentView = view.wrappedWithTitlebarPadding()
        setContentSize(contentView!.fittingSize)
    }

    @objc private func selectBug() {
        kind = .bug
        showForm()
    }

    @objc private func selectEnhancement() {
        kind = .enhancement
        showForm()
    }

    // MARK: - Form (state B)

    private func showForm() {
        formIsVisible = true
        let headerLeft = MascotMessageView(title: formTitle(), message: kind == .bug
            ? NSLocalizedString("What happened, and what did you expect?", comment: "")
            : NSLocalizedString("What would make AltTab more useful for you?", comment: ""))

        let goBack = NSButton(title: "← " + NSLocalizedString("Go back", comment: ""), target: self, action: #selector(goBackToPicker))
        goBack.bezelStyle = .recessed
        goBack.setButtonType(.momentaryPushIn)

        let header = NSStackView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.orientation = .horizontal
        header.alignment = .centerY
        header.addView(headerLeft, in: .leading)
        header.addView(goBack, in: .trailing)

        // Form has no Cancel button on purpose: the only ways out are Send (gated by the
        // confirmation alert, whose own Cancel returns here with content intact), the Go back
        // button (returns to the picker, draft preserved), or closing the window (red traffic-
        // light or Escape — also preserves the draft for the next open).
        sendButton = NSButton(title: NSLocalizedString("Create GitHub issue", comment: ""), target: nil, action: #selector(sendCallback))
        sendButton.keyEquivalent = "\r"
        let buttons = StackView([sendButton])
        buttons.spacing = GridView.interPadding

        issueTitle = TextArea(80, 1, titlePlaceholder(), checkEmptyFields, Self.titleMaxLength)
        body = TextArea(80, 12, bodyPlaceholder(), checkEmptyFields, Self.bodyMaxLength)
        // Restore any unsent draft for this kind so the user picks up exactly where they left off.
        if let draft = drafts[kind] {
            issueTitle.stringValue = draft.title
            body.stringValue = draft.body
        }

        let view = GridView([
            [header],
            [NSView()],
            [issueTitle],
            [body],
            [buttons],
        ])
        view.cell(atColumnIndex: 0, rowIndex: 0).xPlacement = .fill
        view.cell(atColumnIndex: 0, rowIndex: 4).xPlacement = .trailing
        contentView = view.wrappedWithTitlebarPadding()
        setContentSize(contentView!.fittingSize)
        checkEmptyFields()
        // Explicit Tab chain: title → body → Create → Go back → title.
        // NSGridView + NSStackView nesting doesn't compute a useful auto-chain across
        // container boundaries; without this, Tab just re-focuses the current field.
        // Disabled views (e.g. sendButton while title/body are empty) are skipped by
        // AppKit automatically, so the cycle gracefully shortens to title → body → Go back.
        issueTitle.nextKeyView = body
        body.nextKeyView = sendButton
        sendButton.nextKeyView = goBack
        goBack.nextKeyView = issueTitle
        makeFirstResponder(issueTitle)
    }

    @objc private func goBackToPicker() {
        captureCurrentDraft()
        showKindPicker()
    }

    private func formTitle() -> String {
        switch kind {
        case .bug: return NSLocalizedString("Report a bug", comment: "")
        case .enhancement: return NSLocalizedString("Suggest a change", comment: "")
        }
    }

    private func titlePlaceholder() -> String {
        switch kind {
        case .bug: return NSLocalizedString("Brief description of the bug", comment: "")
        case .enhancement: return NSLocalizedString("Brief description of the change", comment: "")
        }
    }

    private func bodyPlaceholder() -> String {
        switch kind {
        case .bug: return NSLocalizedString("What did you expect? What happened? Steps to reproduce…", comment: "")
        case .enhancement: return NSLocalizedString("I think the app could be improved with…", comment: "")
        }
    }

    private func checkEmptyFields() {
        if isSubmitting { return }
        sendButton.isEnabled = !body.stringValue.isEmpty && !issueTitle.stringValue.isEmpty
        sendButton.toolTip = sendButton.isEnabled ? "" : NSLocalizedString("Please fill in the form", comment: "")
    }

    // allow to close with the escape key
    // periphery:ignore - responder-chain target, reached by Esc rather than by a call
    @objc func cancel(_ sender: Any?) {
        close()
    }

    /// Cmd+Return submits even when focus is in the multi-line body field (where plain
    /// Return inserts a newline). Convention: Mail compose, Notes, Linear, Slack — anywhere
    /// you compose multi-paragraph text and need a one-handed keyboard submit.
    /// Running before the field editor sees the key means we don't fight TextArea's
    /// Return → newline behavior; we just add a second submit gesture alongside it.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if formIsVisible,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "\r",
           let sendButton, sendButton.isEnabled {
            sendButton.performClick(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    @objc private func sendCallback() {
        if isSubmitting { return }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("Your feedback will be submitted as a public GitHub issue.", comment: "")
        alert.informativeText = NSLocalizedString("A debug profile (versions, settings, hardware) is attached to help diagnose the issue.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Create GitHub issue", comment: ""))
        let cancelButton = alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        cancelButton.keyEquivalent = "\u{1b}" // Escape
        alert.present(attachedTo: self) { [weak self] in
            if $0 == .alertFirstButtonReturn { self?.submit() }
        }
    }

    private func submit() {
        guard !isSubmitting else { return }
        beginSubmitting()
        // Capture the kind that owns this submission. If the user navigates to the other kind
        // form while the POST is in flight, completion still clears the right draft slot.
        let submittedKind = kind
        URLSession.shared.dataTask(with: prepareRequest()) { [weak self] data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let succeeded = status == 201 && error == nil
            if !succeeded {
                Logger.error { "feedback POST failed. status:\(status) response:\(response) error:\(error) data:\(data.flatMap { String(data: $0, encoding: .utf8) })" }
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.endSubmitting()
                if succeeded {
                    self.drafts[submittedKind] = nil
                    // If the user is still on the form they submitted, also clear the on-screen
                    // textareas so the visible state matches the now-empty draft.
                    if self.formIsVisible && self.kind == submittedKind {
                        self.issueTitle.stringValue = ""
                        self.body.stringValue = ""
                    }
                    self.close()
                } else {
                    self.showSubmitFailureAlert()
                }
            }
        }.resume()
    }

    private func beginSubmitting() {
        isSubmitting = true
        sendButton.isEnabled = false
        sendButton.title = NSLocalizedString("Sending…", comment: "")
    }

    private func endSubmitting() {
        isSubmitting = false
        sendButton.title = NSLocalizedString("Create GitHub issue", comment: "")
        checkEmptyFields()
    }

    private func showSubmitFailureAlert() {
        // If the user already dismissed the window before the failure came back, skip the alert —
        // surprising them with a modal on a closed-feeling window is worse than swallowing it. The
        // draft is already preserved in `drafts`, so they'll see their text again on next reopen.
        guard isVisible else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Couldn't submit feedback", comment: "")
        alert.informativeText = NSLocalizedString("The server didn't accept the submission. Check your internet connection and try again — your draft is preserved.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.present(attachedTo: self) { _ in }
    }

    /// The backend owns the final GitHub issue presentation — we just hand it the raw
    /// pieces. Splitting `body` from `debugProfile` means the markdown layout (quoting,
    /// `<details>` wrapping, disclaimer) can change server-side without forcing every
    /// installed AltTab to update.
    private func prepareRequest() -> URLRequest {
        var request = URLRequest(url: URL(string: Endpoints.feedbackUrl)!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try! JSONSerialization.data(withJSONObject: [
            "title": issueTitle.stringValue,
            "body": body.stringValue,
            "kind": kind.apiValue,
            "debugProfile": DebugProfile.make(),
        ])
        return request
    }

    override func close() {
        captureCurrentDraft()
        hideAppIfLastWindowIsClosed()
        super.close()
    }
}

// Clickable kind card: icon + bold title inside an NSButton. hitTest is overridden so clicks
// on the inner labels register as a button press rather than being swallowed by the label views.
class FeedbackKindCard: NSButton {
    private let iconView: NSView
    private let titleLabel: NSTextField

    init(symbol: Symbols, iconTint: NSColor, title: String, target: AnyObject?, action: Selector) {
        iconView = Self.makeIcon(symbol: symbol, tint: iconTint)

        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        label.alignment = .center
        titleLabel = label

        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        self.target = target
        self.action = action
        bezelStyle = .regularSquare
        isBordered = true
        imagePosition = .noImage
        self.title = ""

        // 36×36 matches the icon's intrinsic size from makeIcon.
        let iconSlot = NSView()
        iconSlot.translatesAutoresizingMaskIntoConstraints = false
        iconSlot.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconSlot.widthAnchor.constraint(equalToConstant: 36),
            iconSlot.heightAnchor.constraint(equalToConstant: 36),
            iconView.centerXAnchor.constraint(equalTo: iconSlot.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconSlot.centerYAnchor),
        ])

        let stack = NSStackView(views: [iconSlot, titleLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            widthAnchor.constraint(equalToConstant: 220),
            heightAnchor.constraint(equalToConstant: 130),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let hit = super.hitTest(point), hit === self || hit.isDescendant(of: self) {
            return self
        }
        return nil
    }

    // Rendered from the bundled SF Pro Text subset. Template tinting is applied at runtime
    // via contentTintColor — same pattern as PermissionView.
    private static func makeIcon(symbol: Symbols, tint: NSColor) -> NSView {
        let image = NSImage.fromSymbol(symbol, pointSize: 28)
        let iv = NSImageView(image: image)
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.contentTintColor = tint
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.fit(36, 36)
        return iv
    }
}
