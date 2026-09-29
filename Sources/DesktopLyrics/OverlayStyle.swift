import AppKit
import Foundation

struct OverlayStyle: Equatable {
    var backgroundRGB: String
    var textRGB: String
    var chipRGB: String
    var backgroundOpacity: Double
    var chipOpacity: Double

    static let defaultValue = OverlayStyle(
        backgroundRGB: "#131313",
        textRGB: "#FFFFFF",
        chipRGB: "#000000",
        backgroundOpacity: 0.91,
        chipOpacity: 0
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
            backgroundOpacity: opacity("backgroundOpacity", fallback: fallback.backgroundOpacity),
            chipOpacity: opacity("chipOpacity", fallback: fallback.chipOpacity)
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
        defaults.set(Self.validOpacity(style.backgroundOpacity, fallback: fallback.backgroundOpacity),
                     forKey: prefix + "backgroundOpacity")
        defaults.set(Self.validOpacity(style.chipOpacity, fallback: fallback.chipOpacity),
                     forKey: prefix + "chipOpacity")
    }

    private func color(_ name: String, fallback: String) -> String {
        Self.validColor(defaults.string(forKey: prefix + name) ?? fallback, fallback: fallback)
    }

    private func opacity(_ name: String, fallback: Double) -> Double {
        guard let value = defaults.object(forKey: prefix + name) as? Double else { return fallback }
        return Self.validOpacity(value, fallback: fallback)
    }

    private static func validColor(_ value: String, fallback: String) -> String {
        OverlayStyle.nsColor(value) == nil ? fallback : value.uppercased()
    }

    private static func validOpacity(_ value: Double, fallback: Double) -> Double {
        value.isFinite && (0...1).contains(value) ? value : fallback
    }
}
