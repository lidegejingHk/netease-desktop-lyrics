import AppKit

/// Geometry of the single background and its transparent content zones.
enum OverlayLayout {
    /// Startup band: the width never changes, while the height follows the lyrics.
    static let lyricSize = NSSize(width: 848, height: 126)
    /// The lyric band inside the background: 16 pt sides, 80 pt below.
    static let lyricInset = NSPoint(x: 16, y: 80)
    /// 10 pt top inset plus the 36 pt tool row plus the 4 pt top-row rhythm.
    static let topInset: CGFloat = 50
    static let horizontalInset = lyricInset.x
    static let bottomInset = lyricInset.y
    static let outerSize = NSSize(width: lyricSize.width + 2 * horizontalInset,
                                  height: lyricSize.height + topInset + bottomInset)
    /// Guard rails for the band that hugs the content.
    static let bandHeightRange: ClosedRange<CGFloat> = 40...320

    /// Three right-aligned tool icons: lock, style and collapse.
    static let toolbarSize = NSSize(width: 120, height: 36)
    static let collapsedToolbarSize = NSSize(width: 42, height: 36)
    static let playbackSize = NSSize(width: 132, height: 32)
    static let railSize = NSSize(width: 832, height: 28)

    static let toolbarRightInset: CGFloat = 16
    static let toolbarTopInset: CGFloat = 10
    static let railInset = NSPoint(x: 24, y: 12)
    static let titleLeftInset: CGFloat = 24
    static let titleGap: CGFloat = 12
    static let titleHeight: CGFloat = 18

    static func outerFrame(for lyrics: NSRect) -> NSRect {
        NSRect(x: lyrics.minX - horizontalInset, y: lyrics.minY - bottomInset,
               width: lyrics.width + 2 * horizontalInset,
               height: lyrics.height + topInset + bottomInset)
    }

    /// A measured band height, bounded so a pathological measurement cannot
    /// shrink the overlay to nothing or grow it past every display.
    static func clampedBandHeight(_ height: CGFloat) -> CGFloat {
        guard height.isFinite else { return lyricSize.height }
        return min(max(height, bandHeightRange.lowerBound), bandHeightRange.upperBound)
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
