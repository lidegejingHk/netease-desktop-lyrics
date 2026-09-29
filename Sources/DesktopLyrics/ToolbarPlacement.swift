import AppKit

/// Toolbar position in global AppKit screen coordinates. Pure so it can be tested without windows.
enum ToolbarPlacement {
    static func origin(overlay: NSRect, size: NSSize, visibleFrames: [NSRect]) -> NSPoint {
        let gap: CGFloat = 8
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
            return NSPoint(x: overlay.maxX - size.width, y: overlay.maxY + gap)
        }
        let x = min(max(overlay.maxX - size.width, screen.minX + gap),
                    max(screen.minX + gap, screen.maxX - size.width - gap))
        let above = overlay.maxY + gap
        let below = overlay.minY - size.height - gap
        let desiredY = above + size.height + gap <= screen.maxY ? above : below
        let y = min(max(desiredY, screen.minY + gap),
                    max(screen.minY + gap, screen.maxY - size.height - gap))
        return NSPoint(x: x, y: y)
    }
}
