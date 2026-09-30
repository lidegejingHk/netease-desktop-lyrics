import AppKit

/// The only visual background for controls, lyrics and waveform.
/// Unlocked empty space accepts drags; locking lets desktop clicks pass through.
final class OverlayFrame {
    let panel: NSPanel
    private let background: OverlayBackgroundView
    var onDrag: ((NSPoint) -> Void)? {
        didSet { background.onDrag = onDrag }
    }

    init() {
        let rect = NSRect(origin: .zero, size: OverlayLayout.outerSize)
        panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = .floating
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false

        background = OverlayBackgroundView(frame: rect)
        background.wantsLayer = true
        background.layer?.cornerRadius = 21
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 1
        panel.contentView = background
        applyStyle(.defaultValue)
    }

    func follow(lyrics: NSRect) {
        panel.setFrame(OverlayLayout.outerFrame(for: lyrics), display: true)
    }

    func applyStyle(_ style: OverlayStyle) {
        let fill = OverlayStyle.nsColor(style.backgroundRGB) ?? .black
        let tint = OverlayStyle.nsColor(style.textRGB) ?? .white
        background.layer?.backgroundColor =
            fill.withAlphaComponent(style.backgroundOpacity).cgColor
        background.layer?.borderColor =
            tint.withAlphaComponent(min(0.24, style.backgroundOpacity * 0.22)).cgColor
    }

    func setLocked(_ locked: Bool) {
        panel.ignoresMouseEvents = locked
    }

    func setVisible(_ visible: Bool) {
        if visible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
    }
}

/// Keep drag tracking in the background view instead of moving its panel directly.
/// The owner applies one constrained position to all overlay windows.
private final class OverlayBackgroundView: NSView {
    var onDrag: ((NSPoint) -> Void)?

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        // Opt out of AppKit's background-window dragging so this view owns
        // subsequent drag events and the controller can constrain the group.
    }

    override func mouseDragged(with event: NSEvent) {
        // Device-space Y has the opposite sign to AppKit screen coordinates.
        onDrag?(NSPoint(x: event.deltaX, y: -event.deltaY))
    }
}
