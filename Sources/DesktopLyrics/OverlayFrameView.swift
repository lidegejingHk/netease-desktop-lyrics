import AppKit

/// The only visual background for controls, lyrics and waveform.
/// Unlocked empty space accepts drags; locking lets desktop clicks pass through.
final class OverlayFrame {
    /// One step below `.floating`: above ordinary windows, below every content panel.
    /// AppKit raises a window to the front of its own level on mouse-down, so a
    /// background that shared `.floating` covered the lyric and waveform panels.
    static let backgroundLevel = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)

    let panel: NSPanel
    /// The verified song title: one truncated line that never takes pointer input.
    private(set) var titleLabel: NSTextField = OverlayTitleLabel(labelWithString: "")
    private let background: OverlayBackgroundView
    var onDrag: ((NSPoint) -> Void)? {
        didSet { background.onDrag = onDrag }
    }

    init() {
        let rect = NSRect(origin: .zero, size: OverlayLayout.outerSize)
        panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = Self.backgroundLevel
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
        titleLabel.alignment = .left
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.drawsBackground = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.isHidden = true
        background.addSubview(titleLabel)

        panel.contentView = background
        applyStyle(.defaultValue)
    }

    func follow(lyrics: NSRect) {
        panel.setFrame(OverlayLayout.outerFrame(for: lyrics), display: true)
        layoutTitle(for: lyrics)
    }

    /// Empty or whitespace-only titles hide the row instead of drawing a blank line.
    func show(title: String?) {
        let text = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        titleLabel.stringValue = text
        titleLabel.setAccessibilityLabel(text)
        titleLabel.isHidden = text.isEmpty
    }

    private func layoutTitle(for lyrics: NSRect) {
        let outer = OverlayLayout.outerFrame(for: lyrics)
        titleLabel.frame = OverlayLayout.titleFrame(for: lyrics)
            .offsetBy(dx: -outer.minX, dy: -outer.minY)
    }

    func applyStyle(_ style: OverlayStyle) {
        let fill = OverlayStyle.nsColor(style.backgroundRGB) ?? .black
        let tint = OverlayStyle.nsColor(style.textRGB) ?? .white
        background.layer?.backgroundColor =
            fill.withAlphaComponent(style.backgroundOpacity).cgColor
        background.layer?.borderColor =
            tint.withAlphaComponent(min(0.24, style.backgroundOpacity * 0.22)).cgColor
        titleLabel.textColor = tint.withAlphaComponent(0.72)
    }

    func setLocked(_ locked: Bool) {
        panel.ignoresMouseEvents = locked
    }

    func setVisible(_ visible: Bool) {
        if visible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
    }
}

/// Visual only: every click falls through to the draggable background beneath it.
private final class OverlayTitleLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
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
