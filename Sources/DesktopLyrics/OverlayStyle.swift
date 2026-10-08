import AppKit
import Foundation

struct OverlayStyle: Equatable {
    var backgroundRGB: String
    var textRGB: String
    var chipRGB: String
    var backgroundOpacity: Double
    var chipOpacity: Double
    /// Equal breathing room above and below the visible lyric pair, in points.
    var lyricSpacing: Double
    var mainFontSize: Double
    var detailFontSize: Double

    static let opacityRange: ClosedRange<Double> = 0...1
    static let spacingRange: ClosedRange<Double> = 0...40
    static let mainFontRange: ClosedRange<Double> = 14...40
    static let detailFontRange: ClosedRange<Double> = 11...28

    static let defaultValue = OverlayStyle(
        backgroundRGB: "#131313",
        textRGB: "#FFFFFF",
        chipRGB: "#000000",
        backgroundOpacity: 0.91,
        chipOpacity: 0,
        lyricSpacing: 8,
        mainFontSize: 24,
        detailFontSize: 15
    )

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
            backgroundOpacity: number("backgroundOpacity", range: OverlayStyle.opacityRange,
                                      fallback: fallback.backgroundOpacity),
            chipOpacity: number("chipOpacity", range: OverlayStyle.opacityRange,
                                fallback: fallback.chipOpacity),
            lyricSpacing: number("lyricSpacing", range: OverlayStyle.spacingRange,
                                 fallback: fallback.lyricSpacing),
            mainFontSize: number("mainFontSize", range: OverlayStyle.mainFontRange,
                                 fallback: fallback.mainFontSize),
            detailFontSize: number("detailFontSize", range: OverlayStyle.detailFontRange,
                                   fallback: fallback.detailFontSize)
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
    }

    private func color(_ name: String, fallback: String) -> String {
        Self.validColor(defaults.string(forKey: prefix + name) ?? fallback, fallback: fallback)
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
