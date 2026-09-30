import AppKit

/// Clamp the complete overlay background, not just its lyric content, to a display.
enum OverlayVisibility {
    static func origin(for envelope: NSRect, visibleFrames: [NSRect]) -> NSPoint {
        guard !visibleFrames.isEmpty else { return envelope.origin }
        if visibleFrames.contains(where: { $0.contains(envelope) }) { return envelope.origin }
        let target = visibleFrames.max(by: { first, second in
            let areaA = intersectionArea(first, envelope)
            let areaB = intersectionArea(second, envelope)
            if areaA != areaB { return areaA < areaB }
            return hypot(first.midX - envelope.midX, first.midY - envelope.midY)
                > hypot(second.midX - envelope.midX, second.midY - envelope.midY)
        })!
        // A very narrow display cannot contain the complete group. Preserve the
        // upper-right playback and expand controls rather than the left lyric edge.
        let x = envelope.width > target.width ? target.maxX - envelope.width
            : min(max(envelope.minX, target.minX), target.maxX - envelope.width)
        let y = envelope.height > target.height ? target.maxY - envelope.height
            : min(max(envelope.minY, target.minY), target.maxY - envelope.height)
        return NSPoint(x: x, y: y)
    }

    private static func intersectionArea(_ first: NSRect, _ second: NSRect) -> CGFloat {
        let intersection = first.intersection(second)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}
