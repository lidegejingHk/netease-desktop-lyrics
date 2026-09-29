import AppKit

/// Compute a safe origin after a display layout changes, preserving on-screen placement.
enum OverlayVisibility {
    static func origin(for overlay: NSRect, visibleFrames: [NSRect]) -> NSPoint {
        guard !visibleFrames.isEmpty else { return overlay.origin }
        let intersects = visibleFrames.contains { screen in
            let visible = screen.intersection(overlay)
            return !visible.isNull && visible.width >= min(40, overlay.width)
                && visible.height >= min(40, overlay.height)
        }
        if intersects { return overlay.origin }
        let target = visibleFrames.min(by: { first, second in
            hypot(first.midX - overlay.midX, first.midY - overlay.midY)
                < hypot(second.midX - overlay.midX, second.midY - overlay.midY)
        })!
        return NSPoint(x: min(max(overlay.minX, target.minX),
                              max(target.minX, target.maxX - overlay.width)),
                       y: min(max(overlay.minY, target.minY),
                              max(target.minY, target.maxY - overlay.height)))
    }
}
