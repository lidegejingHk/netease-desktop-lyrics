import AppKit

/// A utility panel that closes like a popover: Esc, Command-W and any click outside it.
final class StyleSettingsWindow: NSPanel {
    var onDismiss: (() -> Void)?

    override func cancelOperation(_ sender: Any?) { onDismiss?() }

    override func keyDown(with event: NSEvent) {
        guard !handleDismissKey(event) else { return }
        super.keyDown(with: event)
    }

    /// An accessory app has no menu bar, so Command-W arrives as a plain key equivalent.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard !handleDismissKey(event) else { return true }
        return super.performKeyEquivalent(with: event)
    }

    private func handleDismissKey(_ event: NSEvent) -> Bool {
        let escape = event.keyCode == 53
        let commandW = event.charactersIgnoringModifiers == "w"
            && event.modifierFlags.contains(.command)
        guard escape || commandW else { return false }
        onDismiss?()
        return true
    }
}

/// A swatch that places the shared colour panel before AppKit shows it, so it
/// never appears at whatever position the panel was last left in.
final class AnchoredColorWell: NSColorWell {
    var colorPanelAnchor: (() -> NSPoint)?

    override func mouseDown(with event: NSEvent) {
        if let anchor = colorPanelAnchor?() { NSColorPanel.shared.setFrameOrigin(anchor) }
        super.mouseDown(with: event)
    }
}

/// Native controls for appearance only; no playback state enters this window.
final class StyleSettingsPanel: NSObject, NSWindowDelegate {
    static let colorPanelGap: CGFloat = 10
    private static let colorPanelMargin: CGFloat = 8

    /// The colour panel sits beside the settings panel, centred on the swatch that
    /// opened it, and is clamped into the screen that holds that swatch.
    static func colorPanelOrigin(well: NSRect, panel: NSRect, colorPanel: NSSize,
                                 visibleFrames: [NSRect]) -> NSPoint {
        let screen = visibleFrames.first { $0.intersects(well) }
            ?? visibleFrames.first ?? NSRect(x: 0, y: 0, width: colorPanel.width, height: colorPanel.height)
        let left = panel.minX - colorPanelGap - colorPanel.width
        let right = panel.maxX + colorPanelGap
        let x = left >= screen.minX + colorPanelMargin ? left : right
        let y = well.midY - colorPanel.height / 2
        return NSPoint(
            x: min(max(x, screen.minX + colorPanelMargin),
                   screen.maxX - colorPanel.width - colorPanelMargin),
            y: min(max(y, screen.minY + colorPanelMargin),
                   screen.maxY - colorPanel.height - colorPanelMargin))
    }

    let panel: StyleSettingsWindow
    var onStyleChange: ((OverlayStyle) -> Void)?
    var onClose: (() -> Void)?

    private let backgroundWell = AnchoredColorWell(frame: .zero)
    private let textWell = AnchoredColorWell(frame: .zero)
    private let chipWell = AnchoredColorWell(frame: .zero)
    private let backgroundSlider = NSSlider(frame: .zero)
    private let chipSlider = NSSlider(frame: .zero)
    private let backgroundPercent = NSTextField(labelWithString: "91%")
    private let chipPercent = NSTextField(labelWithString: "0%")
    private var style: OverlayStyle
    private var outsideClickMonitors: [Any] = []

    /// True while the panel observes clicks that should dismiss it.
    var isWatchingOutsideClicks: Bool { !outsideClickMonitors.isEmpty }

    init(style: OverlayStyle) {
        self.style = style
        // Titled but not closable: the panel is dismissed by losing focus, Esc,
        // Command-W or a click outside, not by a title-bar button.
        panel = StyleSettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 310),
                                    styleMask: [.titled, .utilityWindow],
                                    backing: .buffered, defer: false)
        super.init()
        panel.onDismiss = { [weak self] in self?.close() }
        panel.title = "歌词样式"
        panel.isMovable = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        NSColorPanel.shared.showsAlpha = false

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 310))
        panel.contentView = root
        addLabel("浮层背景颜色", frame: NSRect(x: 22, y: 260, width: 190, height: 22), to: root)
        addWell(backgroundWell, label: "浮层背景颜色", y: 255, to: root)
        addLabel("歌词文字颜色", frame: NSRect(x: 22, y: 219, width: 190, height: 22), to: root)
        addWell(textWell, label: "歌词文字颜色", y: 214, to: root)
        addLabel("文字背底颜色", frame: NSRect(x: 22, y: 178, width: 190, height: 22), to: root)
        addWell(chipWell, label: "文字背底颜色", y: 173, to: root)
        addLabel("浮层背景不透明度", frame: NSRect(x: 22, y: 135, width: 190, height: 22), to: root)
        addSlider(backgroundSlider, percent: backgroundPercent, label: "浮层背景不透明度", y: 104, to: root)
        addLabel("文字背底不透明度", frame: NSRect(x: 22, y: 74, width: 190, height: 22), to: root)
        addSlider(chipSlider, percent: chipPercent, label: "文字背底不透明度", y: 43, to: root)
        let reset = NSButton(title: "恢复默认", target: self, action: #selector(resetToDefaults))
        reset.frame = NSRect(x: 271, y: 10, width: 88, height: 27)
        reset.setAccessibilityLabel("恢复默认歌词样式")
        root.addSubview(reset)
        refreshControls()
    }

    private func addLabel(_ text: String, frame: NSRect, to root: NSView) {
        let label = NSTextField(labelWithString: text)
        label.frame = frame
        root.addSubview(label)
    }

    private func addWell(_ well: NSColorWell, label: String, y: CGFloat, to root: NSView) {
        well.frame = NSRect(x: 260, y: y, width: 96, height: 28)
        if #available(macOS 14.0, *) { well.supportsAlpha = false }
        well.target = self
        well.action = #selector(colorChanged(_:))
        well.setAccessibilityLabel(label)
        (well as? AnchoredColorWell)?.colorPanelAnchor = { [weak self, weak well] in
            guard let self, let well else { return NSColorPanel.shared.frame.origin }
            return self.colorPanelOrigin(for: well)
        }
        root.addSubview(well)
    }

    private func addSlider(_ slider: NSSlider, percent: NSTextField,
                           label: String, y: CGFloat, to root: NSView) {
        slider.frame = NSRect(x: 22, y: y, width: 279, height: 26)
        slider.minValue = 0
        slider.maxValue = 100
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(opacityChanged(_:))
        slider.setAccessibilityLabel(label)
        root.addSubview(slider)
        percent.frame = NSRect(x: 309, y: y + 4, width: 52, height: 22)
        percent.alignment = .right
        root.addSubview(percent)
    }

    func show(near toolbar: NSRect, visibleFrames: [NSRect]) {
        let screen = visibleFrames.first(where: { $0.contains(toolbar.origin) })
            ?? visibleFrames.first ?? NSScreen.main?.visibleFrame
        if let screen {
            let width = panel.frame.width
            let height = panel.frame.height
            let desiredX = toolbar.maxX - width
            let desiredY = toolbar.maxY + 8 + height <= screen.maxY
                ? toolbar.maxY + 8 : toolbar.minY - height - 8
            let x = min(max(desiredX, screen.minX + 8), screen.maxX - width - 8)
            let y = min(max(desiredY, screen.minY + 8), screen.maxY - height - 8)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installOutsideClickMonitors()
    }

    func close() { panel.close() }
    var isVisible: Bool { panel.isVisible }

    private func colorPanelOrigin(for well: NSView) -> NSPoint {
        Self.colorPanelOrigin(well: panel.convertToScreen(well.convert(well.bounds, to: nil)),
                              panel: panel.frame,
                              colorPanel: NSColorPanel.shared.frame.size,
                              visibleFrames: NSScreen.screens.map(\.visibleFrame))
    }

    /// A click anywhere but this panel and the colour panel it opened dismisses it.
    @discardableResult
    func dismissIfClickingOutside(_ window: NSWindow?) -> Bool {
        guard panel.isVisible else { return false }
        if window === panel || window === NSColorPanel.shared { return false }
        close()
        return true
    }

    private func installOutsideClickMonitors() {
        guard outsideClickMonitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // Local events cover our own overlay windows; global ones cover other apps.
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.dismissIfClickingOutside(event.window)
            return event
        }) {
            outsideClickMonitors.append(local)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            self?.dismissIfClickingOutside(nil)
        }) {
            outsideClickMonitors.append(global)
        }
    }

    private func removeOutsideClickMonitors() {
        for monitor in outsideClickMonitors { NSEvent.removeMonitor(monitor) }
        outsideClickMonitors.removeAll()
    }

    private func refreshControls() {
        backgroundWell.color = OverlayStyle.nsColor(style.backgroundRGB) ?? .black
        textWell.color = OverlayStyle.nsColor(style.textRGB) ?? .white
        chipWell.color = OverlayStyle.nsColor(style.chipRGB) ?? .black
        backgroundSlider.doubleValue = style.backgroundOpacity * 100
        chipSlider.doubleValue = style.chipOpacity * 100
        backgroundPercent.stringValue = "\(Int(backgroundSlider.doubleValue.rounded()))%"
        chipPercent.stringValue = "\(Int(chipSlider.doubleValue.rounded()))%"
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        if sender === backgroundWell { style.backgroundRGB = OverlayStyle.rgbHex(sender.color) }
        if sender === textWell { style.textRGB = OverlayStyle.rgbHex(sender.color) }
        if sender === chipWell { style.chipRGB = OverlayStyle.rgbHex(sender.color) }
        onStyleChange?(style)
    }

    @objc private func opacityChanged(_ sender: NSSlider) {
        if sender === backgroundSlider { style.backgroundOpacity = sender.doubleValue / 100 }
        if sender === chipSlider { style.chipOpacity = sender.doubleValue / 100 }
        refreshControls()
        onStyleChange?(style)
    }

    @objc private func resetToDefaults() {
        style = .defaultValue
        refreshControls()
        onStyleChange?(style)
    }

    /// Losing focus dismisses the panel, unless the shared colour panel took key:
    /// that is the colour-picking flow the panel itself started.
    func shouldDismissAfterLosingKey(colourPanelIsKey: Bool) -> Bool {
        panel.isVisible && !colourPanelIsKey
    }

    func windowDidResignKey(_ notification: Notification) {
        guard shouldDismissAfterLosingKey(colourPanelIsKey: NSColorPanel.shared.isKeyWindow) else {
            return
        }
        close()
    }

    func windowWillClose(_ notification: Notification) {
        removeOutsideClickMonitors()
        NSColorPanel.shared.orderOut(nil)
        onClose?()
    }
}
