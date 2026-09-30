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
check(near(above.x, 684) && near(above.y, 168), "Toolbar inside the lyric frame at its upper right")
let below = ToolbarPlacement.origin(
    overlay: NSRect(x: 700, y: 490, width: 760, height: 112),
    size: size,
    visibleFrames: [screen]
)
check(near(below.x, 826) && near(below.y, 556),
      "Toolbar stays inside the visible part of a lyric window at the screen edge")
let secondScreen = NSRect(x: 1000, y: -200, width: 1200, height: 700)
let moved = ToolbarPlacement.origin(
    overlay: NSRect(x: 1300, y: 100, width: 760, height: 112),
    size: size,
    visibleFrames: [screen, secondScreen]
)
check(near(moved.x, 1884) && near(moved.y, 168), "Toolbar anchors within the active display")
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

let noDisplay = ToolbarPlacement.origin(
    overlay: NSRect(x: 100, y: 100, width: 760, height: 112),
    size: size, visibleFrames: []
)
check(near(noDisplay.x, 684) && near(noDisplay.y, 168),
      "Display-less fallback remains inside the lyric frame")
let collapsedPoint = ToolbarPlacement.origin(
    overlay: NSRect(x: 100, y: 100, width: 760, height: 112),
    size: OverlayControls.collapsedSize, visibleFrames: [screen]
)
check(near(collapsedPoint.x + OverlayControls.collapsedSize.width, above.x + size.width),
      "Collapsed toolbar keeps the same right edge")
let thinSliver = NSRect(x: -700, y: 100, width: 760, height: 112)
let thinExpanded = ToolbarPlacement.origin(overlay: thinSliver, size: size, visibleFrames: [screen])
let thinCollapsed = ToolbarPlacement.origin(overlay: thinSliver,
                                             size: OverlayControls.collapsedSize,
                                             visibleFrames: [screen])
check(near(thinExpanded.x + size.width,
           thinCollapsed.x + OverlayControls.collapsedSize.width),
      "Collapsed controls preserve the same right edge even if lyrics have only a thin visible sliver")
check(thinCollapsed.x >= screen.minX &&
      thinCollapsed.x + OverlayControls.collapsedSize.width <= thinSliver.maxX,
      "Collapsed control remains inside the visible lyric sliver")
let thinCollapseButton = NSRect(x: thinExpanded.x + 124, y: thinExpanded.y + 3,
                                width: 34, height: 32)
check(thinCollapseButton.minX >= screen.minX && thinCollapseButton.maxX <= thinSliver.maxX,
      "Expanded toolbar keeps its collapse button accessible inside the lyric sliver")
let tinySliver = NSRect(x: -740, y: 100, width: 760, height: 112)
let tinyCollapsed = ToolbarPlacement.origin(overlay: tinySliver,
                                             size: OverlayControls.collapsedSize,
                                             visibleFrames: [screen])
check(tinyCollapsed.x + OverlayControls.collapsedSize.width <= tinySliver.maxX &&
      tinyCollapsed.x + 2 + 34 > screen.minX,
      "When less than a button fits, the visible part still stays inside the lyric sliver")
let edgeScreens = [screen, secondScreen]
let edgeOverlay = NSRect(x: 950, y: 100, width: 760, height: 112)
let edgeExpanded = ToolbarPlacement.origin(overlay: edgeOverlay, size: size,
                                            visibleFrames: edgeScreens)
let edgeCollapsed = ToolbarPlacement.origin(overlay: edgeOverlay,
                                             size: OverlayControls.collapsedSize,
                                             visibleFrames: edgeScreens)
check(near(edgeExpanded.x + size.width,
           edgeCollapsed.x + OverlayControls.collapsedSize.width),
      "Collapsed controls preserve the right edge when lyrics straddle displays")

let _ = NSApplication.shared
let controls = OverlayControls()
check(!controls.panel.hasShadow &&
      controls.controlPanels.allSatisfy { $0.level.rawValue > NSWindow.Level.floating.rawValue },
      "Individual transparent controls float above the lyrics without detached shadows")
check(controls.panel.ignoresMouseEvents && !controls.panel.isVisible,
      "Full-size toolbar layout frame cannot intercept mouse events")
check(controls.controlPanels.count == 5 &&
      controls.controlPanels.allSatisfy {
          !$0.hasShadow && !$0.isOpaque && !$0.hidesOnDeactivate &&
          $0.collectionBehavior.contains(.canJoinAllSpaces) && $0.animationBehavior == .none
      },
      "Only individual 34-point control windows can receive clicks")
let handle = controls.controlPanels[0].contentView!
check(handle.hitTest(NSPoint(x: 17, y: 16)) === handle,
      "Drag handle receives pointer input in its own small panel")
let styledToolbar = OverlayStyle(backgroundRGB: "#112233", textRGB: "#20CF80", chipRGB: "#000000",
                                 backgroundOpacity: 0.3, chipOpacity: 0.5)
controls.applyStyle(styledToolbar)
let handleGlyph = handle.subviews.first as! NSTextField
check(OverlayStyle.rgbHex(handleGlyph.textColor!) == "#20CF80",
      "Drag handle tint follows the lyric text color")
check(controls.controlPanels.compactMap { $0.contentView as? NSButton }
    .allSatisfy { OverlayStyle.rgbHex($0.contentTintColor!) == "#20CF80" },
      "All toolbar icons follow the lyric text color")
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
                                   modifierFlags: [], timestamp: 0, windowNumber: controls.controlPanels[0].windowNumber,
                                   context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
var dragDelta = NSPoint.zero
controls.onDrag = { dragDelta = $0 }
handle.mouseDown(with: mouseDown)
handle.mouseDragged(with: movementEvent(x: 30, y: 25, deltaX: 20, deltaY: -15))
check(near(dragDelta.x, 20) && near(dragDelta.y, 15), "Drag uses event delta with flipped Y")
check(!controls.controlPanels[0].ignoresMouseEvents,
      "Unlocked drag handle has a clickable window")
var tappedLock = 0
var tappedSettings = 0
var tappedCollapse = 0
controls.onToggleLock = { tappedLock += 1 }
controls.onToggleSettings = { tappedSettings += 1 }
controls.onToggleCollapsed = { tappedCollapse += 1 }
let toolbarButtons = controls.controlPanels.compactMap { $0.contentView as? NSButton }
toolbarButtons.first(where: { $0.accessibilityLabel() == "锁定歌词位置" })!.performClick(nil)
toolbarButtons.first(where: { $0.accessibilityLabel() == "设置歌词样式" })!.performClick(nil)
toolbarButtons.first(where: { $0.accessibilityLabel() == "收起工具条" })!.performClick(nil)
check(tappedLock == 1 && tappedSettings == 1 && tappedCollapse == 1,
      "Toolbar actions dispatch to their owning controller")
controls.setLocked(true)
check(controls.controlPanels[0].ignoresMouseEvents &&
      controls.controlPanels.dropFirst().allSatisfy { !$0.ignoresMouseEvents },
      "Locked drag handle passes clicks through; remaining buttons stay interactive")
check(handleGlyph.textColor!.alphaComponent < 0.5,
      "Locked drag handle dims while remaining visible")
dragDelta = .zero
handle.mouseDown(with: mouseDown)
handle.mouseDragged(with: movementEvent(x: 35, y: 22, deltaX: 25, deltaY: -12))
check(near(dragDelta.x, 0) && near(dragDelta.y, 0), "Locked drag handle never moves lyrics")
controls.setCollapsed(true)
check(near(controls.panel.frame.width, 38), "Collapsed toolbar width")
controls.follow(overlay: NSRect(x: 100, y: 100, width: 760, height: 112),
                visibleFrames: [screen])
check(near(controls.panel.frame.maxX, 850) && near(controls.panel.frame.maxY, 206),
      "Collapsed button stays at the inside upper-right edge")
toolbarButtons.first(where: { $0.accessibilityLabel() == "展开歌词工具条" })!.performClick(nil)
check(tappedCollapse == 2, "Collapsed toolbar exposes an expand action")
controls.setCollapsed(false)
check(near(controls.panel.frame.width, 166), "Restored toolbar width")
controls.follow(overlay: NSRect(x: 100, y: 100, width: 760, height: 112),
                visibleFrames: [screen])
check(near(controls.panel.frame.origin.x, 684) && near(controls.panel.frame.origin.y, 168),
      "Interactive toolbar follows the lyric panel on its inside")
controls.setVisible(true)
let activeWindows = controls.controlPanels.filter(\.isVisible)
check(activeWindows.count == 4 && activeWindows.allSatisfy { $0.frame.width == 34 },
      "Expanded toolbar exposes four small hit windows rather than one large one")
check(activeWindows.allSatisfy { !$0.ignoresMouseEvents || $0 === controls.controlPanels[0] },
      "Icon panels remain interactive")
let gap = NSPoint(x: controls.panel.frame.minX + 43, y: controls.panel.frame.minY + 20)
check(controls.panel.frame.contains(gap) &&
      !activeWindows.contains(where: { $0.frame.contains(gap) }),
      "Transparent space between icons contains no mouse-intercepting window")
controls.setCollapsed(true)
check(controls.controlPanels.filter(\.isVisible).count == 1 &&
      controls.controlPanels[4].isVisible,
      "Collapsed toolbar leaves only one small hit window")
check(near(controls.controlPanels[4].frame.maxX, controls.panel.frame.maxX - 2),
      "The collapsed hit window stays on the same right edge")
controls.setVisible(false)
check(controls.controlPanels.allSatisfy { !$0.isVisible },
      "Hiding lyrics also removes all toolbar hit targets")

// Exercise the window server's real mouse target selection, not just view hitTest.
// Window ordering and ignoresMouseEvents cross a process boundary, so wait for
// WindowServer's state rather than assuming the next instruction sees the change.
let liveScreen = NSScreen.main!.visibleFrame
let liveOverlay = NSRect(x: liveScreen.midX - 380, y: liveScreen.midY - 56,
                         width: 760, height: 112)
let lyricPanel = NSPanel(contentRect: liveOverlay, styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
lyricPanel.level = .floating
lyricPanel.orderFrontRegardless()
controls.follow(overlay: liveOverlay, visibleFrames: [liveScreen])
controls.setCollapsed(false)
controls.setLocked(false)
controls.setVisible(true)
let clickGap = NSPoint(x: controls.panel.frame.minX + 43,
                       y: controls.panel.frame.minY + 19)
func mouseTarget(_ point: NSPoint) -> Int {
    NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
}
func awaitMouseState(_ message: String, _ matches: () -> Bool) {
    let deadline = Date().addingTimeInterval(2)
    while Date() < deadline {
        if matches() { return }
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
    fatalError(message)
}
func expandedButtonsReceiveClicks() -> Bool {
    controls.controlPanels.prefix(4).allSatisfy { window in
        mouseTarget(NSPoint(x: window.frame.midX, y: window.frame.midY)) == window.windowNumber
    }
}
let dragCenter = NSPoint(x: controls.controlPanels[0].frame.midX,
                         y: controls.controlPanels[0].frame.midY)
let lockCenter = NSPoint(x: controls.controlPanels[1].frame.midX,
                         y: controls.controlPanels[1].frame.midY)
awaitMouseState("All four buttons receive clicks; the gap reaches unlocked lyrics") {
    expandedButtonsReceiveClicks() && mouseTarget(clickGap) == lyricPanel.windowNumber
}
controls.setVisible(false)
awaitMouseState("Hidden controls leave no mouse targets over the lyrics") {
    mouseTarget(dragCenter) == lyricPanel.windowNumber &&
    mouseTarget(lockCenter) == lyricPanel.windowNumber
}
controls.setVisible(true)
awaitMouseState("Buttons work immediately after showing the toolbar again") {
    expandedButtonsReceiveClicks() && mouseTarget(clickGap) == lyricPanel.windowNumber
}
controls.setCollapsed(true)
let expandPanel = controls.controlPanels[4]
let expandCenter = NSPoint(x: expandPanel.frame.midX, y: expandPanel.frame.midY)
awaitMouseState("Collapsed toolbar retains its clickable expand button") {
    mouseTarget(expandCenter) == expandPanel.windowNumber &&
    mouseTarget(dragCenter) == lyricPanel.windowNumber
}
controls.setCollapsed(false)
awaitMouseState("All controls can receive clicks after expanding again") {
    expandedButtonsReceiveClicks() && mouseTarget(clickGap) == lyricPanel.windowNumber
}
controls.setLocked(true)
lyricPanel.ignoresMouseEvents = true
awaitMouseState("Locked lyrics and drag handle pass clicks through, but lock stays clickable") {
    mouseTarget(lockCenter) == controls.controlPanels[1].windowNumber &&
    mouseTarget(dragCenter) != controls.controlPanels[0].windowNumber &&
    mouseTarget(dragCenter) != lyricPanel.windowNumber &&
    mouseTarget(clickGap) != lyricPanel.windowNumber
}
controls.setVisible(false)
lyricPanel.orderOut(nil)

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

let primaryLabel = lyricView.subviews[2] as! NSTextField
let primaryChip = lyricView.subviews[0]
let expandedInside = NSRect(x: 584, y: 68, width: 166, height: 38)
lyricView.setControlsFrame(expandedInside)
lyricView.show(primary: "合成歌词", secondary: "合成副句", fraction: 0, active: true)
lyricView.layout()
check(near(primaryLabel.frame.midX, lyricView.bounds.midX),
      "Ordinary lines stay centered under the inside controls")
check(near((lyricView.subviews[3] as! NSTextField).frame.midX, lyricView.bounds.midX),
      "Secondary line stays centered independently of the toolbar")

let mediumLine = String(repeating: "合成", count: 10)
lyricView.applyStyle(OverlayStyle(backgroundRGB: "#123456", textRGB: "#F0E0D0", chipRGB: "#112233",
                                  backgroundOpacity: 0.15, chipOpacity: 0.55))
lyricView.show(primary: mediumLine, secondary: "", fraction: 0, active: true)
lyricView.layout()
check(primaryLabel.frame.midX < lyricView.bounds.midX,
      "Only overlapping lyric lines move left of the expanded controls")
check(primaryChip.frame.maxX <= expandedInside.minX - 8,
      "Text background leaves an eight-point gap before the toolbar")
check(primaryLabel.frame.maxX <= expandedInside.minX - 8,
      "The text label itself cannot draw under the toolbar")

lyricView.show(primary: String(repeating: "很长的合成歌词", count: 12),
               secondary: "", fraction: 0, active: true)
lyricView.layout()
check(primaryChip.frame.maxX <= expandedInside.minX - 8 &&
      primaryChip.frame.width <= primaryLabel.frame.width,
      "Long truncated lines and their text backgrounds do not cover the toolbar")

lyricView.show(primary: mediumLine, secondary: "", fraction: 0, active: true)
lyricView.setControlsFrame(NSRect(x: 712, y: 68, width: 38, height: 38))
lyricView.layout()
check(near(primaryLabel.frame.midX, lyricView.bounds.midX),
      "After collapsing the toolbar, an ordinary line returns to the center")

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
