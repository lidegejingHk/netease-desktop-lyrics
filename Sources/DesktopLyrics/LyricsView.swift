import AppKit

/// The center region draws text and optional text-sized backings, but no separate card.
final class LyricsView: NSView {
    var onDrag: ((NSPoint) -> Void)?
    private let mainLabel = NSTextField(labelWithString: "正在等待网易云音乐…")
    private let detailLabel = NSTextField(labelWithString: "")
    private let mainChip = NSView()
    private let detailChip = NSView()
    private var style = OverlayStyle.defaultValue
    private var primaryText = "正在等待网易云音乐…"
    private var secondaryText = ""
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
        applyStyle(style)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }

    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, bounds.contains(convert(point, from: superview)) else { return nil }
        // The labels and optional chips are visual only: their full visible area
        // must behave like the rest of the unified, draggable background.
        return self
    }

    override func mouseDown(with event: NSEvent) {
        // Keep AppKit drag tracking in this view rather than moving its panel.
    }

    override func mouseDragged(with event: NSEvent) {
        onDrag?(NSPoint(x: event.deltaX, y: -event.deltaY))
    }

    func applyStyle(_ newStyle: OverlayStyle) {
        style = newStyle
        let text = OverlayStyle.nsColor(newStyle.textRGB) ?? .white
        let chip = OverlayStyle.nsColor(newStyle.chipRGB) ?? .black
        layer?.backgroundColor = NSColor.clear.cgColor
        mainLabel.textColor = text
        detailLabel.textColor = text.withAlphaComponent(0.70)
        let chipColor = chip.withAlphaComponent(newStyle.chipOpacity).cgColor
        mainChip.layer?.backgroundColor = chipColor
        detailChip.layer?.backgroundColor = chipColor
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let hasSecondary = !secondaryText.isEmpty
        let inset: CGFloat = 26
        let bandWidth = max(0, bounds.width - inset * 2)
        let primaryBand: NSRect
        if hasSecondary {
            primaryBand = NSRect(x: inset, y: 58, width: bandWidth, height: 60)
        } else {
            primaryBand = NSRect(x: inset, y: (bounds.height - 60) / 2,
                                 width: bandWidth, height: 60)
        }
        layoutText(primaryText, in: mainLabel, chip: mainChip, band: primaryBand,
                   preferredSize: 24, minimumSize: 16, weight: .semibold)
        detailLabel.isHidden = !hasSecondary
        if hasSecondary {
            layoutText(secondaryText, in: detailLabel, chip: detailChip,
                       band: NSRect(x: inset, y: 9, width: bandWidth, height: 44),
                       preferredSize: 15, minimumSize: 12, weight: .medium)
        } else {
            detailChip.isHidden = true
            detailLabel.setAccessibilityLabel("")
        }
    }

    private func layoutText(_ original: String, in label: NSTextField, chip: NSView,
                            band: NSRect, preferredSize: CGFloat, minimumSize: CGFloat,
                            weight: NSFont.Weight) {
        let full = fittedText(original, width: max(1, band.width - 24), for: label,
                              preferredSize: preferredSize, minimumSize: minimumSize, weight: weight)
        let fittedWidth = min(band.width, max(24, full.width + 24))
        let lineHeight = ceil(full.font.ascender - full.font.descender + full.font.leading)
        let labelHeight = min(band.height, CGFloat(full.lineCount) * lineHeight + 4)
        label.frame = NSRect(x: bounds.midX - fittedWidth / 2,
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

    func show(primary: String, secondary: String) {
        primaryText = primary
        secondaryText = secondary
        needsLayout = true
    }
}

/// Fit at grapheme boundaries, never silently drawing beyond a two-row band.
private struct FittedLyric {
    let font: NSFont
    let text: String
    let width: CGFloat
    let lineCount: Int

    init(_ original: String, width: CGFloat, preferredSize: CGFloat,
         minimumSize: CGFloat, weight: NSFont.Weight) {
        let normalized = original.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
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
        self.width = (chosenLines.map { Self.measure($0, font: chosenFont) }.max() ?? 0)
        lineCount = max(1, chosenLines.count)
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
