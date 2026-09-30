import AppKit

/// Geometry of the single visual frame and its three inset regions (AppKit screen coordinates).
enum OverlayLayout {
    static let outerSize = NSSize(width: 880, height: 236)
    static let lyricSize = NSSize(width: 848, height: 126)
    static let toolbarSize = NSSize(width: 294, height: 44)
    static let collapsedToolbarSize = NSSize(width: 42, height: 44)
    static let railSize = NSSize(width: 832, height: 28)

    static let lyricInset = NSPoint(x: 16, y: 44)
    static let toolbarRightInset: CGFloat = 18
    static let toolbarTopInset: CGFloat = 14
    static let railInset = NSPoint(x: 24, y: 10)

    static func outerFrame(for lyrics: NSRect) -> NSRect {
        NSRect(x: lyrics.minX - lyricInset.x, y: lyrics.minY - lyricInset.y,
               width: lyrics.width + outerSize.width - lyricSize.width,
               height: lyrics.height + outerSize.height - lyricSize.height)
    }

    static func toolbarFrame(for lyrics: NSRect, collapsed: Bool = false) -> NSRect {
        let size = collapsed ? collapsedToolbarSize : toolbarSize
        return NSRect(origin: ToolbarPlacement.origin(overlay: lyrics, size: size), size: size)
    }

    static func railFrame(for lyrics: NSRect) -> NSRect {
        let outer = outerFrame(for: lyrics)
        return NSRect(x: outer.minX + railInset.x, y: outer.minY + railInset.y,
                      width: max(0, outer.width - 2 * railInset.x), height: railSize.height)
    }

    /// The visible outer frame already contains all three inset regions.
    static func envelope(for lyrics: NSRect) -> NSRect { outerFrame(for: lyrics) }

    static func constrainedOrigin(for lyrics: NSRect, visibleFrames: [NSRect]) -> NSPoint {
        let group = envelope(for: lyrics)
        let safe = OverlayVisibility.origin(for: group, visibleFrames: visibleFrames)
        return NSPoint(x: lyrics.minX + safe.x - group.minX,
                       y: lyrics.minY + safe.y - group.minY)
    }
}
