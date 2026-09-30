import AppKit

/// A mouse target separate from the click-through lyric window.
final class OverlayControls: NSObject {
    static let expandedSize = NSSize(width: ToolbarPlacement.expandedWidth,
                                     height: ToolbarPlacement.expandedHeight)
    static let collapsedSize = OverlayLayout.collapsedToolbarSize

    /// Separate transparent layout panels; only the individual icons receive events.
    let panel: NSPanel
    let playbackPanel: NSPanel
    private(set) var controlPanels: [NSPanel] = []
    var onDrag: ((NSPoint) -> Void)?
    var onToggleLock: (() -> Void)?
    var onToggleSettings: (() -> Void)?
    var onToggleCollapsed: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onTogglePlayback: (() -> Void)?
    var onNext: (() -> Void)?

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
        playbackPanel = NSPanel(contentRect: NSRect(origin: .zero, size: OverlayLayout.playbackSize),
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        super.init()
        for window in [panel, playbackPanel] {
            window.level = .floating
            window.animationBehavior = .none
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.hidesOnDeactivate = false
            window.ignoresMouseEvents = true
            let backdrop = NSView(frame: NSRect(origin: .zero, size: window.frame.size))
            backdrop.wantsLayer = true
            backdrop.layer?.backgroundColor = NSColor.clear.cgColor
            window.contentView = backdrop
        }

        makeButton(lockButton, symbol: "lock.open", fallback: "◇", label: "锁定歌词位置", action: #selector(toggleLock))
        makeButton(settingsButton, symbol: "paintpalette", fallback: "◐", label: "设置歌词样式", action: #selector(toggleSettings))
        makeButton(collapseButton, symbol: "chevron.right", fallback: "−", label: "收起工具条", action: #selector(toggleCollapsed))
        makeButton(expandButton, symbol: "slider.horizontal.3", fallback: "+", label: "展开歌词工具条", action: #selector(toggleCollapsed))
        makeButton(previousButton, symbol: "backward.end.fill", fallback: "❮", label: "上一首", action: #selector(previousTrack))
        makeButton(playbackButton, symbol: "play.fill", fallback: "▶", label: "播放", action: #selector(togglePlayback))
        makeButton(nextButton, symbol: "forward.end.fill", fallback: "❯", label: "下一首", action: #selector(nextTrack))
        for (index, view) in [lockButton, settingsButton, collapseButton, expandButton,
                              previousButton, playbackButton, nextButton].enumerated() {
            let size: NSSize
            switch index {
            case 4, 6: size = NSSize(width: 34, height: 30)
            case 5: size = NSSize(width: 38, height: 32)
            default: size = NSSize(width: 34, height: 32)
            }
            controlPanels.append(makeControlPanel(for: view, size: size))
        }
        expandButton.isHidden = true
        setPlaybackAvailability(previous: false, toggle: .unavailable, next: false)
    }

    private func makeControlPanel(for view: NSView, size: NSSize) -> NSPanel {
        let window = NSPanel(contentRect: NSRect(origin: .zero, size: size),
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
        view.frame = NSRect(origin: .zero, size: size)
        window.contentView = view
        return window
    }

    func applyStyle(_ style: OverlayStyle) {
        let tint = OverlayStyle.nsColor(style.textRGB) ?? .white
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        playbackPanel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        for button in [lockButton, settingsButton, collapseButton, expandButton,
                       previousButton, playbackButton, nextButton] {
            let opacity: CGFloat = button === playbackButton ? 1.0
                : ((button === previousButton || button === nextButton) ? 0.84 : 0.94)
            button.contentTintColor = tint.withAlphaComponent(opacity)
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
            let size: CGFloat = button === playbackButton ? 19 : 16
            let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
            button.image = image.withSymbolConfiguration(configuration) ?? image
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
        // The transparent layout surface never intercepts clicks. A disabled
        // icon should behave likewise, particularly when the frame is locked.
        for (index, button) in [(4, previousButton), (5, playbackButton), (6, nextButton)] {
            controlPanels[index].ignoresMouseEvents = !button.isEnabled
        }
        let shouldPause = toggle == .pause
        let label = shouldPause ? "暂停" : "播放"
        playbackButton.toolTip = label
        playbackButton.setAccessibilityLabel(label)
        updateImage(playbackButton, symbol: shouldPause ? "pause.fill" : "play.fill",
                    fallback: shouldPause ? "Ⅱ" : "▶")
    }

    /// Locking changes the lyric and background hit targets only, never the tools.
    func setLocked(_ locked: Bool) {
        let label = locked ? "解锁歌词位置" : "锁定歌词位置"
        lockButton.toolTip = label
        lockButton.setAccessibilityLabel(label)
        updateImage(lockButton, symbol: locked ? "lock" : "lock.open", fallback: locked ? "◆" : "◇")
    }

    func setCollapsed(_ collapsed: Bool) {
        isCollapsed = collapsed
        lockButton.isHidden = collapsed
        settingsButton.isHidden = collapsed
        collapseButton.isHidden = collapsed
        expandButton.isHidden = !collapsed
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
        let toolOrigin = ToolbarPlacement.origin(overlay: overlay, size: Self.expandedSize)
        let toolOffsets: [CGFloat] = [3, 43, 83]
        for (index, x) in toolOffsets.enumerated() {
            controlPanels[index].setFrameOrigin(NSPoint(x: toolOrigin.x + x,
                                                        y: toolOrigin.y + 2))
        }
        controlPanels[3].setFrameOrigin(NSPoint(x: point.x + 4, y: point.y + 2))

        let playback = OverlayLayout.playbackFrame(for: overlay)
        playbackPanel.setFrameOrigin(playback.origin)
        for (index, x) in zip(4...6, [CGFloat(3), 47, 95]) {
            controlPanels[index].setFrameOrigin(NSPoint(x: playback.minX + x,
                                                        y: playback.minY + (index == 5 ? 0 : 1)))
        }
    }

    func setVisible(_ visible: Bool) {
        isVisible = visible
        updateVisiblePanels()
    }

    private func updateVisiblePanels() {
        if isVisible {
            panel.orderFrontRegardless()
            playbackPanel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
            playbackPanel.orderOut(nil)
        }
        for (index, window) in controlPanels.enumerated() {
            let shouldShow = isVisible && (index >= 4 || (isCollapsed ? index == 3 : index < 3))
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
