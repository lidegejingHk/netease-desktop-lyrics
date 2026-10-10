import AppKit

/// Clamp the complete overlay background, not just its lyric content, to a display.
enum OverlayVisibility {
    /// The pointer-free magnetic edge keeps this much room inside the display.
    static let snapMargin: CGFloat = 16

    static func origin(for envelope: NSRect, visibleFrames: [NSRect]) -> NSPoint {
        guard !visibleFrames.isEmpty else { return envelope.origin }
        if visibleFrames.contains(where: { $0.contains(envelope) }) { return envelope.origin }
        let target = targetScreen(for: envelope, visibleFrames: visibleFrames)
        // A very narrow display cannot contain the complete group. Preserve the
        // upper-right tools and transport keys rather than the left lyric edge.
        let x = envelope.width > target.width ? target.maxX - envelope.width
            : min(max(envelope.minX, target.minX), target.maxX - envelope.width)
        let y = envelope.height > target.height ? target.maxY - envelope.height
            : min(max(envelope.minY, target.minY), target.maxY - envelope.height)
        return NSPoint(x: x, y: y)
    }

    /// The right-edge rail: the frame hugs the display it mostly occupies, one
    /// small margin inside the edge, and keeps that edge while its height changes.
    static func snappedRightOrigin(for envelope: NSRect, visibleFrames: [NSRect]) -> NSPoint {
        guard !visibleFrames.isEmpty else { return envelope.origin }
        let target = targetScreen(for: envelope, visibleFrames: visibleFrames)
        let proposed = NSRect(x: target.maxX - snapMargin - envelope.width, y: envelope.minY,
                              width: envelope.width, height: envelope.height)
        return origin(for: proposed, visibleFrames: visibleFrames)
    }

    /// The display that owns the largest part of the frame; ties go to the closest.
    private static func targetScreen(for envelope: NSRect, visibleFrames: [NSRect]) -> NSRect {
        visibleFrames.max(by: { first, second in
            let areaA = intersectionArea(first, envelope)
            let areaB = intersectionArea(second, envelope)
            if areaA != areaB { return areaA < areaB }
            return hypot(first.midX - envelope.midX, first.midY - envelope.midY)
                > hypot(second.midX - envelope.midX, second.midY - envelope.midY)
        })!
    }

    private static func intersectionArea(_ first: NSRect, _ second: NSRect) -> CGFloat {
        let intersection = first.intersection(second)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}
