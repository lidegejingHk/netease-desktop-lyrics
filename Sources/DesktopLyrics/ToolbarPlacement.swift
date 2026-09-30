import AppKit

/// Toolbar position in global AppKit screen coordinates. Pure so it can be tested without windows.
enum ToolbarPlacement {
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
        let visibleOverlay = screen.intersection(overlay)
        // Prefer the visible part of the lyric window, but fall back to the display
        // when only a narrow sliver of the window is currently on-screen.
        let horizontal = !visibleOverlay.isNull
            && visibleOverlay.width >= size.width + horizontalInset * 2
            ? visibleOverlay : screen
        let vertical = !visibleOverlay.isNull
            && visibleOverlay.height >= size.height + verticalInset * 2
            ? visibleOverlay : screen
        let x = min(max(desired.x, horizontal.minX + horizontalInset),
                    max(horizontal.minX + horizontalInset,
                        horizontal.maxX - size.width - horizontalInset))
        let y = min(max(desired.y, vertical.minY + verticalInset),
                    max(vertical.minY + verticalInset,
                        vertical.maxY - size.height - verticalInset))
        return NSPoint(x: x, y: y)
    }
}
