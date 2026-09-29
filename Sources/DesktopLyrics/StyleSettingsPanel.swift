import AppKit

/// Native controls for appearance only; no playback state enters this window.
final class StyleSettingsPanel: NSObject, NSWindowDelegate {
    let panel: NSPanel
    var onStyleChange: ((OverlayStyle) -> Void)?
    var onClose: (() -> Void)?

    private let backgroundWell = NSColorWell(frame: .zero)
    private let textWell = NSColorWell(frame: .zero)
    private let chipWell = NSColorWell(frame: .zero)
    private let backgroundSlider = NSSlider(frame: .zero)
    private let chipSlider = NSSlider(frame: .zero)
    private let backgroundPercent = NSTextField(labelWithString: "91%")
    private let chipPercent = NSTextField(labelWithString: "0%")
    private var style: OverlayStyle

    init(style: OverlayStyle) {
        self.style = style
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 310),
                        styleMask: [.titled, .closable, .utilityWindow],
                        backing: .buffered, defer: false)
        super.init()
        panel.title = "歌词样式"
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
        addLabel("浮层背景透明度", frame: NSRect(x: 22, y: 135, width: 190, height: 22), to: root)
        addSlider(backgroundSlider, percent: backgroundPercent, label: "浮层背景透明度", y: 104, to: root)
        addLabel("文字背底透明度", frame: NSRect(x: 22, y: 74, width: 190, height: 22), to: root)
        addSlider(chipSlider, percent: chipPercent, label: "文字背底透明度", y: 43, to: root)
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
        well.supportsAlpha = false
        well.target = self
        well.action = #selector(colorChanged(_:))
        well.setAccessibilityLabel(label)
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
    }

    func close() { panel.close() }
    var isVisible: Bool { panel.isVisible }

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

    func windowWillClose(_ notification: Notification) {
        NSColorPanel.shared.orderOut(nil)
        onClose?()
    }
}
