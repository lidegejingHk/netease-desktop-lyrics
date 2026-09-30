import AppKit

/// A mouse target separate from the click-through lyric window.
final class OverlayControls: NSObject {
    static let expandedSize = NSSize(width: ToolbarPlacement.expandedWidth,
                                     height: ToolbarPlacement.expandedHeight)
    static let collapsedSize = OverlayLayout.collapsedToolbarSize

    /// Transparent layout panel; only the small icon windows receive events.
    let panel: NSPanel
    private(set) var controlPanels: [NSPanel] = []
    var onDrag: ((NSPoint) -> Void)?
    var onToggleLock: (() -> Void)?
    var onToggleSettings: (() -> Void)?
    var onToggleCollapsed: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onTogglePlayback: (() -> Void)?
    var onNext: (() -> Void)?

    private let dragHandle = OverlayDragHandle(frame: NSRect(x: 0, y: 0, width: 34, height: 32))
    private let lockButton = NSButton(title: "", target: nil, action: nil)
    private let settingsButton = NSButton(title: "", target: nil, action: nil)
    private let collapseButton = NSButton(title: "", target: nil, action: nil)
    private let expandButton = NSButton(title: "", target: nil, action: nil)
    private let previousButton = NSButton(title: "", target: nil, action: nil)
    private let playbackButton = NSButton(title: "", target: nil, action: nil)
    private let nextButton = NSButton(title: "", target: nil, action: nil)
    private(set) var isCollapsed = false
    private var isVisible = false
    private var lastOverlay = NSRect.zero

    override init() {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.expandedSize),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.level = .floating
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        let backdrop = NSView(frame: NSRect(origin: .zero, size: Self.expandedSize))
        backdrop.wantsLayer = true
        backdrop.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = backdrop

        dragHandle.onDrag = { [weak self] delta in self?.onDrag?(delta) }
        makeButton(lockButton, symbol: "lock.open", fallback: "◇", label: "锁定歌词位置", action: #selector(toggleLock))
        makeButton(settingsButton, symbol: "paintpalette", fallback: "◐", label: "设置歌词样式", action: #selector(toggleSettings))
        makeButton(collapseButton, symbol: "chevron.right", fallback: "−", label: "收起工具条", action: #selector(toggleCollapsed))
        makeButton(expandButton, symbol: "slider.horizontal.3", fallback: "+", label: "展开歌词工具条", action: #selector(toggleCollapsed))
        makeButton(previousButton, symbol: "backward.end.fill", fallback: "❮", label: "上一首", action: #selector(previousTrack))
        makeButton(playbackButton, symbol: "play.fill", fallback: "▶", label: "播放", action: #selector(togglePlayback))
        makeButton(nextButton, symbol: "forward.end.fill", fallback: "❯", label: "下一首", action: #selector(nextTrack))
        for view in [dragHandle, lockButton, settingsButton, collapseButton, expandButton,
                     previousButton, playbackButton, nextButton] {
            controlPanels.append(makeControlPanel(for: view))
        }
        expandButton.isHidden = true
        setPlaybackAvailability(previous: false, toggle: .unavailable, next: false)
    }

    private func makeControlPanel(for view: NSView) -> NSPanel {
        let window = NSPanel(contentRect: NSRect(origin: .zero, size: NSSize(width: 34, height: 32)),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        // Reordering panels must not leave a fading, visually present control unable to receive clicks.
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = false
        window.contentView = view
        return window
    }

    func applyStyle(_ style: OverlayStyle) {
        let tint = OverlayStyle.nsColor(style.textRGB) ?? .white
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        dragHandle.tintColor = tint
        for button in [lockButton, settingsButton, collapseButton, expandButton,
                       previousButton, playbackButton, nextButton] {
            button.contentTintColor = tint.withAlphaComponent(0.94)
        }
    }

    private func makeButton(_ button: NSButton, symbol: String, fallback: String,
                            label: String, action: Selector) {
        button.target = self
        button.action = action
        button.isBordered = false
        button.bezelStyle = .recessed
        button.contentTintColor = .white
        button.focusRingType = .exterior
        button.toolTip = label
        button.setAccessibilityLabel(label)
        updateImage(button, symbol: symbol, fallback: fallback)
    }

    private func updateImage(_ button: NSButton, symbol: String, fallback: String) {
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            button.image = image
            button.imagePosition = .imageOnly
        } else {
            button.image = nil
            button.title = fallback
        }
    }

    enum PlaybackToggle {
        case unavailable
        case play
        case pause
    }

    func setPlaybackAvailability(previous: Bool, toggle: PlaybackToggle, next: Bool) {
        previousButton.isEnabled = previous
        nextButton.isEnabled = next
        playbackButton.isEnabled = toggle != .unavailable
        let shouldPause = toggle == .pause
        let label = shouldPause ? "暂停" : "播放"
        playbackButton.toolTip = label
        playbackButton.setAccessibilityLabel(label)
        updateImage(playbackButton, symbol: shouldPause ? "pause.fill" : "play.fill",
                    fallback: shouldPause ? "Ⅱ" : "▶")
    }

    func setLocked(_ locked: Bool) {
        dragHandle.isLocked = locked
        controlPanels[0].ignoresMouseEvents = locked
        let label = locked ? "解锁歌词位置" : "锁定歌词位置"
        lockButton.toolTip = label
        lockButton.setAccessibilityLabel(label)
        updateImage(lockButton, symbol: locked ? "lock" : "lock.open", fallback: locked ? "◆" : "◇")
    }

    func setCollapsed(_ collapsed: Bool) {
        isCollapsed = collapsed
        dragHandle.isHidden = collapsed
        lockButton.isHidden = collapsed
        settingsButton.isHidden = collapsed
        collapseButton.isHidden = collapsed
        expandButton.isHidden = !collapsed
        previousButton.isHidden = collapsed
        playbackButton.isHidden = collapsed
        nextButton.isHidden = collapsed
        let size = collapsed ? Self.collapsedSize : Self.expandedSize
        panel.setContentSize(size)
        panel.contentView?.frame = NSRect(origin: .zero, size: size)
        follow(overlay: lastOverlay)
        updateVisiblePanels()
    }

    func follow(overlay: NSRect) {
        lastOverlay = overlay
        let point = ToolbarPlacement.origin(overlay: overlay,
                                            size: isCollapsed ? Self.collapsedSize : Self.expandedSize)
        panel.setFrameOrigin(point)
        // Playback first, then placement and appearance; all seven controls are
        // a single row inside the independent upper-right toolbar.
        let offsets: [NSPoint] = [NSPoint(x: 121, y: 6), NSPoint(x: 159, y: 6),
                                  NSPoint(x: 197, y: 6), NSPoint(x: 235, y: 6),
                                  NSPoint(x: 1, y: 6), NSPoint(x: 7, y: 6),
                                  NSPoint(x: 45, y: 6), NSPoint(x: 83, y: 6)]
        for (window, offset) in zip(controlPanels, offsets) {
            window.setFrameOrigin(NSPoint(x: point.x + offset.x, y: point.y + offset.y))
        }
    }

    func setVisible(_ visible: Bool) {
        isVisible = visible
        updateVisiblePanels()
    }

    private func updateVisiblePanels() {
        if isVisible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
        for (index, window) in controlPanels.enumerated() {
            let shouldShow = isVisible && (isCollapsed ? index == 4 : index != 4)
            if shouldShow { window.orderFrontRegardless() } else { window.orderOut(nil) }
        }
    }

    @objc private func toggleLock() { onToggleLock?() }
    @objc private func toggleSettings() { onToggleSettings?() }
    @objc private func toggleCollapsed() { onToggleCollapsed?() }
    @objc private func previousTrack() { if previousButton.isEnabled { onPrevious?() } }
    @objc private func togglePlayback() { if playbackButton.isEnabled { onTogglePlayback?() } }
    @objc private func nextTrack() { if nextButton.isEnabled { onNext?() } }
}

private final class OverlayDragHandle: NSView {
    var onDrag: ((NSPoint) -> Void)?
    var tintColor: NSColor = .white {
        didSet { updateTint() }
    }
    var isLocked = false {
        didSet { updateTint() }
    }
    private let glyph = NSTextField(labelWithString: "✥")

    override init(frame: NSRect) {
        super.init(frame: frame)
        glyph.frame = bounds
        glyph.alignment = .center
        glyph.font = .systemFont(ofSize: 22, weight: .regular)
        updateTint()
        addSubview(glyph)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("拖动歌词位置")
        toolTip = "拖动歌词位置"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    private func updateTint() {
        glyph.textColor = tintColor.withAlphaComponent(isLocked ? 0.42 : 0.94)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, bounds.contains(convert(point, from: superview)) else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        // Keep drag events bound to this handle; no window-relative coordinates are cached.
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isLocked else { return }
        // NSEvent deltas are independent of our toolbar moving after each callback.
        // Device-space Y is flipped relative to AppKit window coordinates.
        onDrag?(NSPoint(x: event.deltaX, y: -event.deltaY))
    }
}
