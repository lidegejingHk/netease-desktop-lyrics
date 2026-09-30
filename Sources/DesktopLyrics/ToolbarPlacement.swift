import AppKit

/// Toolbar position in global AppKit screen coordinates. Pure so it can be tested without windows.
enum ToolbarPlacement {
    // Reserve enough room for expanded controls even when the toolbar is collapsed;
    // otherwise the right edge jumps when the overlay is partly off-screen.
    static let expandedWidth: CGFloat = 166

    static func origin(overlay: NSRect, size: NSSize, visibleFrames: [NSRect]) -> NSPoint {
        let horizontalInset: CGFloat = 8
        let verticalInset: CGFloat = 6
        let desired = NSPoint(x: overlay.maxX - size.width - 10,
                              y: overlay.maxY - size.height - 6)
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
        // Use the expanded width for the screen-safe anchor in both states.
        // A narrow visible sliver cannot contain the expanded toolbar; in that
        // case keep both states together on-screen rather than jumping on toggle.
        let safeRight = screen.width >= expandedWidth + horizontalInset * 2
            ? min(max(overlay.maxX - 10, screen.minX + expandedWidth + horizontalInset),
                  screen.maxX - horizontalInset)
            : screen.maxX
        let visibleOverlay = screen.intersection(overlay)
        let vertical = !visibleOverlay.isNull
            && visibleOverlay.height >= size.height + verticalInset * 2
            ? visibleOverlay : screen
        let x = max(screen.minX, safeRight - size.width)
        let y = min(max(desired.y, vertical.minY + verticalInset),
                    max(vertical.minY + verticalInset,
                        vertical.maxY - size.height - verticalInset))
        return NSPoint(x: x, y: y)
    }
}
