import AppKit

/// Anchors the tool row inside the enclosing frame's upper-right inset.
enum ToolbarPlacement {
    static func origin(overlay lyrics: NSRect, size: NSSize) -> NSPoint {
        let outer = OverlayLayout.outerFrame(for: lyrics)
        return NSPoint(x: outer.maxX - OverlayLayout.toolbarRightInset - size.width,
                       y: outer.maxY - OverlayLayout.toolbarTopInset - size.height)
    }
}
