import AppKit

/// Geometry of the single background and its transparent content zones.
enum OverlayLayout {
    static let outerSize = NSSize(width: 880, height: 256)
    static let lyricSize = NSSize(width: 848, height: 126)
    static let toolbarSize = NSSize(width: 160, height: 36)
    static let collapsedToolbarSize = NSSize(width: 42, height: 36)
    static let playbackSize = NSSize(width: 132, height: 32)
    static let railSize = NSSize(width: 832, height: 28)

    static let lyricInset = NSPoint(x: 16, y: 80)
    static let toolbarRightInset: CGFloat = 16
    static let toolbarTopInset: CGFloat = 10
    static let railInset = NSPoint(x: 24, y: 12)
    static let titleLeftInset: CGFloat = 24
    static let titleGap: CGFloat = 12
    static let titleHeight: CGFloat = 18

    static func outerFrame(for lyrics: NSRect) -> NSRect {
        NSRect(x: lyrics.minX - lyricInset.x, y: lyrics.minY - lyricInset.y,
               width: lyrics.width + outerSize.width - lyricSize.width,
               height: lyrics.height + outerSize.height - lyricSize.height)
    }

    static func toolbarFrame(for lyrics: NSRect, collapsed: Bool = false) -> NSRect {
        let size = collapsed ? collapsedToolbarSize : toolbarSize
        return NSRect(origin: ToolbarPlacement.origin(overlay: lyrics, size: size), size: size)
    }

    /// One truncated title line in the top row, ending before the tool icons.
    static func titleFrame(for lyrics: NSRect) -> NSRect {
        let outer = outerFrame(for: lyrics)
        let tools = toolbarFrame(for: lyrics)
        let x = outer.minX + titleLeftInset
        return NSRect(x: x, y: tools.midY - titleHeight / 2,
                      width: max(0, tools.minX - titleGap - x), height: titleHeight)
    }

    static func playbackFrame(for lyrics: NSRect) -> NSRect {
        let outer = outerFrame(for: lyrics)
        return NSRect(x: outer.midX - playbackSize.width / 2,
                      y: lyrics.minY - 4 - playbackSize.height,
                      width: playbackSize.width, height: playbackSize.height)
    }

    static func railFrame(for lyrics: NSRect) -> NSRect {
        let outer = outerFrame(for: lyrics)
        return NSRect(x: outer.minX + railInset.x, y: outer.minY + railInset.y,
                      width: max(0, outer.width - 2 * railInset.x), height: railSize.height)
    }

    /// The outer background contains every content zone.
    static func envelope(for lyrics: NSRect) -> NSRect { outerFrame(for: lyrics) }

    static func constrainedOrigin(for lyrics: NSRect, visibleFrames: [NSRect]) -> NSPoint {
        let group = envelope(for: lyrics)
        let safe = OverlayVisibility.origin(for: group, visibleFrames: visibleFrames)
        return NSPoint(x: lyrics.minX + safe.x - group.minX,
                       y: lyrics.minY + safe.y - group.minY)
    }
}
