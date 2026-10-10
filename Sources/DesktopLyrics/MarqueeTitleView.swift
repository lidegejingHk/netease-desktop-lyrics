import AppKit

/// The verified song title on the single top-row line. A title that fits stays
/// still; a longer one drifts slowly and seamlessly instead of truncating.
/// Reduce Motion is honoured: the row truncates and never animates.
final class MarqueeTitleView: NSView {
    /// Blank space between the two scrolled copies, in points.
    static let loopGap: CGFloat = 40
    /// Deliberately slow: the title is background information, not a ticker.
    static let pointsPerSecond: CGFloat = 30
    static let tickInterval: TimeInterval = 1.0 / 30

    private let leading = MarqueeTitleLabel(labelWithString: "")
    private let trailing = MarqueeTitleLabel(labelWithString: "")
    private var font = NSFont.systemFont(ofSize: 13, weight: .medium)
    private var offset: CGFloat = 0
    private var timer: Timer?
    private var lastTick: TimeInterval?
    private var overlayVisible = true
    var reduceMotionProvider: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion } {
        didSet { updateMotion() }
    }

    private(set) var text = ""
    var isScrolling: Bool { timer != nil }
    /// Test hook: how far the leading copy has travelled to the left.
    var scrollOffset: CGFloat { offset }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // The row is a window onto the two copies, never a growing label.
        layer?.masksToBounds = true
        for label in [leading, trailing] {
            label.alignment = .left
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            label.drawsBackground = false
            label.isEditable = false
            label.isSelectable = false
            label.setAccessibilityElement(false)
            addSubview(label)
        }
        trailing.isHidden = true
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        NSWorkspace.shared.notificationCenter.addObserver(self,
            selector: #selector(accessibilityOptionsChanged(_:)),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    deinit {
        timer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// Visual only: the title never takes pointer input away from the background.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(title: String?) {
        let trimmed = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != text else { return }
        text = trimmed
        offset = 0
        leading.stringValue = trimmed
        trailing.stringValue = trimmed
        setAccessibilityLabel(trimmed)
        needsLayout = true
        updateMotion()
    }

    func applyStyle(_ style: OverlayStyle) {
        let tint = OverlayStyle.nsColor(style.textRGB) ?? .white
        for label in [leading, trailing] {
            label.font = font
            label.textColor = tint.withAlphaComponent(0.72)
        }
        needsLayout = true
        updateMotion()
    }

    override func layout() {
        super.layout()
        positionCopies()
    }

    override func viewDidHide() { updateMotion() }
    override func viewDidUnhide() { updateMotion() }
    override func viewDidMoveToWindow() { updateMotion() }

    @objc private func accessibilityOptionsChanged(_ notification: Notification) { updateMotion() }

    /// One step of the slow drift. The timer calls it; tests call it directly so
    /// the marquee can be asserted without waiting on a real clock.
    func advance(by seconds: TimeInterval) {
        guard shouldScroll, seconds > 0 else { return }
        let distance = scrollDistance
        guard distance > 0 else { return }
        offset += Self.pointsPerSecond * CGFloat(seconds)
        if offset >= distance { offset -= distance }
        positionCopies()
    }

    /// Measured by the label itself: the cell's own insets then never truncate the
    /// copy that is supposed to be drawn at its natural width.
    private var textWidth: CGFloat {
        ceil(leading.sizeThatFits(NSSize(width: CGFloat.greatestFiniteMagnitude,
                                         height: max(1, bounds.height))).width)
    }

    /// The period of the loop: one full copy plus the blank gap behind it.
    var scrollDistance: CGFloat { textWidth + Self.loopGap }

    /// The enclosing overlay can be hidden without changing this view's own hidden
    /// flag; a paused row never keeps a timer alive off screen.
    func setOverlayVisible(_ visible: Bool) {
        overlayVisible = visible
        updateMotion()
    }

    private var shouldScroll: Bool {
        overlayVisible && !isHidden && window != nil && !reduceMotionProvider() &&
            textWidth > bounds.width + 0.5
    }

    /// A scrolled title shows two natural-size copies; a fitted or truncated one
    /// shows a single copy across the whole row.
    private func positionCopies() {
        let scrolling = shouldScroll
        if !scrolling { offset = 0 }
        let width = scrolling ? textWidth : bounds.width
        for (index, label) in [leading, trailing].enumerated() {
            label.frame = NSRect(x: CGFloat(index) * scrollDistance - offset, y: 0,
                                 width: width, height: bounds.height)
        }
        trailing.isHidden = !scrolling
    }

    private func updateMotion() {
        needsLayout = true
        let animate = shouldScroll
        if animate, timer == nil {
            let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
                guard let self else { return }
                let now = ProcessInfo.processInfo.systemUptime
                let previous = self.lastTick ?? now
                self.lastTick = now
                self.advance(by: now - previous)
            }
            self.timer = timer
            lastTick = ProcessInfo.processInfo.systemUptime
            RunLoop.main.add(timer, forMode: .common)
        } else if !animate {
            timer?.invalidate()
            timer = nil
            lastTick = nil
        }
        positionCopies()
    }
}

/// Visual only: every click falls through to the draggable background beneath it.
private final class MarqueeTitleLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
