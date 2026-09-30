import AppKit

/// A click-through, visually transparent lower panel containing a full-width progress waveform.
final class WaveformRail {
    let panel: NSPanel
    let content: WaveformRailView
    private var isVisible = false

    init() {
        let frame = NSRect(origin: .zero, size: OverlayLayout.railSize)
        panel = NSPanel(contentRect: frame,
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        content = WaveformRailView(frame: frame)
        panel.contentView = content
    }

    func follow(lyrics: NSRect) {
        panel.setFrame(OverlayLayout.railFrame(for: lyrics), display: true)
    }

    func applyStyle(_ style: OverlayStyle) { content.applyStyle(style) }

    func show(fraction: CGFloat, active: Bool, playing: Bool) {
        content.show(fraction: fraction, active: active, playing: playing)
    }

    func setVisible(_ visible: Bool) {
        isVisible = visible
        content.waveform.setOverlayVisible(visible)
        if visible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
    }
}

final class WaveformRailView: NSView {
    let waveform = WaveformView(frame: .zero)
    private let progressTrack = NSView()
    private let progress = NSView()
    private var active = false
    private(set) var progressFraction: CGFloat = 0
    var progressWidth: CGFloat { progress.frame.width }
    var progressTrackWidth: CGFloat { progressTrack.frame.width }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for view in [progressTrack, progress, waveform] {
            view.wantsLayer = true
            addSubview(view)
        }
        progressTrack.layer?.cornerRadius = 1
        progress.layer?.cornerRadius = 1
        applyStyle(.defaultValue)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    func applyStyle(_ style: OverlayStyle) {
        let text = OverlayStyle.nsColor(style.textRGB) ?? .white
        layer?.backgroundColor = NSColor.clear.cgColor
        progressTrack.layer?.backgroundColor = text.withAlphaComponent(0.11).cgColor
        progress.layer?.backgroundColor = text.withAlphaComponent(0.50).cgColor
        waveform.setTint(text)
    }

    func show(fraction: CGFloat, active: Bool, playing: Bool) {
        self.active = active
        progressFraction = fraction.isFinite ? min(1, max(0, fraction)) : 0
        progressTrack.isHidden = !active
        progress.isHidden = !active
        // Keep a quiet, static baseline while waiting for a song.
        waveform.isHidden = false
        waveform.setProgress(active ? progressFraction : 0)
        waveform.setPlaying(active && playing)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let trackWidth = max(0, bounds.width - 28)
        progressTrack.frame = NSRect(x: 14, y: 4, width: trackWidth, height: 1)
        progress.frame = NSRect(x: 14, y: 4,
                                width: active ? trackWidth * progressFraction : 0, height: 1)
        waveform.frame = NSRect(x: 12, y: 7, width: max(0, bounds.width - 24),
                                height: max(0, bounds.height - 10))
    }
}
