import AppKit

/// Toolbar position in global AppKit screen coordinates. Pure so it can be tested without windows.
enum ToolbarPlacement {
    // Reserve enough room for expanded controls even when the toolbar is collapsed;
    // otherwise the right edge jumps when the overlay is partly off-screen.
    static let expandedWidth: CGFloat = 166
    static let expandedHeight: CGFloat = 80

    static func origin(overlay: NSRect, size: NSSize, visibleFrames: [NSRect]) -> NSPoint {
        let horizontalInset: CGFloat = 8
        let verticalInset: CGFloat = 6
        // Center the two rows vertically in the right rail, well below the top
        // edge; keep the same lower-row anchor when the toolbar is collapsed.
        let desired = NSPoint(x: overlay.maxX - size.width - 10,
                              y: overlay.maxY - expandedHeight - 48)
        guard let screen = visibleFrames.max(by: { first, second in
            let a = first.intersection(overlay)
            let b = second.intersection(overlay)
            let areaA = a.isNull ? 0 : a.width * a.height
            let areaB = b.isNull ? 0 : b.width * b.height
            if areaA != areaB { return areaA < areaB }
            let distanceA = hypot(first.midX - overlay.midX, first.midY - overlay.midY)
            let distanceB = hypot(second.midX - overlay.midX, second.midY - overlay.midY)
            return distanceA > distanceB
        }) else {
            return desired
        }
        let visibleOverlay = screen.intersection(overlay)
        let desiredRight = overlay.maxX - 10
        let safeRight: CGFloat
        if !visibleOverlay.isNull && visibleOverlay.width < expandedWidth + horizontalInset * 2 {
            // If the lyrics only show a sliver, clipping the expanded toolbar is
            // preferable to moving its collapse/expand button away from the lyrics.
            // The expanded button ends 8 pt before this anchor; the collapsed
            // button ends 2 pt before it. Preserve this anchor in both states.
            // A 42 pt margin lets the entire collapsed button fit at the left edge.
            let minRight = visibleOverlay.minX + 42
            let maxRight = visibleOverlay.maxX
            if minRight <= maxRight {
                safeRight = min(max(desiredRight, minRight), maxRight)
            } else {
                // Less than one button remains visible. Show as much of the
                // rightmost control as the lyric sliver can contain.
                safeRight = maxRight
            }
        } else if screen.width >= expandedWidth + horizontalInset * 2 {
            safeRight = min(max(desiredRight, screen.minX + expandedWidth + horizontalInset),
                            screen.maxX - horizontalInset)
        } else {
            safeRight = min(max(desiredRight, screen.minX), screen.maxX)
        }
        let vertical = !visibleOverlay.isNull
            && visibleOverlay.height >= expandedHeight + verticalInset * 2
            ? visibleOverlay : screen
        let x = safeRight - size.width
        let y = min(max(desired.y, vertical.minY + verticalInset),
                    max(vertical.minY + verticalInset,
                        vertical.maxY - expandedHeight - verticalInset))
        return NSPoint(x: x, y: y)
    }
}
