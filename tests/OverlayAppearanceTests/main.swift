import AppKit
import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

func near(_ actual: CGFloat, _ expected: CGFloat) -> Bool {
    abs(actual - expected) < 0.001
}

let appMode = DesktopLaunchMode(arguments: ["NeteaseDesktopLyrics"])
check(appMode.accessibilityPermissionStatus.contains("网易云桌面歌词"),
      "Independent app permission notice names the App")
check(!appMode.accessibilityPermissionStatus.contains("终端"),
      "Independent app permission notice does not ask for Terminal access")
let stdinMode = DesktopLaunchMode(arguments: ["NeteaseDesktopLyrics", "--stdin"])
check(stdinMode.accessibilityPermissionStatus.contains("终端"),
      "Stdin mode permission notice names the terminal")
check(!stdinMode.accessibilityPermissionStatus.contains("网易云桌面歌词"),
      "Stdin mode does not ask for the independent App permission")

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
let restored = OverlayStyleStore(defaults: defaults).load()
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
defaults.set(true, forKey: "overlayStyle.backgroundOpacity")
check(store.load().backgroundOpacity == baseline.backgroundOpacity, "Boolean opacity fallback")

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
let safelyKept = OverlayVisibility.origin(
    for: NSRect(x: 1200, y: 100, width: 760, height: 112), visibleFrames: [screen, secondScreen]
)
check(near(safelyKept.x, 1200) && near(safelyKept.y, 100), "Keep visible lyric window")
let rescued = OverlayVisibility.origin(
    for: NSRect(x: 1300, y: 1200, width: 760, height: 112), visibleFrames: [screen]
)
check(near(rescued.x, 240) && near(rescued.y, 488), "Recover lyric window from disconnected display")
let mostlyStranded = OverlayVisibility.origin(
    for: NSRect(x: 960, y: 300, width: 760, height: 112), visibleFrames: [screen]
)
check(near(mostlyStranded.x, 240) && near(mostlyStranded.y, 300),
      "Recover lyric window even when a narrow sliver remains")

let isolated = ToolbarPlacement.origin(
    overlay: NSRect(x: 2400, y: 200, width: 760, height: 112),
    size: size,
    visibleFrames: [screen, secondScreen]
)
check(isolated.x >= secondScreen.minX && isolated.x + size.width <= secondScreen.maxX,
      "Fallback position remains on a visible display")

let _ = NSApplication.shared
let controls = OverlayControls()
let handle = controls.panel.contentView!.subviews.first!
check(handle.isAccessibilityElement() && handle.accessibilityRole() == .button,
      "Drag handle is exposed as an accessible control")
func movementEvent(x: CGFloat, y: CGFloat, deltaX: Int64, deltaY: Int64) -> NSEvent {
    let cgEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged,
                          mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)!
    cgEvent.setIntegerValueField(.mouseEventDeltaX, value: deltaX)
    cgEvent.setIntegerValueField(.mouseEventDeltaY, value: deltaY)
    return NSEvent(cgEvent: cgEvent)!
}
let mouseDown = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 10, y: 10),
                                   modifierFlags: [], timestamp: 0, windowNumber: controls.panel.windowNumber,
                                   context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
var dragDelta = NSPoint.zero
controls.onDrag = { dragDelta = $0 }
handle.mouseDown(with: mouseDown)
handle.mouseDragged(with: movementEvent(x: 30, y: 25, deltaX: 20, deltaY: -15))
check(near(dragDelta.x, 20) && near(dragDelta.y, 15), "Drag uses event delta with flipped Y")
check(!controls.panel.ignoresMouseEvents, "Toolbar is interactive by default")
var tappedLock = 0
var tappedSettings = 0
var tappedCollapse = 0
controls.onToggleLock = { tappedLock += 1 }
controls.onToggleSettings = { tappedSettings += 1 }
controls.onToggleCollapsed = { tappedCollapse += 1 }
let toolbarButtons = controls.panel.contentView!.subviews.compactMap { $0 as? NSButton }
toolbarButtons.first(where: { $0.accessibilityLabel() == "锁定歌词位置" })!.performClick(nil)
toolbarButtons.first(where: { $0.accessibilityLabel() == "设置歌词样式" })!.performClick(nil)
toolbarButtons.first(where: { $0.accessibilityLabel() == "收起工具条" })!.performClick(nil)
check(tappedLock == 1 && tappedSettings == 1 && tappedCollapse == 1,
      "Toolbar actions dispatch to their owning controller")
controls.setLocked(true)
check(!controls.panel.ignoresMouseEvents, "Toolbar stays interactive while lyrics lock")
dragDelta = .zero
handle.mouseDown(with: mouseDown)
handle.mouseDragged(with: movementEvent(x: 35, y: 22, deltaX: 25, deltaY: -12))
check(near(dragDelta.x, 0) && near(dragDelta.y, 0), "Locked drag handle never moves lyrics")
controls.setCollapsed(true)
check(near(controls.panel.frame.width, 38), "Collapsed toolbar width")
toolbarButtons.first(where: { $0.accessibilityLabel() == "展开歌词工具条" })!.performClick(nil)
check(tappedCollapse == 2, "Collapsed toolbar exposes an expand action")
controls.setCollapsed(false)
check(near(controls.panel.frame.width, 166), "Restored toolbar width")
controls.follow(overlay: NSRect(x: 100, y: 100, width: 760, height: 112),
                visibleFrames: [screen])
check(near(controls.panel.frame.origin.x, 694) && near(controls.panel.frame.origin.y, 220),
      "Interactive toolbar follows the lyric panel")

controls.setLocked(false)
var overlayForDrag = NSRect(x: 100, y: 100, width: 760, height: 112)
controls.onDrag = { delta in
    overlayForDrag.origin.x += delta.x
    overlayForDrag.origin.y += delta.y
    controls.follow(overlay: overlayForDrag, visibleFrames: [screen])
}
// Construct both events before the first callback moves the toolbar: queued events must not double-count it.
let queuedA = movementEvent(x: 140, y: 290, deltaX: 20, deltaY: -15)
let queuedB = movementEvent(x: 155, y: 300, deltaX: 15, deltaY: 10)
handle.mouseDown(with: mouseDown)
handle.mouseDragged(with: queuedA)
handle.mouseDragged(with: queuedB)
check(near(overlayForDrag.minX, 135) && near(overlayForDrag.minY, 105),
      "Queued drag events move by their independent deltas, not moving-window coordinates")

let lyricView = LyricsView(frame: NSRect(x: 0, y: 0, width: 760, height: 112))
lyricView.applyStyle(OverlayStyle(backgroundRGB: "#123456", textRGB: "#F0E0D0", chipRGB: "#112233",
                                  backgroundOpacity: 0.15, chipOpacity: 0.55))
lyricView.show(primary: "合成歌词", secondary: "合成副句", fraction: 0.5, active: true)
lyricView.layout()
check(near(lyricView.layer!.backgroundColor!.alpha, 0.15), "Live background alpha")
check(!lyricView.subviews[0].isHidden && !lyricView.subviews[1].isHidden,
      "Text-sized chip views appear for both lines")
check(near(lyricView.subviews[0].layer!.backgroundColor!.alpha, 0.55), "Live chip alpha")
lyricView.applyStyle(.defaultValue)
lyricView.layout()
check(lyricView.subviews[0].isHidden && lyricView.subviews[1].isHidden,
      "Default text background is fully transparent")

let settings = StyleSettingsPanel(style: .defaultValue)
let wells = settings.panel.contentView!.subviews.compactMap { $0 as? NSColorWell }
let sliders = settings.panel.contentView!.subviews.compactMap { $0 as? NSSlider }
check(wells.count == 3 && sliders.count == 2, "Color and opacity controls are present")
check(sliders.contains(where: { $0.accessibilityLabel() == "浮层背景不透明度" }),
      "Opacity labels describe the actual slider semantics")
var sentStyle: OverlayStyle?
settings.onStyleChange = { sentStyle = $0 }
func deliverChange(_ control: NSControl) {
    check(NSApp.sendAction(control.action!, to: control.target, from: control),
          "Native appearance control delivers its action")
}
let backgroundWell = wells.first(where: { $0.accessibilityLabel() == "浮层背景颜色" })!
backgroundWell.color = NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
deliverChange(backgroundWell)
check(sentStyle?.backgroundRGB == "#00FF00", "Color well sends live background color")
let textWell = wells.first(where: { $0.accessibilityLabel() == "歌词文字颜色" })!
textWell.color = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
deliverChange(textWell)
check(sentStyle?.textRGB == "#FF0000", "Color well sends live lyric text color")
let chipWell = wells.first(where: { $0.accessibilityLabel() == "文字背底颜色" })!
chipWell.color = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
deliverChange(chipWell)
check(sentStyle?.chipRGB == "#0000FF", "Color well sends live text backing color")
let backgroundOpacitySlider = sliders.first(where: { $0.accessibilityLabel() == "浮层背景不透明度" })!
backgroundOpacitySlider.doubleValue = 25
deliverChange(backgroundOpacitySlider)
check(sentStyle?.backgroundOpacity == 0.25, "Background opacity sends live update")
let chipOpacitySlider = sliders.first(where: { $0.accessibilityLabel() == "文字背底不透明度" })!
chipOpacitySlider.doubleValue = 60
deliverChange(chipOpacitySlider)
check(sentStyle?.chipOpacity == 0.6, "Text backing opacity sends live update")
settings.panel.contentView!.subviews.compactMap { $0 as? NSButton }
    .first(where: { $0.title == "恢复默认" })!.performClick(nil)
check(sentStyle == .defaultValue, "Reset restores all original colors and opacity")

print("Overlay appearance: all assertions passed")
