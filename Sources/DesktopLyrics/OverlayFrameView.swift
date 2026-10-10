import AppKit

/// The only visual background for controls, lyrics and waveform.
/// Unlocked empty space accepts drags; locking lets desktop clicks pass through.
final class OverlayFrame {
    /// One step below `.floating`: above ordinary windows, below every content panel.
    /// AppKit raises a window to the front of its own level on mouse-down, so a
    /// background that shared `.floating` covered the lyric and waveform panels.
    static let backgroundLevel = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)

    let panel: NSPanel
    /// The verified song title: one line that never takes pointer input and turns
    /// into a slow marquee while it cannot fit the reserved row.
    private(set) var titleView = MarqueeTitleView(frame: .zero)
    private let background: OverlayBackgroundView
    /// A hairline sheen above the fill: paper's soft cut edge on a light theme,
    /// a faint rim on a dark one. Rounded by itself because the fill clips.
    private let sheen = OverlaySheenView()
    private var currentTitle = ""
    private var titleRowVisible = true
    private var style = OverlayStyle.defaultValue
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
        sheen.wantsLayer = true
        sheen.layer?.cornerRadius = 21
        sheen.layer?.borderWidth = 1
        sheen.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        background.addSubview(sheen)
        titleView.isHidden = true
        background.addSubview(titleView)

        panel.contentView = background
        applyStyle(.defaultValue)
    }

    func follow(lyrics: NSRect) {
        panel.setFrame(OverlayLayout.outerFrame(for: lyrics), display: true)
        sheen.frame = background.bounds
        layoutTitle(for: lyrics)
    }

    /// Empty or whitespace-only titles hide the row instead of drawing a blank line.
    func show(title: String?) {
        currentTitle = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        titleView.show(title: currentTitle)
        refreshTitleRow()
    }

    /// The title shares the tool row, so it follows the pointer as well.
    func setTitleVisible(_ visible: Bool) {
        titleRowVisible = visible
        refreshTitleRow()
    }

    /// Three independent reasons to hide the row: no verified title, the pointer
    /// left the overlay, or the user switched the song title off in the settings.
    private func refreshTitleRow() {
        titleView.isHidden = !titleRowVisible || !style.showsTitle || currentTitle.isEmpty
    }

    private func layoutTitle(for lyrics: NSRect) {
        let outer = OverlayLayout.outerFrame(for: lyrics)
        titleView.frame = OverlayLayout.titleFrame(for: lyrics)
            .offsetBy(dx: -outer.minX, dy: -outer.minY)
    }

    func applyStyle(_ style: OverlayStyle) {
        self.style = style
        let fill = OverlayStyle.nsColor(style.backgroundRGB) ?? .black
        let tint = OverlayStyle.nsColor(style.textRGB) ?? .white
        background.layer?.backgroundColor =
            fill.withAlphaComponent(style.backgroundOpacity).cgColor
        // The edge follows the text tone so a light paper and a dark panel both
        // get a border that reads: slightly darker on paper, slightly lighter on ink.
        background.layer?.borderColor =
            tint.withAlphaComponent(min(0.16, style.backgroundOpacity * 0.14)).cgColor
        titleView.applyStyle(style)
        refreshTitleRow()
    }

    func setLocked(_ locked: Bool) {
        panel.ignoresMouseEvents = locked
    }

    func setVisible(_ visible: Bool) {
        sheen.frame = background.bounds
        titleView.setOverlayVisible(visible)
        if visible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
    }
}

/// Purely decorative rim light: it must never take a mouse event from the
/// draggable background or the icon panels above it.
private final class OverlaySheenView: NSView {
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
