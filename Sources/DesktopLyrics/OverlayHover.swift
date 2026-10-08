import AppKit

/// The overlay shows its controls only while the pointer is inside the whole
/// background. A short grace period keeps a grazing pointer from flickering them,
/// and the lyric plus its waveform always stay visible.
struct OverlayHover {
    static let margin: CGFloat = 8
    static let hideDelay: TimeInterval = 0.4

    private(set) var controlsVisible = true
    private var leftAt: TimeInterval?

    static func inside(point: NSPoint, envelope: NSRect) -> Bool {
        envelope.insetBy(dx: -margin, dy: -margin).contains(point)
    }

    mutating func update(now: TimeInterval, inside: Bool) -> Bool {
        if inside {
            leftAt = nil
            controlsVisible = true
        } else if controlsVisible {
            guard let left = leftAt else {
                leftAt = now
                return controlsVisible
            }
            if now - left >= Self.hideDelay { controlsVisible = false }
        }
        return controlsVisible
    }
}
