import AppKit

/// Anchors expanded and collapsed controls inside the enclosing frame's upper-right inset.
enum ToolbarPlacement {
    static let expandedWidth = OverlayLayout.toolbarSize.width
    static let expandedHeight = OverlayLayout.toolbarSize.height

    static func origin(overlay lyrics: NSRect, size: NSSize) -> NSPoint {
        let outer = OverlayLayout.outerFrame(for: lyrics)
        return NSPoint(x: outer.maxX - OverlayLayout.toolbarRightInset - size.width,
                       y: outer.maxY - OverlayLayout.toolbarTopInset - size.height)
    }
}
