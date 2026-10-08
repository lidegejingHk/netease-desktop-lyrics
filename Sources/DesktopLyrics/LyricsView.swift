import AppKit

/// The center region draws text and optional text-sized backings, but no separate card.
final class LyricsView: NSView {
    var onDrag: ((NSPoint) -> Void)?
    /// The band height that hugs the visible text with the selected spacing.
    private(set) var desiredBandHeight: CGFloat = OverlayLayout.lyricSize.height
    /// Called whenever the current text needs a different band height.
    var onBandHeightChange: ((CGFloat) -> Void)?
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
        let size: CGFloat
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
        if newStyle.mainFontSize != style.mainFontSize ||
            newStyle.detailFontSize != style.detailFontSize {
            mainFits.removeAll()
            detailFits.removeAll()
        }
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
        updateBandHeight()
    }

    override func layout() {
        super.layout()
        let spacing = CGFloat(style.lyricSpacing)
        let (primary, detail) = measureBand()
        detailLabel.isHidden = detail == nil
        guard let detail else {
            detailChip.isHidden = true
            detailLabel.setAccessibilityLabel("")
            // A lone status or waiting line hugs the band like one half of a pair.
            place(primary, in: mainLabel, chip: mainChip, bottom: spacing,
                  maximumHeight: LyricStack.maximumLineHeight(
                      preferredSize: CGFloat(style.mainFontSize), weight: .semibold))
            return
        }
        // One exact gap between the two visible text areas, with equal spacing
        // above and below the pair, so the band hugs what is actually drawn.
        place(detail, in: detailLabel, chip: detailChip, bottom: spacing,
              maximumHeight: LyricStack.maximumLineHeight(
                  preferredSize: CGFloat(style.detailFontSize), weight: .medium))
        place(primary, in: mainLabel, chip: mainChip,
              bottom: spacing + detail.height + LyricStack.gap,
              maximumHeight: LyricStack.maximumLineHeight(
                  preferredSize: CGFloat(style.mainFontSize), weight: .semibold))
    }

    /// The band height and the drawn text come from the same measurement, so the
    /// enclosing panel can resize without ever clipping a visible line.
    private func updateBandHeight() {
        guard bounds.width > 1 else { return }
        let (primary, detail) = measureBand()
        let height = LyricBand.height(primaryHeight: primary.height,
                                      detailHeight: detail?.height ?? 0,
                                      spacing: CGFloat(style.lyricSpacing))
        guard abs(height - desiredBandHeight) > 0.5 else { return }
        desiredBandHeight = height
        onBandHeightChange?(height)
    }

    /// Both `layout()` and the band height use this one measurement.
    private func measureBand() -> (primary: MeasuredLine, detail: MeasuredLine?) {
        let inset: CGFloat = 26
        let bandWidth = max(0, bounds.width - inset * 2)
        let primary = measured(primaryText, in: mainLabel, width: bandWidth,
                               preferredSize: CGFloat(style.mainFontSize),
                               minimumSize: LyricStack.minimumFontSize(
                                   preferred: CGFloat(style.mainFontSize),
                                   floor: LyricStack.mainMinimumFontSize),
                               weight: .semibold)
        guard !secondaryText.isEmpty else { return (primary, nil) }
        let detail = measured(secondaryText, in: detailLabel, width: bandWidth,
                              preferredSize: CGFloat(style.detailFontSize),
                              minimumSize: LyricStack.minimumFontSize(
                                  preferred: CGFloat(style.detailFontSize),
                                  floor: LyricStack.detailMinimumFontSize),
                              weight: .medium)
        return (primary, detail)
    }

    private func measured(_ original: String, in label: NSTextField, width: CGFloat,
                          preferredSize: CGFloat, minimumSize: CGFloat,
                          weight: NSFont.Weight) -> MeasuredLine {
        let fit = fittedText(original, width: max(1, width - 24), for: label,
                             preferredSize: preferredSize, minimumSize: minimumSize, weight: weight)
        let lineHeight = ceil(fit.font.ascender - fit.font.descender + fit.font.leading)
        return MeasuredLine(
            original: original,
            fit: fit,
            width: min(width, max(24, fit.width + 24)),
            height: min(LyricStack.maximumLineHeight(preferredSize: preferredSize, weight: weight),
                        CGFloat(fit.lineCount) * lineHeight + 4))
    }

    private func place(_ line: MeasuredLine, in label: NSTextField, chip: NSView,
                       bottom: CGFloat, maximumHeight: CGFloat) {
        label.frame = NSRect(x: bounds.midX - line.width / 2, y: bottom,
                             width: line.width, height: line.height)
        label.font = line.fit.font
        label.stringValue = line.fit.text
        label.setAccessibilityLabel(line.original)

        chip.isHidden = line.original.isEmpty || style.chipOpacity <= 0
        if !chip.isHidden {
            // The optional backing hugs the visible text with a small padding.
            let chipHeight = min(maximumHeight, line.height + 8)
            chip.frame = NSRect(x: label.frame.minX,
                                y: bottom + (line.height - chipHeight) / 2,
                                width: line.width, height: chipHeight)
        }
    }

    private func fittedText(_ original: String, width: CGFloat, for label: NSTextField,
                            preferredSize: CGFloat, minimumSize: CGFloat,
                            weight: NSFont.Weight) -> FittedLyric {
        let isMain = label === mainLabel
        var cache = isMain ? mainFits : detailFits
        if cache.first?.original != original || cache.first?.size != preferredSize {
            cache.removeAll()
        }
        if let existing = cache.first(where: { $0.width == width }) { return existing.fit }
        let fit = FittedLyric(original, width: width,
                              preferredSize: preferredSize, minimumSize: minimumSize, weight: weight)
        cache.append(FitCache(original: original, width: width, size: preferredSize, fit: fit))
        if cache.count > 2 { cache.removeFirst() }
        if isMain { mainFits = cache } else { detailFits = cache }
        return fit
    }

    func show(primary: String, secondary: String) {
        primaryText = primary
        secondaryText = secondary
        needsLayout = true
        updateBandHeight()
    }
}

/// Vertical rhythm of the lyric band: the two visible lines stay one close pair
/// while the band hugs them with equal spacing above and below.
enum LyricStack {
    static let gap: CGFloat = 12
    /// Shrink floors the automatic fitter uses when the user asks for more.
    static let mainMinimumFontSize: CGFloat = 16
    static let detailMinimumFontSize: CGFloat = 12

    /// A selected size below the historical floor wins: never shrink below it.
    static func minimumFontSize(preferred: CGFloat, floor: CGFloat) -> CGFloat {
        min(max(1, floor), max(1, preferred))
    }

    static func lineHeight(at size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        let font = NSFont.systemFont(ofSize: max(1, size), weight: weight)
        return ceil(font.ascender - font.descender + font.leading)
    }

    /// The tallest visible text area: two rows at the selected font size.
    static func maximumLineHeight(preferredSize: CGFloat, weight: NSFont.Weight) -> CGFloat {
        2 * lineHeight(at: preferredSize, weight: weight) + 4
    }
}

/// The lyric band's height: the visible text plus equal spacing above and below.
enum LyricBand {
    static func height(primaryHeight: CGFloat, detailHeight: CGFloat, spacing: CGFloat) -> CGFloat {
        let text = detailHeight > 0
            ? primaryHeight + detailHeight + LyricStack.gap
            : primaryHeight
        return text + 2 * max(0, spacing)
    }
}

/// A fitted lyric line before it is positioned inside the band.
private struct MeasuredLine {
    let original: String
    let fit: FittedLyric
    let width: CGFloat
    let height: CGFloat
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
