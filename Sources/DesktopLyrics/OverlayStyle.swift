import AppKit
import Foundation

struct OverlayStyle: Equatable {
    var backgroundRGB: String
    var textRGB: String
    var chipRGB: String
    /// The warm focal colour: whole-song progress plus the current-line sweep.
    var accentRGB: String
    var backgroundOpacity: Double
    var chipOpacity: Double
    /// Equal breathing room above and below the visible lyric pair, in points.
    var lyricSpacing: Double
    var mainFontSize: Double
    var detailFontSize: Double
    /// How far the lyric row and its sweep trail the reported position: the
    /// player's clock runs ahead of what is audible, and some lyric files mark
    /// a row's end before the sung line actually finishes. Only the presentation
    /// is delayed; the engine and the whole-song rail stay live.
    var lyricDelayMs: Double
    /// Optional elements: both default to on and are user-switchable.
    var showsTitle: Bool = true
    var showsWaveform: Bool = true

    static let opacityRange: ClosedRange<Double> = 0...1
    static let spacingRange: ClosedRange<Double> = 0...40
    static let mainFontRange: ClosedRange<Double> = 14...40
    static let detailFontRange: ClosedRange<Double> = 11...28
    static let delayRange: ClosedRange<Double> = 0...1_000

    /// The overlay's baseline look: warm paper, ink text and a cinnabar accent.
    /// "Restore Defaults" reports exactly this style.
    static let defaultValue = OverlayStyle(
        backgroundRGB: "#F6F3EC",
        textRGB: "#23262C",
        chipRGB: "#23262C",
        accentRGB: "#BF4A2E",
        backgroundOpacity: 0.97,
        chipOpacity: 0,
        lyricSpacing: 8,
        mainFontSize: 24,
        detailFontSize: 15,
        lyricDelayMs: 200
    )

    /// An explicit initializer keeps the memberwise call sites stable while the
    /// accent stays optional: omitting it selects the theme's own cinnabar.
    init(backgroundRGB: String, textRGB: String, chipRGB: String,
         accentRGB: String = "#BF4A2E", backgroundOpacity: Double, chipOpacity: Double,
         lyricSpacing: Double, mainFontSize: Double, detailFontSize: Double,
         lyricDelayMs: Double = 200, showsTitle: Bool = true, showsWaveform: Bool = true) {
        self.backgroundRGB = backgroundRGB
        self.textRGB = textRGB
        self.chipRGB = chipRGB
        self.accentRGB = accentRGB
        self.backgroundOpacity = backgroundOpacity
        self.chipOpacity = chipOpacity
        self.lyricSpacing = lyricSpacing
        self.mainFontSize = mainFontSize
        self.detailFontSize = detailFontSize
        self.lyricDelayMs = lyricDelayMs
        self.showsTitle = showsTitle
        self.showsWaveform = showsWaveform
    }

    /// One serif stack drives the current lyric line across languages: the macOS
    /// Chinese Song faces first, then a serif fallback for a missing system.
    static let serifFamily = "Songti SC"
    static var primaryFont: NSFont {
        NSFont(name: serifFamily, size: 24)
            ?? NSFont(name: "STSong", size: 24)
            ?? NSFont.systemFont(ofSize: 24)
    }

    static func primaryFont(ofSize size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont(name: serifFamily, size: size)
            ?? NSFont(name: "STSong", size: size)
            ?? NSFont.systemFont(ofSize: size, weight: weight)
        let traits: NSFontTraitMask = weight >= .semibold ? .boldFontMask : []
        return NSFontManager.shared.convert(base, toHaveTrait: traits)
    }

    /// The secondary line stays a quiet sans, whatever the display face does.
    static func secondaryFont(ofSize size: CGFloat, weight: NSFont.Weight) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }

    static func nsColor(_ rgb: String) -> NSColor? {
        guard rgb.utf8.count == 7, rgb.utf8.first == 35,
              rgb.utf8.dropFirst().allSatisfy({
                  (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
              }) else { return nil }
        guard let value = Int(rgb.dropFirst(), radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                       green: CGFloat((value >> 8) & 255) / 255,
                       blue: CGFloat(value & 255) / 255, alpha: 1)
    }

    static func rgbHex(_ color: NSColor) -> String {
        guard let converted = color.usingColorSpace(.sRGB) else { return defaultValue.textRGB }
        func byte(_ value: CGFloat) -> Int {
            Int((min(1, max(0, value)) * 255).rounded())
        }
        return String(format: "#%02X%02X%02X", byte(converted.redComponent),
                      byte(converted.greenComponent), byte(converted.blueComponent))
    }
}

struct OverlayStyleStore {
    let defaults: UserDefaults
    private let prefix = "overlayStyle."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> OverlayStyle {
        let fallback = OverlayStyle.defaultValue
        return OverlayStyle(
            backgroundRGB: color("backgroundRGB", fallback: fallback.backgroundRGB),
            textRGB: color("textRGB", fallback: fallback.textRGB),
            chipRGB: color("chipRGB", fallback: fallback.chipRGB),
            accentRGB: color("accentRGB", fallback: fallback.accentRGB),
            backgroundOpacity: number("backgroundOpacity", range: OverlayStyle.opacityRange,
                                      fallback: fallback.backgroundOpacity),
            chipOpacity: number("chipOpacity", range: OverlayStyle.opacityRange,
                                fallback: fallback.chipOpacity),
            lyricSpacing: number("lyricSpacing", range: OverlayStyle.spacingRange,
                                 fallback: fallback.lyricSpacing),
            mainFontSize: number("mainFontSize", range: OverlayStyle.mainFontRange,
                                 fallback: fallback.mainFontSize),
            detailFontSize: number("detailFontSize", range: OverlayStyle.detailFontRange,
                                   fallback: fallback.detailFontSize),
            lyricDelayMs: number("lyricDelayMs", range: OverlayStyle.delayRange,
                                 fallback: fallback.lyricDelayMs),
            showsTitle: boolean("showsTitle", fallback: fallback.showsTitle),
            showsWaveform: boolean("showsWaveform", fallback: fallback.showsWaveform)
        )
    }

    func save(_ style: OverlayStyle) {
        let fallback = OverlayStyle.defaultValue
        defaults.set(Self.validColor(style.backgroundRGB, fallback: fallback.backgroundRGB),
                     forKey: prefix + "backgroundRGB")
        defaults.set(Self.validColor(style.textRGB, fallback: fallback.textRGB),
                     forKey: prefix + "textRGB")
        defaults.set(Self.validColor(style.chipRGB, fallback: fallback.chipRGB),
                     forKey: prefix + "chipRGB")
        defaults.set(Self.validColor(style.accentRGB, fallback: fallback.accentRGB),
                     forKey: prefix + "accentRGB")
        defaults.set(Self.validNumber(style.backgroundOpacity, range: OverlayStyle.opacityRange,
                                      fallback: fallback.backgroundOpacity),
                     forKey: prefix + "backgroundOpacity")
        defaults.set(Self.validNumber(style.chipOpacity, range: OverlayStyle.opacityRange,
                                      fallback: fallback.chipOpacity),
                     forKey: prefix + "chipOpacity")
        defaults.set(Self.validNumber(style.lyricSpacing, range: OverlayStyle.spacingRange,
                                      fallback: fallback.lyricSpacing),
                     forKey: prefix + "lyricSpacing")
        defaults.set(Self.validNumber(style.mainFontSize, range: OverlayStyle.mainFontRange,
                                      fallback: fallback.mainFontSize),
                     forKey: prefix + "mainFontSize")
        defaults.set(Self.validNumber(style.detailFontSize, range: OverlayStyle.detailFontRange,
                                      fallback: fallback.detailFontSize),
                     forKey: prefix + "detailFontSize")
        defaults.set(Self.validNumber(style.lyricDelayMs, range: OverlayStyle.delayRange,
                                      fallback: fallback.lyricDelayMs),
                     forKey: prefix + "lyricDelayMs")
        defaults.set(style.showsTitle, forKey: prefix + "showsTitle")
        defaults.set(style.showsWaveform, forKey: prefix + "showsWaveform")
    }

    private func color(_ name: String, fallback: String) -> String {
        Self.validColor(defaults.string(forKey: prefix + name) ?? fallback, fallback: fallback)
    }

    /// Only a real boolean is accepted; a number or string stored under the same
    /// key falls back to the default instead of being read as a truthy value.
    private func boolean(_ name: String, fallback: Bool) -> Bool {
        guard let value = defaults.object(forKey: prefix + name) as? NSNumber,
              CFGetTypeID(value) == CFBooleanGetTypeID() else { return fallback }
        return value.boolValue
    }

    private func number(_ name: String, range: ClosedRange<Double>, fallback: Double) -> Double {
        guard let value = defaults.object(forKey: prefix + name) as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID() else { return fallback }
        return Self.validNumber(value.doubleValue, range: range, fallback: fallback)
    }

    private static func validColor(_ value: String, fallback: String) -> String {
        OverlayStyle.nsColor(value) == nil ? fallback : value.uppercased()
    }

    private static func validNumber(_ value: Double, range: ClosedRange<Double>,
                                    fallback: Double) -> Double {
        value.isFinite && range.contains(value) ? value : fallback
    }
}
