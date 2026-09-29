import AppKit

/// A mouse target separate from the click-through lyric window.
final class OverlayControls: NSObject {
    static let expandedSize = NSSize(width: 166, height: 38)
    static let collapsedSize = NSSize(width: 38, height: 38)

    let panel: NSPanel
    var onDrag: ((NSPoint) -> Void)?
    var onToggleLock: (() -> Void)?
    var onToggleSettings: (() -> Void)?
    var onToggleCollapsed: (() -> Void)?

    private let dragHandle = OverlayDragHandle(frame: NSRect(x: 7, y: 3, width: 34, height: 32))
    private let lockButton = NSButton(title: "", target: nil, action: nil)
    private let settingsButton = NSButton(title: "", target: nil, action: nil)
    private let collapseButton = NSButton(title: "", target: nil, action: nil)
    private let expandButton = NSButton(title: "", target: nil, action: nil)
    private let background = NSView()
    private(set) var isCollapsed = false
    private var lastOverlay = NSRect.zero
    private var lastVisibleFrames: [NSRect] = []

    override init() {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.expandedSize),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false

        background.frame = NSRect(origin: .zero, size: Self.expandedSize)
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.94).cgColor
        background.layer?.borderWidth = 1
        background.layer?.borderColor = NSColor.white.withAlphaComponent(0.17).cgColor
        background.layer?.cornerRadius = 12
        panel.contentView = background

        dragHandle.onDrag = { [weak self] delta in self?.onDrag?(delta) }
        background.addSubview(dragHandle)
        makeButton(lockButton, symbol: "lock.open", fallback: "◇", label: "锁定歌词位置", action: #selector(toggleLock))
        makeButton(settingsButton, symbol: "paintpalette", fallback: "◐", label: "设置歌词样式", action: #selector(toggleSettings))
        makeButton(collapseButton, symbol: "chevron.right", fallback: "−", label: "收起工具条", action: #selector(toggleCollapsed))
        makeButton(expandButton, symbol: "slider.horizontal.3", fallback: "+", label: "展开歌词工具条", action: #selector(toggleCollapsed))
        lockButton.frame = NSRect(x: 46, y: 3, width: 34, height: 32)
        settingsButton.frame = NSRect(x: 85, y: 3, width: 34, height: 32)
        collapseButton.frame = NSRect(x: 124, y: 3, width: 34, height: 32)
        expandButton.frame = NSRect(x: 2, y: 3, width: 34, height: 32)
        expandButton.isHidden = true
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
        background.addSubview(button)
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

    func setLocked(_ locked: Bool) {
        dragHandle.isLocked = locked
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
        let size = collapsed ? Self.collapsedSize : Self.expandedSize
        background.frame = NSRect(origin: .zero, size: size)
        panel.setContentSize(size)
        follow(overlay: lastOverlay, visibleFrames: lastVisibleFrames)
    }

    func follow(overlay: NSRect, visibleFrames: [NSRect]) {
        lastOverlay = overlay
        lastVisibleFrames = visibleFrames
        guard !visibleFrames.isEmpty else { return }
        let point = ToolbarPlacement.origin(overlay: overlay,
                                            size: isCollapsed ? Self.collapsedSize : Self.expandedSize,
                                            visibleFrames: visibleFrames)
        panel.setFrameOrigin(point)
    }

    func setVisible(_ visible: Bool) {
        if visible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
    }

    @objc private func toggleLock() { onToggleLock?() }
    @objc private func toggleSettings() { onToggleSettings?() }
    @objc private func toggleCollapsed() { onToggleCollapsed?() }
}

private final class OverlayDragHandle: NSView {
    var onDrag: ((NSPoint) -> Void)?
    var isLocked = false {
        didSet { glyph.textColor = .white.withAlphaComponent(isLocked ? 0.32 : 0.92) }
    }
    private let glyph = NSTextField(labelWithString: "✥")
    private var previousMouseLocation = NSPoint.zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        glyph.frame = bounds
        glyph.alignment = .center
        glyph.font = .systemFont(ofSize: 22, weight: .regular)
        glyph.textColor = .white.withAlphaComponent(0.92)
        addSubview(glyph)
        setAccessibilityRole(.button)
        setAccessibilityLabel("拖动歌词位置")
        toolTip = "拖动歌词位置"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, bounds.contains(convert(point, from: superview)) else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        guard !isLocked else { return }
        previousMouseLocation = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isLocked else { return }
        let current = NSEvent.mouseLocation
        let delta = NSPoint(x: current.x - previousMouseLocation.x,
                            y: current.y - previousMouseLocation.y)
        previousMouseLocation = current
        onDrag?(delta)
    }
}
