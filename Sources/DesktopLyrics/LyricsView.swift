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
    private let waveform = WaveformView(frame: .zero)
    private var style = OverlayStyle.defaultValue
    private var primaryText = "正在等待网易云音乐…"
    private var secondaryText = ""
    private var progressFraction: CGFloat = 0
    private var controlsFrame: NSRect?
    private struct FitCache {
        let original: String
        let width: CGFloat
        let fit: FittedLyric
    }
    private var mainFits: [FitCache] = []
    private var detailFits: [FitCache] = []

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
            label.lineBreakMode = .byCharWrapping
            label.maximumNumberOfLines = 2
            label.drawsBackground = false
            label.isEditable = false
            label.isSelectable = false
            addSubview(label)
        }
        mainLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        detailLabel.font = .systemFont(ofSize: 15, weight: .medium)

        for view in [accent, progressTrack, progress, waveform] {
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

    /// The independent controls panel's frame, converted to lyric-view coordinates.
    func setControlsFrame(_ frame: NSRect) {
        controlsFrame = frame
        needsLayout = true
    }

    func setOverlayVisible(_ visible: Bool) {
        waveform.setOverlayVisible(visible)
    }

    func applyStyle(_ newStyle: OverlayStyle) {
        style = newStyle
        let background = OverlayStyle.nsColor(newStyle.backgroundRGB) ?? .black
        let text = OverlayStyle.nsColor(newStyle.textRGB) ?? .white
        let chip = OverlayStyle.nsColor(newStyle.chipRGB) ?? .black
        layer?.backgroundColor = background.withAlphaComponent(newStyle.backgroundOpacity).cgColor
        layer?.borderColor = text.withAlphaComponent(min(0.14, newStyle.backgroundOpacity * 0.15)).cgColor
        mainLabel.textColor = text
        detailLabel.textColor = text.withAlphaComponent(0.70)
        waveform.setTint(text.withAlphaComponent(0.85))
        let chipColor = chip.withAlphaComponent(newStyle.chipOpacity).cgColor
        mainChip.layer?.backgroundColor = chipColor
        detailChip.layer?.backgroundColor = chipColor
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        accent.frame = NSRect(x: width / 2 - 18, y: bounds.height - 15, width: 36, height: 5)

        let lyricsRight = min(width - 32, controlsFrame.map { $0.minX - 20 } ?? width - 32)
        let mainBand = NSRect(x: 32, y: 88, width: max(0, lyricsRight - 32), height: 61)
        let detailBand = NSRect(x: 36, y: 35, width: max(0, lyricsRight - 36), height: 48)
        layoutText(primaryText, in: mainLabel, chip: mainChip,
                   band: mainBand,
                   preferredSize: 24, minimumSize: 16, weight: .semibold)
        layoutText(secondaryText, in: detailLabel, chip: detailChip,
                   band: detailBand,
                   preferredSize: 15, minimumSize: 12, weight: .medium)

        let trackWidth = max(0, width - 132)
        progressTrack.frame = NSRect(x: 32, y: 15, width: trackWidth, height: 3)
        progress.frame = NSRect(x: 32, y: 15, width: trackWidth * progressFraction, height: 3)
        waveform.frame = NSRect(x: width - 89, y: 7, width: 43, height: 22)
    }

    private func layoutText(_ original: String, in label: NSTextField, chip: NSView,
                            band: NSRect, preferredSize: CGFloat, minimumSize: CGFloat,
                            weight: NSFont.Weight) {
        let full = fittedText(original, width: max(1, band.width - 24), for: label,
                              preferredSize: preferredSize, minimumSize: minimumSize, weight: weight)
        let fittedWidth = min(band.width, max(24, full.width + 24))
        // Preserve the original centered appearance for short lyrics, but
        // center longer lyrics in the left text area rather than under buttons.
        let rightClearance = controlsFrame.map { $0.minX - 20 } ?? bounds.maxX - 32
        let canCenterOnWindow = bounds.midX - fittedWidth / 2 >= band.minX &&
            bounds.midX + fittedWidth / 2 <= rightClearance
        let centerX = canCenterOnWindow ? bounds.midX : band.midX
        let lineHeight = ceil(full.font.ascender - full.font.descender + full.font.leading)
        let labelHeight = min(band.height, CGFloat(full.lineCount) * lineHeight + 4)
        label.frame = NSRect(x: centerX - fittedWidth / 2,
                             y: band.midY - labelHeight / 2,
                             width: fittedWidth, height: labelHeight)
        label.font = full.font
        label.stringValue = full.text
        label.setAccessibilityLabel(original)

        chip.isHidden = original.isEmpty || style.chipOpacity <= 0
        if !chip.isHidden {
            let chipHeight = min(band.height, labelHeight + 8)
            chip.frame = NSRect(x: label.frame.minX, y: band.midY - chipHeight / 2,
                                width: fittedWidth, height: chipHeight)
        }
    }

    private func fittedText(_ original: String, width: CGFloat, for label: NSTextField,
                            preferredSize: CGFloat, minimumSize: CGFloat,
                            weight: NSFont.Weight) -> FittedLyric {
        let isMain = label === mainLabel
        var cache = isMain ? mainFits : detailFits
        if cache.first?.original != original { cache.removeAll() }
        if let existing = cache.first(where: { $0.width == width }) { return existing.fit }
        let fit = FittedLyric(original, width: width,
                              preferredSize: preferredSize, minimumSize: minimumSize, weight: weight)
        cache.append(FitCache(original: original, width: width, fit: fit))
        if cache.count > 2 { cache.removeFirst() }
        if isMain { mainFits = cache } else { detailFits = cache }
        return fit
    }

    func show(primary: String, secondary: String, fraction: CGFloat, active: Bool,
              playing: Bool = false) {
        primaryText = primary
        secondaryText = secondary
        progressFraction = min(1, max(0, fraction))
        progress.isHidden = !active
        progressTrack.isHidden = !active
        waveform.isHidden = !active
        waveform.setPlaying(active && playing)
        accent.layer?.backgroundColor = (active
            ? NSColor(red: 1, green: 0.28, blue: 0.34, alpha: 1)
            : NSColor.white.withAlphaComponent(0.35)).cgColor
        needsLayout = true
    }
}

/// TextKit's implicit wrapping is hard to bound with font changes. Explicitly fit at
/// grapheme boundaries so a line never hides underneath the independent control panels.
private struct FittedLyric {
    let font: NSFont
    let text: String
    let width: CGFloat
    let lineCount: Int

    init(_ original: String, width: CGFloat, preferredSize: CGFloat,
         minimumSize: CGFloat, weight: NSFont.Weight) {
        let normalized = original.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        // The engine bounds its JSON lines, but formatting must also have a
        // predictable upper bound when the player supplies a pathological line.
        // Bound pathological input without splitting a composed character.
        let wasCapped = normalized.count > 512
        let characters = Array(normalized.prefix(512))
        var size = preferredSize
        var chosenFont = NSFont.systemFont(ofSize: minimumSize, weight: weight)
        var chosenLines: [String] = []
        var consumed = 0
        while size >= minimumSize {
            let candidateFont = NSFont.systemFont(ofSize: size, weight: weight)
            let result = Self.lines(in: characters, width: width, font: candidateFont)
            chosenFont = candidateFont
            chosenLines = result.lines
            consumed = result.consumed
            if consumed == characters.count && !wasCapped { break }
            size -= 0.5
        }
        if consumed < characters.count || wasCapped {
            if chosenLines.isEmpty { chosenLines = [""] }
            var last = Array(chosenLines.removeLast())
            while !last.isEmpty && Self.measure(String(last) + "…", font: chosenFont) > width {
                last.removeLast()
            }
            chosenLines.append(String(last) + "…")
        }
        font = chosenFont
        text = chosenLines.joined(separator: "\n")
        lineCount = max(1, chosenLines.count)
        self.width = chosenLines.map { Self.measure($0, font: chosenFont) }.max() ?? 0
    }

    private static func lines(in characters: [Character], width: CGFloat,
                              font: NSFont) -> (lines: [String], consumed: Int) {
        var index = 0
        var lines: [String] = []
        while index < characters.count && lines.count < 2 {
            if characters[index] == "\n" {
                lines.append("")
                index += 1
                continue
            }
            let hardEnd = characters[index...].firstIndex(of: "\n") ?? characters.count
            var low = index
            var high = hardEnd
            while low < high {
                let middle = low + (high - low + 1) / 2
                if measure(String(characters[index..<middle]), font: font) <= width {
                    low = middle
                } else {
                    high = middle - 1
                }
            }
            var end = low
            // If even a single grapheme cannot fit at minimum size, do not draw it
            // outside the reserved text band; the ellipsis below remains legible.
            if low == index {
                lines.append("")
                break
            }
            if end < hardEnd,
               let whitespace = characters[index..<end].lastIndex(where: { $0.isWhitespace }),
               whitespace > index {
                end = whitespace
            }
            lines.append(String(characters[index..<end]))
            index = end
            if index == hardEnd && index < characters.count {
                index += 1
            } else {
                while index < hardEnd && characters[index].isWhitespace { index += 1 }
            }
        }
        return (lines, index)
    }

    private static func measure(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}
