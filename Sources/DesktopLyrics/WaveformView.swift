import AppKit

/// Decorative motion derived from playback state, never from the microphone or system audio.
enum WaveformMotion {
    static func shouldAnimate(playing: Bool, reduceMotion: Bool) -> Bool {
        playing && !reduceMotion
    }
}

final class WaveformView: NSView {
    static let barCount = 116
    private let bars = (0..<barCount).map { _ in CALayer() }
    private var timer: Timer?
    private var phase = 0
    private var playing = false
    private var overlayVisible = true
    private var tint = NSColor.white
    private var progress: CGFloat = 0
    var reduceMotionProvider: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for bar in bars {
            bar.cornerRadius = 1
            layer?.addSublayer(bar)
        }
        setAccessibilityElement(false)
        NSWorkspace.shared.notificationCenter.addObserver(self,
            selector: #selector(accessibilityOptionsChanged(_:)),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        updateBars()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    deinit {
        timer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    var isAnimating: Bool { timer != nil }

    func setTint(_ color: NSColor) {
        tint = color
        updateBars()
    }

    func setProgress(_ value: CGFloat) {
        progress = min(1, max(0, value))
        updateBars()
    }

    func setPlaying(_ value: Bool) {
        playing = value
        updateMotion()
    }

    func setOverlayVisible(_ value: Bool) {
        overlayVisible = value
        updateMotion()
    }

    func refreshMotionPreference() { updateMotion() }

    @objc private func accessibilityOptionsChanged(_ notification: Notification) { updateMotion() }

    private func updateMotion() {
        let animate = overlayVisible && WaveformMotion.shouldAnimate(
            playing: playing, reduceMotion: reduceMotionProvider())
        if animate, timer == nil {
            let timer = Timer(timeInterval: 0.11, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.phase = (self.phase + 1) % 60
                self.updateBars()
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else if !animate {
            timer?.invalidate()
            timer = nil
            phase = 0
        }
        updateBars()
    }

    override func layout() {
        super.layout()
        updateBars()
    }

    private func updateBars() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let spacing = bounds.width / CGFloat(Self.barCount)
        for (index, bar) in bars.enumerated() {
            // Sparse waves with small in-between movement read as a continuous
            // horizon instead of five large meters tucked in a corner.
            let wave = abs(sin(CGFloat(index) * 0.23 + CGFloat(phase) * 0.31))
            let swell = abs(sin(CGFloat(index) * 0.061 - CGFloat(phase) * 0.15))
            let height: CGFloat = isAnimating ? 3 + (wave * 0.45 + swell * 0.55) * 15 : 4 + wave * 7
            let x = CGFloat(index) * spacing
            bar.frame = NSRect(x: x + (spacing - 2) / 2,
                               y: (bounds.height - height) / 2,
                               width: 2, height: height)
            bar.backgroundColor = tint.withAlphaComponent(
                CGFloat(index) / CGFloat(Self.barCount) <= progress ? 0.88 : 0.27).cgColor
        }
        CATransaction.commit()
    }
}
