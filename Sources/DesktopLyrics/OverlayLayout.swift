import AppKit

/// Geometry of the single background and its transparent content zones.
enum OverlayLayout {
    /// Startup band: the width never changes, while the height follows the lyrics.
    static let lyricSize = NSSize(width: 848, height: 126)
    /// The lyric band inside the background: 16 pt sides, and below it the 4 pt
    /// gap plus the full-width waveform rail.
    static let lyricInset = NSPoint(x: 16, y: 44)
    /// 10 pt top inset plus the 36 pt tool row plus the 4 pt top-row rhythm.
    static let topInset: CGFloat = 50
    static let horizontalInset = lyricInset.x
    static let waveformBottomInset = lyricInset.y
    /// Without a waveform the rail's 44 pt slot would be an empty strip. Keep
    /// only a small rim below the lyric band in that case.
    static let compactBottomInset: CGFloat = 8
    static let outerSize = NSSize(width: lyricSize.width + 2 * horizontalInset,
                                  height: lyricSize.height + topInset + waveformBottomInset)
    /// Guard rails for the band that hugs the content.
    static let bandHeightRange: ClosedRange<CGFloat> = 40...320

    /// The style and quit icons stay together on the right; the lock lives on
    /// the leading edge as a stable, content-aligned state control.
    static let toolbarSize = NSSize(width: 80, height: 36)
    static let lockSize = NSSize(width: 34, height: 32)
    static let playbackSize = NSSize(width: 132, height: 32)
    static let railSize = NSSize(width: 832, height: 28)

    static let toolbarRightInset: CGFloat = 16
    static let toolbarTopInset: CGFloat = 10
    static let lockLeftInset: CGFloat = 8
    static let lockTitleGap: CGFloat = 8
    static let railInset = NSPoint(x: 24, y: 12)
    static let titleLeftInset: CGFloat = 24
    static let titleGap: CGFloat = 12
    static let titleHeight: CGFloat = 18

    static func bottomInset(showsWaveform: Bool) -> CGFloat {
        showsWaveform ? waveformBottomInset : compactBottomInset
    }

    static func outerFrame(for lyrics: NSRect, showsWaveform: Bool = true) -> NSRect {
        let bottom = bottomInset(showsWaveform: showsWaveform)
        return NSRect(x: lyrics.minX - horizontalInset, y: lyrics.minY - bottom,
               width: lyrics.width + 2 * horizontalInset,
               height: lyrics.height + topInset + bottom)
    }

    /// A measured band height, bounded so a pathological measurement cannot
    /// shrink the overlay to nothing or grow it past every display.
    static func clampedBandHeight(_ height: CGFloat) -> CGFloat {
        guard height.isFinite else { return lyricSize.height }
        return min(max(height, bandHeightRange.lowerBound), bandHeightRange.upperBound)
    }

    static func toolbarFrame(for lyrics: NSRect) -> NSRect {
        NSRect(origin: ToolbarPlacement.origin(overlay: lyrics, size: toolbarSize),
               size: toolbarSize)
    }

    /// The lock is pinned to the leading edge of the top row, independent of the
    /// lyric alignment. Its trailing edge reserve keeps the title clear of it.
    static func lockFrame(for lyrics: NSRect) -> NSRect {
        let tools = toolbarFrame(for: lyrics)
        return NSRect(x: outerFrame(for: lyrics).minX + lockLeftInset,
                      y: tools.midY - lockSize.height / 2,
                      width: lockSize.width, height: lockSize.height)
    }

    /// One single-line title in the top row, ending before the centered transport
    /// keys, which in turn end before the tool icons.
    static func titleFrame(for lyrics: NSRect) -> NSRect {
        let outer = outerFrame(for: lyrics)
        let tools = toolbarFrame(for: lyrics)
        let playback = playbackFrame(for: lyrics)
        let x = max(outer.minX + titleLeftInset,
                    lockFrame(for: lyrics).maxX + lockTitleGap)
        return NSRect(x: x, y: tools.midY - titleHeight / 2,
                      width: max(0, min(tools.minX, playback.minX) - titleGap - x),
                      height: titleHeight)
    }

    /// The transport keys ride the top row itself, centered between the song title
    /// and the tool icons, so the band beneath the lyrics stays a single waveform.
    static func playbackFrame(for lyrics: NSRect) -> NSRect {
        let tools = toolbarFrame(for: lyrics)
        return NSRect(x: outerFrame(for: lyrics).midX - playbackSize.width / 2,
                      y: tools.midY - playbackSize.height / 2,
                      width: playbackSize.width, height: playbackSize.height)
    }

    static func railFrame(for lyrics: NSRect) -> NSRect {
        let outer = outerFrame(for: lyrics)
        return NSRect(x: outer.minX + railInset.x, y: outer.minY + railInset.y,
                      width: max(0, outer.width - 2 * railInset.x), height: railSize.height)
    }

    /// The outer background contains every content zone.
    static func envelope(for lyrics: NSRect, showsWaveform: Bool = true) -> NSRect {
        outerFrame(for: lyrics, showsWaveform: showsWaveform)
    }

    static func constrainedOrigin(for lyrics: NSRect, visibleFrames: [NSRect],
                                  showsWaveform: Bool = true) -> NSPoint {
        let group = envelope(for: lyrics, showsWaveform: showsWaveform)
        let safe = OverlayVisibility.origin(for: group, visibleFrames: visibleFrames)
        return NSPoint(x: lyrics.minX + safe.x - group.minX,
                       y: lyrics.minY + safe.y - group.minY)
    }

    /// A free position is intentionally unbounded: dragging can park the
    /// complete overlay beyond a display edge. Only the explicit right-edge snap
    /// pulls a freed overlay back on screen, so the menu-bar command remains the
    /// recovery path.
    static func settledOrigin(for lyrics: NSRect, visibleFrames: [NSRect],
                              snappedRight: Bool,
                              showsWaveform: Bool = true) -> NSPoint {
        snappedRight
            ? snappedRightOrigin(for: lyrics, visibleFrames: visibleFrames,
                                 showsWaveform: showsWaveform)
            : lyrics.origin
    }

    /// The pin target: same group geometry, right edge against the display edge.
    static func snappedRightOrigin(for lyrics: NSRect, visibleFrames: [NSRect],
                                   showsWaveform: Bool = true) -> NSPoint {
        let group = envelope(for: lyrics, showsWaveform: showsWaveform)
        let safe = OverlayVisibility.snappedRightOrigin(for: group, visibleFrames: visibleFrames)
        return NSPoint(x: lyrics.minX + safe.x - group.minX,
                       y: lyrics.minY + safe.y - group.minY)
    }
}
