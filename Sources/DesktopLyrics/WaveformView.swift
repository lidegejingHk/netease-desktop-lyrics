import AppKit

/// An ambient playback indicator, not a sound meter or an audio input.
enum WaveformMotion {
    static func shouldAnimate(playing: Bool, reduceMotion: Bool) -> Bool {
        playing && !reduceMotion
    }
}

final class WaveformView: NSView {
    private let bars = (0..<5).map { _ in CALayer() }
    private var timer: Timer?
    private var phase = 0
    private var playing = false
    private var overlayVisible = true
    var reduceMotionProvider: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private static let steps: [[CGFloat]] = [
        [6, 13, 8, 18, 10], [11, 8, 17, 12, 6], [17, 12, 7, 15, 9],
        [8, 18, 11, 7, 15], [14, 9, 16, 10, 7]
    ]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for bar in bars {
            bar.cornerRadius = 2
            layer?.addSublayer(bar)
        }
        setTint(.white)
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
        for bar in bars { bar.backgroundColor = color.cgColor }
    }

    func setPlaying(_ value: Bool) {
        playing = value
        updateMotion()
    }

    func setOverlayVisible(_ value: Bool) {
        overlayVisible = value
        updateMotion()
    }

    func refreshMotionPreference() {
        updateMotion()
    }

    @objc private func accessibilityOptionsChanged(_ notification: Notification) {
        updateMotion()
    }

    private func updateMotion() {
        let animate = overlayVisible && WaveformMotion.shouldAnimate(
            playing: playing, reduceMotion: reduceMotionProvider())
        if animate, timer == nil {
            let timer = Timer(timeInterval: 0.11, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.phase = (self.phase + 1) % Self.steps.count
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
        let heights = isAnimating ? Self.steps[phase] : [5, 7, 9, 7, 5]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            let height = heights[index]
            bar.frame = NSRect(x: CGFloat(index) * 8 + 2,
                               y: (bounds.height - height) / 2,
                               width: 3, height: height)
        }
        CATransaction.commit()
    }
}
