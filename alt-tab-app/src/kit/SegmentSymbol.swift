import Cocoa

/// An SF Symbol beside a segment's label (`LabelAndControl.makeSegmentedControl`).
enum SegmentSymbol {
    static let pointSize: CGFloat = 13
    /// Room for anti-aliasing around the glyph; see `NSImage.fromSymbol`.
    static let margin: CGFloat = 1
    /// What AppKit leaves between a segment's image and its label. It reads as cramped next to round
    /// glyphs and letters like S or M, hence `extraGap`.
    static let appKitGap: CGFloat = 2
    static let extraGap: CGFloat = 1.5

    /// Space to put before and after a glyph that has no margin of its own. AppKit truncates a segment's
    /// label as soon as image + `appKitGap` + label exceed the segment width, with no padding to spare
    /// (measured on macOS 27), so this space only comes out of slack: a label that fit beside the bare
    /// glyph still fits.
    static func spacing(glyphWidth: CGFloat, labelWidth: CGFloat, availableWidth: CGFloat) -> (before: CGFloat, after: CGFloat) {
        let room = max(0, min(2 * margin + extraGap, availableWidth - glyphWidth - appKitGap - labelWidth))
        let before = min(margin, room / 2)
        return (before, room - before)
    }
}
