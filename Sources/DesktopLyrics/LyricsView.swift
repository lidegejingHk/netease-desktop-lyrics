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
    private let sweep = LyricSweepLayer(frame: .zero)
    private var style = OverlayStyle.defaultValue
    private var primaryText = "正在等待网易云音乐…"
    private var secondaryText = ""
    private struct FitCache {
        let original: String
        let width: CGFloat
        let size: CGFloat
        let family: String
        let fit: FittedLyric
    }
    private var mainFits: [FitCache] = []
    private var detailFits: [FitCache] = []
    private var primaryFit: FittedLyric?
    /// Recent verified rows in track time: the presentation clock trails the
    /// engine by the user's delay, so it always has an earlier row to draw.
    private var events: [LyricRow] = []
    private var sweepTimer: Timer?

    /// At most this many rows are kept; twelve covers every delay the slider
    /// offers at the engine's 300 ms cadence.
    static let eventBufferLimit = 12
    /// A jump this large between rows is a seek or a new track: the buffer
    /// restarts so a stale row can never be drawn after it.
    static let seekJumpMs: UInt64 = 2_000

    /// Test hooks: where the sung/unsung boundary sits and whether it advances.
    var sweepCaretOffset: CGFloat? { sweep.caretOffset }
    var isSweepActive: Bool { sweep.isSweeping }
    var displayedTextForTesting: String { primaryText }
    func advanceSweepForTesting() { tickSweep() }
    func setSweepProgressForTesting(_ value: CGFloat) {
        sweep.setProgress(value, sweeping: true)
    }

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
        // Above both labels: the only part of the current line that is fully sung.
        addSubview(sweep, positioned: .above, relativeTo: detailLabel)
        mainLabel.font = OverlayStyle.primaryFont(ofSize: 24, weight: .semibold)
        detailLabel.font = OverlayStyle.secondaryFont(ofSize: 15, weight: .regular)
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
        // The unsung current line stays a quiet base; the sweep layer paints the
        // sung characters in full ink on top of it.
        mainLabel.textColor = text.withAlphaComponent(events.isEmpty ? 1 : 0.38)
        detailLabel.textColor = text.withAlphaComponent(0.70)
        sweep.applyStyle(style)
        // A delay change takes effect on the next frame, without waiting for
        // the next engine event.
        renderPresentation(now: Date().timeIntervalSinceReferenceDate)
        let chipColor = chip.withAlphaComponent(newStyle.chipOpacity).cgColor
        mainChip.layer?.backgroundColor = chipColor
        detailChip.layer?.backgroundColor = chipColor
        needsLayout = true
        updateBandHeight()
    }

    override func layout() {
        super.layout()
        sweep.needsDisplay = true
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
                  preferredSize: CGFloat(style.detailFontSize), weight: .regular))
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
        primaryFit = primary.fit
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
                               weight: .semibold, fontFamily: OverlayStyle.serifFamily)
        guard !secondaryText.isEmpty else { return (primary, nil) }
        let detail = measured(secondaryText, in: detailLabel, width: bandWidth,
                              preferredSize: CGFloat(style.detailFontSize),
                              minimumSize: LyricStack.minimumFontSize(
                                  preferred: CGFloat(style.detailFontSize),
                                  floor: LyricStack.detailMinimumFontSize),
                              weight: .regular, fontFamily: "sans")
        return (primary, detail)
    }

    private func measured(_ original: String, in label: NSTextField, width: CGFloat,
                          preferredSize: CGFloat, minimumSize: CGFloat,
                          weight: NSFont.Weight, fontFamily: String) -> MeasuredLine {
        let fit = fittedText(original, width: max(1, width - 24), for: label,
                             preferredSize: preferredSize, minimumSize: minimumSize,
                             weight: weight, fontFamily: fontFamily)
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
        if label === mainLabel {
            // The sweep reads the same fitted row and can draw across the full
            // band; the label still decides the row's height and vertical seat.
            sweep.refresh(fit: line.fit, primary: true)
            sweep.frame = NSRect(x: 0, y: label.frame.minY,
                                 width: bounds.width, height: label.frame.height)
        }

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
                            weight: NSFont.Weight, fontFamily: String) -> FittedLyric {
        let isMain = label === mainLabel
        var cache = isMain ? mainFits : detailFits
        if cache.first?.original != original || cache.first?.size != preferredSize ||
            cache.first?.family != fontFamily {
            cache.removeAll()
        }
        if let existing = cache.first(where: { $0.width == width }) { return existing.fit }
        let fit = FittedLyric(original, width: width, preferredSize: preferredSize,
                              minimumSize: minimumSize, weight: weight, family: fontFamily)
        cache.append(FitCache(original: original, width: width, size: preferredSize,
                              family: fontFamily, fit: fit))
        if cache.count > 2 { cache.removeFirst() }
        if isMain { mainFits = cache } else { detailFits = cache }
        return fit
    }

    func show(primary: String, secondary: String) {
        events.removeAll()
        syncSweepTimer()
        primaryText = primary
        secondaryText = secondary
        mainLabel.textColor = inkColor(1)
        sweep.setProgress(0, sweeping: false)
        sweep.setDimmed(false)
        needsLayout = true
        updateBandHeight()
    }

    /// A verified lyric row: the current line, the next line (or translation),
    /// and the row's own timing. The row is buffered in track time and drawn by
    /// the presentation clock, `lyricDelayMs` behind the reported position.
    func showLine(primary: String, secondary: String,
                  line: LineTiming?, playing: Bool, now: TimeInterval) {
        guard let line else {
            show(primary: primary, secondary: secondary)
            return
        }
        let event = LyricRow(text: primary, secondary: secondary,
                               lineStartMs: line.lineStart_ms, nextStartMs: line.nextStart_ms,
                               positionMs: line.position_ms, playing: playing, receivedAt: now)
        if let last = events.last {
            let jump = event.positionMs > last.positionMs
                ? event.positionMs - last.positionMs
                : last.positionMs - event.positionMs
            if jump > Self.seekJumpMs { events.removeAll() }
        }
        events.append(event)
        if events.count > Self.eventBufferLimit { events.removeFirst() }
        // A timed row draws a dim base for the sweep to light up.
        mainLabel.textColor = inkColor(0.38)
        sweep.setDimmed(true)
        syncSweepTimer()
        renderPresentation(now: now)
    }

    private func inkColor(_ alpha: CGFloat) -> NSColor {
        (OverlayStyle.nsColor(style.textRGB) ?? .white).withAlphaComponent(alpha)
    }

    // MARK: - Current-line sweep

    /// Runs only while a verified row is still being sung: pausing or losing the
    /// timing data stops the timer instead of guessing a position.
    private func syncSweepTimer() {
        let shouldRun = events.last?.playing == true
        if shouldRun, sweepTimer == nil {
            let timer = Timer(timeInterval: LyricSweepLayer.tickInterval, repeats: true) { [weak self] _ in
                self?.tickSweep()
            }
            sweepTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else if !shouldRun {
            sweepTimer?.invalidate()
            sweepTimer = nil
        }
    }

    /// Between engine events the host advances the presentation clock itself, so
    /// the row and its sweep move smoothly instead of every 300 ms.
    private func tickSweep() {
        renderPresentation(now: Date().timeIntervalSinceReferenceDate)
    }

    /// Draws the row and the sweep for the delayed presentation clock. The row
    /// shown is the newest verified row at or before `clock`, so a row can only
    /// change once the sung line has had its full time plus the delay.
    private func renderPresentation(now: TimeInterval) {
        guard let estimated = LyricPresentation.estimatedPosition(events, now: now),
              let index = LyricPresentation.selectedIndex(events, target: estimated - style.lyricDelayMs) else {
            return
        }
        let target = max(0, estimated - style.lyricDelayMs)
        let event = events[index]
        if event.text != primaryText || event.secondary != secondaryText {
            primaryText = event.text
            secondaryText = event.secondary
            needsLayout = true
            updateBandHeight()
            sweep.refresh(fit: primaryFit, primary: true)
        }
        // The row may trail the player, but whether the sweep animates follows
        // the player's own state: pausing freezes the delayed row at once.
        let playing = events.last?.playing == true
        if let progress = LyricPresentation.progress(event, target: target) {
            sweep.setProgress(progress, sweeping: playing)
        } else {
            // The last row has no following timestamp: show it as fully sung.
            sweep.setProgress(1, sweeping: false)
        }
    }
}

/// One verified lyric row in track time, kept with the moment it arrived so the
/// presentation clock can keep running between engine events.
struct LyricRow: Equatable {
    let text: String
    let secondary: String
    let lineStartMs: UInt64
    let nextStartMs: UInt64?
    let positionMs: UInt64
    let playing: Bool
    let receivedAt: TimeInterval
}

/// Presentation timing for the lyric rows. The engine's estimate keeps advancing
/// between events; the display deliberately trails it by the selected delay so a
/// row never changes before the sung line has actually finished.
enum LyricPresentation {
    /// How far the song has played by wall clock since the newest row arrived.
    static func estimatedPosition(_ events: [LyricRow], now: TimeInterval) -> Double? {
        guard let latest = events.last else { return nil }
        let elapsed = latest.playing ? max(0, now - latest.receivedAt) : 0
        return Double(latest.positionMs) + elapsed * 1_000
    }

    /// The row to draw for a presentation position: the newest row at or before
    /// it. Rows still ahead of the clock are never drawn, so nothing is shown
    /// early; a clock before the oldest row keeps that oldest row.
    static func selectedIndex(_ events: [LyricRow], target: Double) -> Int? {
        guard !events.isEmpty else { return nil }
        return events.lastIndex { Double($0.positionMs) <= target } ?? 0
    }

    /// The sweep's 0...1 progress inside a row; nil when the row has no end.
    static func progress(_ event: LyricRow, target: Double) -> CGFloat? {
        guard let next = event.nextStartMs, next > event.lineStartMs else { return nil }
        let raw = (target - Double(event.lineStartMs)) / Double(next - event.lineStartMs)
        return CGFloat(min(1, max(0, raw)))
    }
}

/// The verified timing of the current lyric row, straight from the engine.
struct LineTiming: Equatable {
    let lineStart_ms: UInt64
    let nextStart_ms: UInt64?
    let position_ms: UInt64
}

/// The lyric band's drawn state: which fitted text sits on the current row and
/// how far the sweep has reached into it.
private final class LyricSweepState {
    var fit: FittedLyric?
    var primary = true
    var progress: CGFloat = 0
    var drawnFirstLineWidth: CGFloat = 0
}

/// Paints only the already-sung characters of the current line, at full ink,
/// directly above the dimmed base label.
private final class LyricSweepLayer: NSView {
    static let tickInterval: TimeInterval = 1.0 / 30.0

    var reduceMotionProvider: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private let state = LyricSweepState()
    private var baseInk = NSColor.black
    private var ink = NSColor.black
    private var visible = false
    private(set) var isSweeping = false

    /// How far the boundary has travelled into the row, for tests: 0 at the
    /// head of the line, growing towards the measured row width.
    var caretOffset: CGFloat? {
        guard visible, let fit = state.fit, state.primary,
              let line = (fit.text as NSString).components(separatedBy: "\n").first else { return nil }
        return LyricSweepLayer.prefixWidth(of: line, progress: state.progress, font: fit.font)
    }

    /// One draw pass for the whole sung row: the text is placed at the measured
    /// row width (exactly where the base label sits) and clipped to the sung
    /// prefix, so the base and the sweep can never drift apart.
    override func draw(_ dirtyRect: NSRect) {
        guard visible, let fit = state.fit, state.primary,
              let line = (fit.text as NSString).components(separatedBy: "\n").first else { return }
        let lineWidth = state.drawnFirstLineWidth
        guard lineWidth > 0 else { return }
        let originX = bounds.midX - lineWidth / 2
        let available = min(bounds.height, fit.font.ascender - fit.font.descender + 6)
        let rect = NSRect(x: originX, y: (bounds.height - available) / 2,
                          width: lineWidth, height: available)
        let prefix = LyricSweepLayer.prefixWidth(of: line, progress: state.progress, font: fit.font)
        guard prefix > 0 else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: fit.font,
            .foregroundColor: ink.withAlphaComponent(0.96),
            .paragraphStyle: LyricSweepLayer.paragraphStyle,
        ]
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: rect.minX, y: 0, width: prefix, height: bounds.height)).addClip()
        (line as NSString).draw(in: rect, withAttributes: attributes)
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    /// The leading x of a row drawn with the same width rule the label uses.
    private func lineOrigin(_ fit: FittedLyric) -> CGFloat {
        bounds.midX - state.drawnFirstLineWidth / 2
    }

    func refresh(fit: FittedLyric?, primary: Bool) {
        state.fit = fit
        state.primary = primary
        state.drawnFirstLineWidth = fit?.drawnFirstLineWidth ?? 0
        needsDisplay = true
    }

    /// Static ink, or the quiet base the sweep paints on top of.
    func setDimmed(_ dimmed: Bool) {
        ink = baseInk.withAlphaComponent(dimmed ? 0.55 : 1)
        needsDisplay = true
    }

    /// `sweeping` means the boundary animates; a frozen row stays visible at the
    /// verified position, and the layer hides entirely when nothing has timing.
    func setProgress(_ value: CGFloat, sweeping: Bool) {
        state.progress = min(1, max(0, value))
        let animated = sweeping && !reduceMotionProvider()
        visible = value > 0 || animated
        needsDisplay = true
        isSweeping = animated
    }

    func applyStyle(_ style: OverlayStyle) {
        baseInk = OverlayStyle.nsColor(style.textRGB) ?? .black
        ink = baseInk
        needsDisplay = true
    }

    private static func prefixWidth(of line: String, progress: CGFloat, font: NSFont) -> CGFloat {
        let characters = Array(line)
        guard !characters.isEmpty else { return 0 }
        let count = min(characters.count, Int((progress * CGFloat(characters.count)).rounded()))
        let prefix = String(characters.prefix(count))
        return (prefix as NSString).size(withAttributes: [.font: font]).width
    }

    private static var paragraphStyle: NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byClipping
        return paragraph
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
    /// The drawn width of each visual row, so the sweep can centre on the first.
    let lineWidths: [CGFloat]
    /// The unwrapped width of the first row at the chosen size: the reference
    /// the sweep layer draws against, even when the row wraps or truncates.
    let drawnFirstLineWidth: CGFloat

    init(_ original: String, width: CGFloat, preferredSize: CGFloat,
         minimumSize: CGFloat, weight: NSFont.Weight, family: String) {
        let normalized = original.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let wasCapped = normalized.count > 512
        let characters = Array(normalized.prefix(512))
        drawnFirstLineWidth = FittedLyric.measure(String(characters),
                                                  font: FittedLyric.font(size: preferredSize, weight: weight, family: family))
        var size = preferredSize
        var chosenFont = FittedLyric.font(size: minimumSize, weight: weight, family: family)
        var chosenLines: [String] = []
        var consumed = 0
        while size >= minimumSize {
            let candidateFont = FittedLyric.font(size: size, weight: weight, family: family)
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
        lineWidths = chosenLines.map { Self.measure($0, font: chosenFont) }
        self.width = lineWidths.max() ?? 0
        lineCount = max(1, chosenLines.count)
    }

    /// The font stack the lyric band draws with: the serif display face for the
    /// current line, the system sans for everything else.
    static func font(size: CGFloat, weight: NSFont.Weight, family: String) -> NSFont {
        if family == OverlayStyle.serifFamily {
            return OverlayStyle.primaryFont(ofSize: size, weight: weight)
        }
        return OverlayStyle.secondaryFont(ofSize: size, weight: weight)
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
