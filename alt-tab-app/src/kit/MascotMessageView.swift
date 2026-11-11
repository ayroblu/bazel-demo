import Cocoa

final class ProMascotView: NSImageView {
    private static let artwork = NSImage(named: "pro-rabbit")

    init() {
        super.init(frame: .zero)
        image = Self.artwork
        imageScaling = .scaleProportionallyUpOrDown
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }
}

final class MascotMessageView: NSStackView {
    private let heading = NSTextField(wrappingLabelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")

    init(title: String, message: String, emphasizeMessage: Bool = false) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let rabbit = ProMascotView()
        rabbit.wantsLayer = true
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        rabbit.shadow = shadow
        rabbit.translatesAutoresizingMaskIntoConstraints = false
        rabbit.widthAnchor.constraint(equalToConstant: 76).isActive = true
        rabbit.heightAnchor.constraint(equalToConstant: 76).isActive = true
        heading.font = .systemFont(ofSize: emphasizeMessage ? 13 : 18, weight: emphasizeMessage ? .regular : .semibold)
        heading.textColor = emphasizeMessage ? .secondaryLabelColor : .labelColor
        detail.font = .systemFont(ofSize: emphasizeMessage ? 20 : 13, weight: emphasizeMessage ? .bold : .regular)
        detail.textColor = emphasizeMessage ? .labelColor : .secondaryLabelColor
        heading.isSelectable = false
        detail.isSelectable = false
        update(title: title, message: message)
        let bubble = NSStackView(views: [heading, detail])
        bubble.orientation = .vertical
        bubble.alignment = .leading
        bubble.spacing = SpeechBubbleView.lineSpacing
        let balloon = SpeechBubbleView()
        balloon.pointsRight = userInterfaceLayoutDirection == .rightToLeft
        balloon.translatesAutoresizingMaskIntoConstraints = false
        balloon.addContent(bubble)
        addArrangedSubview(rabbit)
        addArrangedSubview(balloon)
        spacing = 10
    }

    func update(title: String, message: String) {
        heading.stringValue = title
        detail.stringValue = message
        detail.setAccessibilityLabel(message)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }
}

final class SpeechBubbleView: NSView {
    static let cornerRadius = CGFloat(24)
    static let contentPadding = CGFloat(18)
    static let lineSpacing = CGFloat(4)
    private static let tailWidth = CGFloat(10)
    private static let outlineInset = CGFloat(1)
    var pointsRight = false { didSet { needsLayout = true } }
    var highContrast = false { didSet { needsLayout = true } }
    private var material: NSView?
    private let outline = CAShapeLayer()

    static func contentInsets(pointsRight: Bool) -> NSEdgeInsets {
        let inset = outlineInset + contentPadding
        return NSEdgeInsets(top: inset, left: inset + (pointsRight ? 0 : tailWidth),
            bottom: inset, right: inset + (pointsRight ? tailWidth : 0))
    }

    static func contentRect(in bounds: NSRect, pointsRight: Bool) -> NSRect {
        let insets = contentInsets(pointsRight: pointsRight)
        return NSRect(x: bounds.minX + insets.left, y: bounds.minY + insets.bottom,
            width: max(1, bounds.width - insets.left - insets.right),
            height: max(1, bounds.height - insets.top - insets.bottom))
    }

    func addContent(_ view: NSView) {
        let insets = Self.contentInsets(pointsRight: pointsRight)
        addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leftAnchor.constraint(equalTo: leftAnchor, constant: insets.left),
            view.rightAnchor.constraint(equalTo: rightAnchor, constant: -insets.right),
            view.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom),
        ])
    }

    func setMaterial(_ view: NSView) {
        material?.removeFromSuperview()
        material = view
        addSubview(view, positioned: .below, relativeTo: subviews.first)
        wantsLayer = true
        layer?.addSublayer(outline)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        material?.frame = bounds
        let path = bubblePath()
        let shape = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)
        for index in 0..<path.elementCount {
            switch path.element(at: index, associatedPoints: &points) {
            case .moveTo: shape.move(to: points[0])
            case .lineTo: shape.addLine(to: points[0])
            case .cubicCurveTo: shape.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo: shape.addQuadCurve(to: points[1], control: points[0])
            case .closePath: shape.closeSubpath()
            @unknown default: break
            }
        }
        let mask = CAShapeLayer()
        mask.path = shape
        material?.wantsLayer = true
        material?.layer?.mask = mask
        outline.path = shape
        outline.fillColor = nil
        outline.strokeColor = highContrast ? NSColor.labelColor.cgColor : nil
        outline.lineWidth = 2
        needsDisplay = true
    }

    override func draw(_: NSRect) {
        guard material == nil else { return }
        let path = bubblePath()
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        (highContrast ? NSColor.labelColor : NSColor.separatorColor).setStroke()
        path.lineWidth = highContrast ? 2 : 1
        path.stroke()
    }

    /// One closed silhouette, with no edge crossing the mouth of the tail.
    func bubblePath() -> NSBezierPath {
        let r = bounds.insetBy(dx: Self.outlineInset, dy: Self.outlineInset)
        let left = r.minX + Self.tailWidth
        let radius = max(0, min(Self.cornerRadius, (r.height - 20) / 2))
        let arc = radius * 0.5522847498
        let p = NSBezierPath()
        p.move(to: NSPoint(x: left + radius, y: r.minY))
        p.line(to: NSPoint(x: r.maxX - radius, y: r.minY))
        p.curve(to: NSPoint(x: r.maxX, y: r.minY + radius),
            controlPoint1: NSPoint(x: r.maxX - radius + arc, y: r.minY),
            controlPoint2: NSPoint(x: r.maxX, y: r.minY + radius - arc))
        p.line(to: NSPoint(x: r.maxX, y: r.maxY - radius))
        p.curve(to: NSPoint(x: r.maxX - radius, y: r.maxY),
            controlPoint1: NSPoint(x: r.maxX, y: r.maxY - radius + arc),
            controlPoint2: NSPoint(x: r.maxX - radius + arc, y: r.maxY))
        p.line(to: NSPoint(x: left + radius, y: r.maxY))
        p.curve(to: NSPoint(x: left, y: r.maxY - radius),
            controlPoint1: NSPoint(x: left + radius - arc, y: r.maxY),
            controlPoint2: NSPoint(x: left, y: r.maxY - radius + arc))
        p.line(to: NSPoint(x: left, y: r.midY + 8))
        p.line(to: NSPoint(x: r.minX, y: r.midY))
        p.line(to: NSPoint(x: left, y: r.midY - 8))
        p.line(to: NSPoint(x: left, y: r.minY + radius))
        p.curve(to: NSPoint(x: left + radius, y: r.minY),
            controlPoint1: NSPoint(x: left, y: r.minY + radius - arc),
            controlPoint2: NSPoint(x: left + radius - arc, y: r.minY))
        p.close()
        if pointsRight {
            p.transform(using: AffineTransform(m11: -1, m12: 0, m21: 0, m22: 1, tX: bounds.width, tY: 0))
        }
        return p
    }
}
