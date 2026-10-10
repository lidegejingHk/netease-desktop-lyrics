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
    private let accentWell = AnchoredColorWell(frame: .zero)
    private let backgroundSlider = NSSlider(frame: .zero)
    private let chipSlider = NSSlider(frame: .zero)
    private let spacingSlider = NSSlider(frame: .zero)
    private let mainFontSlider = NSSlider(frame: .zero)
    private let detailFontSlider = NSSlider(frame: .zero)
    private let delaySlider = NSSlider(frame: .zero)
    private let titleCheckbox = NSButton(checkboxWithTitle: "显示歌曲名", target: nil, action: nil)
    private let waveformCheckbox = NSButton(checkboxWithTitle: "显示声浪", target: nil, action: nil)
    private let backgroundValue = NSTextField(labelWithString: "91%")
    private let chipValue = NSTextField(labelWithString: "0%")
    private let spacingValue = NSTextField(labelWithString: "8 pt")
    private let mainFontValue = NSTextField(labelWithString: "24 pt")
    private let detailFontValue = NSTextField(labelWithString: "15 pt")
    private let delayValue = NSTextField(labelWithString: "200 ms")
    private var style: OverlayStyle
    private var outsideClickMonitors: [Any] = []

    /// True while the panel observes clicks that should dismiss it.
    var isWatchingOutsideClicks: Bool { !outsideClickMonitors.isEmpty }

    init(style: OverlayStyle) {
        self.style = style
        // Titled but not closable: the panel is dismissed by losing focus, Esc,
        // Command-W or a click outside, not by a title-bar button.
        panel = StyleSettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 620),
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
        configureSharedColorPanel()

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 620))
        panel.contentView = root
        addCheckbox(titleCheckbox, label: "显示歌曲名", x: 22, y: 572, to: root)
        addCheckbox(waveformCheckbox, label: "显示声浪", x: 200, y: 572, to: root)
        addLabel("浮层背景颜色", frame: NSRect(x: 22, y: 497, width: 190, height: 22), to: root)
        addWell(backgroundWell, label: "浮层背景颜色", y: 492, to: root)
        addLabel("歌词文字颜色", frame: NSRect(x: 22, y: 457, width: 190, height: 22), to: root)
        addWell(textWell, label: "歌词文字颜色", y: 452, to: root)
        addLabel("文字背底颜色", frame: NSRect(x: 22, y: 417, width: 190, height: 22), to: root)
        addWell(chipWell, label: "文字背底颜色", y: 412, to: root)
        addLabel("强调颜色（声浪与扫光）", frame: NSRect(x: 22, y: 377, width: 210, height: 22), to: root)
        addWell(accentWell, label: "强调颜色", y: 372, to: root)
        addLabel("歌词延迟（觉得比人声早，就调大）", frame: NSRect(x: 22, y: 338, width: 240, height: 22), to: root)
        addSlider(delaySlider, value: delayValue, label: "歌词延迟",
                  y: 307, range: OverlayStyle.delayRange, scale: 1, to: root)
        addLabel("浮层背景不透明度", frame: NSRect(x: 22, y: 281, width: 190, height: 22), to: root)
        addSlider(backgroundSlider, value: backgroundValue, label: "浮层背景不透明度",
                  y: 250, range: OverlayStyle.opacityRange, scale: 100, to: root)
        addLabel("文字背底不透明度", frame: NSRect(x: 22, y: 224, width: 190, height: 22), to: root)
        addSlider(chipSlider, value: chipValue, label: "文字背底不透明度",
                  y: 193, range: OverlayStyle.opacityRange, scale: 100, to: root)
        addLabel("歌词上下留白", frame: NSRect(x: 22, y: 167, width: 190, height: 22), to: root)
        addSlider(spacingSlider, value: spacingValue, label: "歌词上下留白",
                  y: 136, range: OverlayStyle.spacingRange, scale: 1, to: root)
        addLabel("歌词字号", frame: NSRect(x: 22, y: 110, width: 190, height: 22), to: root)
        addSlider(mainFontSlider, value: mainFontValue, label: "歌词字号",
                  y: 79, range: OverlayStyle.mainFontRange, scale: 1, to: root)
        addLabel("翻译字号", frame: NSRect(x: 22, y: 53, width: 190, height: 22), to: root)
        addSlider(detailFontSlider, value: detailFontValue, label: "翻译字号",
                  y: 22, range: OverlayStyle.detailFontRange, scale: 1, to: root)
        let reset = NSButton(title: "恢复默认", target: self, action: #selector(resetToDefaults))
        reset.frame = NSRect(x: 268, y: 534, width: 92, height: 26)
        reset.setAccessibilityLabel("恢复默认歌词样式")
        root.addSubview(reset)
        refreshControls()
    }

    /// The two optional elements sit above the appearance controls: same panel,
    /// same live-apply path, no second place to look for them.
    private func addCheckbox(_ box: NSButton, label: String, x: CGFloat, y: CGFloat, to root: NSView) {
        box.frame = NSRect(x: x, y: y, width: 170, height: 24)
        box.target = self
        box.action = #selector(checkboxChanged(_:))
        box.setAccessibilityLabel(label)
        root.addSubview(box)
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

    /// `scale` maps the stored value to slider units, 100% for the two opacities.
    private func addSlider(_ slider: NSSlider, value: NSTextField, label: String,
                           y: CGFloat, range: ClosedRange<Double>, scale: Double,
                           to root: NSView) {
        slider.frame = NSRect(x: 22, y: y, width: 279, height: 26)
        slider.minValue = range.lowerBound * scale
        slider.maxValue = range.upperBound * scale
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderChanged(_:))
        slider.setAccessibilityLabel(label)
        root.addSubview(slider)
        value.frame = NSRect(x: 309, y: y + 4, width: 52, height: 22)
        value.alignment = .right
        root.addSubview(value)
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
        // AppKit can restore the panel's own chrome when it is ordered front.
        configureSharedColorPanel()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installOutsideClickMonitors()
    }

    func close() { panel.close() }
    var isVisible: Bool { panel.isVisible }

    /// The shared colour panel belongs to this flow: it must not be dragged away and
    /// offers no window buttons, because it closes together with this panel.
    private func configureSharedColorPanel() {
        let colorPanel = NSColorPanel.shared
        colorPanel.showsAlpha = false
        colorPanel.isMovable = false
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            colorPanel.standardWindowButton(button)?.isHidden = true
        }
    }

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
        accentWell.color = OverlayStyle.nsColor(style.accentRGB) ?? .orange
        backgroundSlider.doubleValue = style.backgroundOpacity * 100
        chipSlider.doubleValue = style.chipOpacity * 100
        titleCheckbox.state = style.showsTitle ? .on : .off
        waveformCheckbox.state = style.showsWaveform ? .on : .off
        spacingSlider.doubleValue = style.lyricSpacing
        mainFontSlider.doubleValue = style.mainFontSize
        detailFontSlider.doubleValue = style.detailFontSize
        delaySlider.doubleValue = style.lyricDelayMs
        backgroundValue.stringValue = "\(Int((style.backgroundOpacity * 100).rounded()))%"
        chipValue.stringValue = "\(Int((style.chipOpacity * 100).rounded()))%"
        spacingValue.stringValue = "\(Int(style.lyricSpacing.rounded())) pt"
        mainFontValue.stringValue = "\(Int(style.mainFontSize.rounded())) pt"
        detailFontValue.stringValue = "\(Int(style.detailFontSize.rounded())) pt"
        delayValue.stringValue = "\(Int(style.lyricDelayMs.rounded())) ms"
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        if sender === backgroundWell { style.backgroundRGB = OverlayStyle.rgbHex(sender.color) }
        if sender === textWell { style.textRGB = OverlayStyle.rgbHex(sender.color) }
        if sender === chipWell { style.chipRGB = OverlayStyle.rgbHex(sender.color) }
        if sender === accentWell { style.accentRGB = OverlayStyle.rgbHex(sender.color) }
        onStyleChange?(style)
    }

    @objc private func checkboxChanged(_ sender: NSButton) {
        let on = sender.state == .on
        if sender === titleCheckbox { style.showsTitle = on }
        if sender === waveformCheckbox { style.showsWaveform = on }
        onStyleChange?(style)
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        if sender === backgroundSlider { style.backgroundOpacity = sender.doubleValue / 100 }
        else if sender === chipSlider { style.chipOpacity = sender.doubleValue / 100 }
        else if sender === spacingSlider { style.lyricSpacing = sender.doubleValue.rounded() }
        else if sender === mainFontSlider { style.mainFontSize = sender.doubleValue.rounded() }
        else if sender === detailFontSlider { style.detailFontSize = sender.doubleValue.rounded() }
        else if sender === delaySlider { style.lyricDelayMs = sender.doubleValue.rounded() }
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
