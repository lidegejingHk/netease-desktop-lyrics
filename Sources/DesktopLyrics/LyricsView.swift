import AppKit

/// The Rust bridge owns lyric timing; this view only draws the current line and its appearance.
final class LyricsView: NSView {
    private let mainLabel = NSTextField(labelWithString: "正在等待网易云音乐…")
    private let detailLabel = NSTextField(labelWithString: "")
    private let mainChip = NSView()
    private let detailChip = NSView()
    private let accent = NSView()
    private let progressTrack = NSView()
    private let progress = NSView()
    private var style = OverlayStyle.defaultValue
    private var progressFraction: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 19
        layer?.masksToBounds = true
        layer?.borderWidth = 1

        for chip in [mainChip, detailChip] {
            chip.wantsLayer = true
            chip.layer?.cornerRadius = 8
            addSubview(chip)
        }
        for label in [mainLabel, detailLabel] {
            label.alignment = .center
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.drawsBackground = false
            label.isEditable = false
            label.isSelectable = false
            addSubview(label)
        }
        mainLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        detailLabel.font = .systemFont(ofSize: 15, weight: .medium)

        for view in [accent, progressTrack, progress] {
            view.wantsLayer = true
            addSubview(view)
        }
        accent.layer?.cornerRadius = 3
        progressTrack.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        progressTrack.layer?.cornerRadius = 2
        progress.layer?.backgroundColor = NSColor(red: 1, green: 0.31, blue: 0.37, alpha: 0.95).cgColor
        progress.layer?.cornerRadius = 2
        applyStyle(style)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    func applyStyle(_ newStyle: OverlayStyle) {
        style = newStyle
        let background = OverlayStyle.nsColor(newStyle.backgroundRGB) ?? .black
        let text = OverlayStyle.nsColor(newStyle.textRGB) ?? .white
        let chip = OverlayStyle.nsColor(newStyle.chipRGB) ?? .black
        layer?.backgroundColor = background.withAlphaComponent(newStyle.backgroundOpacity).cgColor
        layer?.borderColor = text.withAlphaComponent(min(0.14, newStyle.backgroundOpacity * 0.15)).cgColor
        mainLabel.textColor = text
        detailLabel.textColor = text.withAlphaComponent(0.70)
        let chipColor = chip.withAlphaComponent(newStyle.chipOpacity).cgColor
        mainChip.layer?.backgroundColor = chipColor
        detailChip.layer?.backgroundColor = chipColor
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        accent.frame = NSRect(x: width / 2 - 18, y: bounds.height - 15, width: 36, height: 5)
        mainLabel.frame = NSRect(x: 32, y: 51, width: max(0, width - 64), height: 35)
        detailLabel.frame = NSRect(x: 36, y: 28, width: max(0, width - 72), height: 22)
        progressTrack.frame = NSRect(x: 32, y: 15, width: max(0, width - 64), height: 3)
        progress.frame = NSRect(x: 32, y: 15, width: max(0, width - 64) * progressFraction, height: 3)
        layoutChip(mainChip, for: mainLabel, height: 34)
        layoutChip(detailChip, for: detailLabel, height: 24)
    }

    private func layoutChip(_ chip: NSView, for label: NSTextField, height: CGFloat) {
        chip.isHidden = style.chipOpacity == 0 || label.stringValue.isEmpty
        guard !chip.isHidden else { return }
        let font = label.font ?? NSFont.systemFont(ofSize: 15)
        let textWidth = (label.stringValue as NSString).size(withAttributes: [.font: font]).width
        let chipWidth = min(textWidth, label.frame.width) + 24
        chip.frame = NSRect(x: bounds.midX - chipWidth / 2,
                            y: label.frame.midY - height / 2,
                            width: chipWidth, height: height)
    }

    func show(primary: String, secondary: String, fraction: CGFloat, active: Bool) {
        mainLabel.stringValue = primary
        detailLabel.stringValue = secondary
        progressFraction = min(1, max(0, fraction))
        progress.isHidden = !active
        progressTrack.isHidden = !active
        accent.layer?.backgroundColor = (active
            ? NSColor(red: 1, green: 0.28, blue: 0.34, alpha: 1)
            : NSColor.white.withAlphaComponent(0.35)).cgColor
        needsLayout = true
    }
}
