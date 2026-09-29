import AppKit
import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

func near(_ actual: CGFloat, _ expected: CGFloat) -> Bool {
    abs(actual - expected) < 0.001
}

let suite = "desktop-lyrics-appearance-tests-\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let store = OverlayStyleStore(defaults: defaults)
let baseline = store.load()
check(baseline.backgroundRGB == "#131313", "Default background")
check(baseline.backgroundOpacity == 0.91, "Default background opacity")
check(baseline.textRGB == "#FFFFFF", "Default text")
check(baseline.chipRGB == "#000000", "Default text chip")
check(baseline.chipOpacity == 0, "Default text chip is transparent")

var edited = baseline
edited.backgroundRGB = "#12ab34"
edited.backgroundOpacity = 0.25
edited.textRGB = "#F0E0D0"
edited.chipRGB = "#345678"
edited.chipOpacity = 0.6
store.save(edited)
let restored = store.load()
check(restored.backgroundRGB == "#12AB34", "Normalized hex roundtrip")
check(restored.backgroundOpacity == 0.25, "Background opacity roundtrip")
check(restored.textRGB == "#F0E0D0", "Text color roundtrip")
check(restored.chipRGB == "#345678", "Chip color roundtrip")
check(restored.chipOpacity == 0.6, "Chip opacity roundtrip")

check(OverlayStyle.rgbHex(NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 0.2)) == "#FF8000", "NSColor to RGB")
check(OverlayStyle.nsColor("#ABCDEF") != nil, "Valid RGB")
check(OverlayStyle.nsColor("#１２ABCD") == nil, "Reject non-ASCII digits")
check(OverlayStyle.nsColor("#12345") == nil, "Reject truncated hex")
check(OverlayStyle.nsColor("red") == nil, "Reject names")

defaults.set("#GG0000", forKey: "overlayStyle.backgroundRGB")
defaults.set("not-a-color", forKey: "overlayStyle.textRGB")
defaults.set("#00000G", forKey: "overlayStyle.chipRGB")
defaults.set(Double.nan, forKey: "overlayStyle.backgroundOpacity")
defaults.set(1.1, forKey: "overlayStyle.chipOpacity")
let invalid = store.load()
check(invalid.backgroundRGB == baseline.backgroundRGB, "Invalid background fallback")
check(invalid.textRGB == baseline.textRGB, "Invalid text fallback")
check(invalid.chipRGB == baseline.chipRGB, "Invalid chip fallback")
check(invalid.backgroundOpacity == baseline.backgroundOpacity, "NaN fallback")
check(invalid.chipOpacity == baseline.chipOpacity, "Out of range fallback")

defaults.set(-0.01, forKey: "overlayStyle.backgroundOpacity")
defaults.set(Double.infinity, forKey: "overlayStyle.chipOpacity")
check(store.load().backgroundOpacity == baseline.backgroundOpacity, "Negative fallback")
check(store.load().chipOpacity == baseline.chipOpacity, "Infinity fallback")

let screen = NSRect(x: 0, y: 0, width: 1000, height: 600)
let size = NSSize(width: 166, height: 38)
let above = ToolbarPlacement.origin(
    overlay: NSRect(x: 100, y: 100, width: 760, height: 112),
    size: size,
    visibleFrames: [screen]
)
check(near(above.x, 694) && near(above.y, 220), "Toolbar above right edge")
let below = ToolbarPlacement.origin(
    overlay: NSRect(x: 700, y: 490, width: 760, height: 112),
    size: size,
    visibleFrames: [screen]
)
check(near(below.x, 826) && near(below.y, 444), "Below on top edge and clamped to right")
let secondScreen = NSRect(x: 1000, y: -200, width: 1200, height: 700)
let moved = ToolbarPlacement.origin(
    overlay: NSRect(x: 1300, y: 100, width: 760, height: 112),
    size: size,
    visibleFrames: [screen, secondScreen]
)
check(near(moved.x, 1894) && near(moved.y, 220), "Follows active display")
let isolated = ToolbarPlacement.origin(
    overlay: NSRect(x: 2400, y: 200, width: 760, height: 112),
    size: size,
    visibleFrames: [screen, secondScreen]
)
check(isolated.x >= secondScreen.minX && isolated.x + size.width <= secondScreen.maxX,
      "Fallback position remains on a visible display")

print("Overlay appearance: all assertions passed")
