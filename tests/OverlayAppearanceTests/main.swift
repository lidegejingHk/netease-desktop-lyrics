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

let safeMenu: [PlaybackTransport.Item] = [
    .init(role: "AXMenuItem", title: "上一个", enabled: true),
    .init(role: "AXMenuItem", title: "播放", enabled: true),
    .init(role: "AXMenuItem", title: "下一个", enabled: true)
]
check(PlaybackTransport.uniqueIndex(for: .previous, in: safeMenu) == 0 &&
      PlaybackTransport.uniqueIndex(for: .next, in: safeMenu) == 2,
      "Only exact, enabled previous and next actions are selected")
let pausedMenu = PlaybackTransport.availability(safeMenu)
check(pausedMenu.previous && pausedMenu.toggle == .play && pausedMenu.next,
      "A single playable item exposes the play button")
let playingMenu = PlaybackTransport.availability([
    .init(role: "AXMenuItem", title: "暂停", enabled: true)
])
check(!playingMenu.previous && playingMenu.toggle == .pause && !playingMenu.next,
      "A single pause item exposes pause without guessing other actions")
let duplicates = safeMenu + [.init(role: "AXMenuItem", title: "上一首", enabled: true)]
check(PlaybackTransport.uniqueIndex(for: .previous, in: duplicates) == nil,
      "Two equivalent matches are ambiguous, never press either")
check(PlaybackTransport.uniqueIndex(for: .next, in: [
    .init(role: "AXButton", title: "下一个", enabled: true)]) == nil,
      "A matching title in a non-menu role cannot trigger playback")
check(PlaybackTransport.uniqueIndex(for: .play, in: [
    .init(role: "AXMenuItem", title: "播放", enabled: false)]) == nil,
      "Disabled items cannot trigger playback")
check(PlaybackTransport.availability([
    .init(role: "AXMenuItem", title: "播放", enabled: true),
    .init(role: "AXMenuItem", title: "暂停", enabled: true)
]).toggle == .unavailable, "Conflicting play/pause menu actions disable the toggle")
check(PlaybackTransport.availability([
    .init(role: "AXMenuItem", title: "播放歌曲", enabled: true)
]).toggle == .unavailable, "Partial menu titles never enable transport")

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

let twoRowOverlay = NSRect(x: 100, y: 100, width: 860, height: 176)
let twoRowOrigin = ToolbarPlacement.origin(overlay: twoRowOverlay,
                                           size: OverlayControls.expandedSize,
                                           visibleFrames: [NSRect(x: 0, y: 0, width: 1000, height: 600)])
check(near(OverlayControls.expandedSize.height, 80), "Two rows have a reserved 80-point height")
check(near(twoRowOrigin.x, 784) && near(twoRowOrigin.y, 148),
      "The controls move down and stay in the right rail")
let twoRowCollapsed = ToolbarPlacement.origin(overlay: twoRowOverlay,
                                              size: OverlayControls.collapsedSize,
                                              visibleFrames: [NSRect(x: 0, y: 0, width: 1000, height: 600)])
check(near(twoRowCollapsed.y, twoRowOrigin.y) &&
      near(twoRowCollapsed.x + OverlayControls.collapsedSize.width,
           twoRowOrigin.x + OverlayControls.expandedSize.width),
      "Collapse keeps the lower row and right edge anchored")
let screen = NSRect(x: 0, y: 0, width: 1000, height: 600)
let size = OverlayControls.expandedSize
let above = ToolbarPlacement.origin(
    overlay: NSRect(x: 100, y: 100, width: 860, height: 176),
    size: size,
    visibleFrames: [screen]
)
check(near(above.x, 784) && near(above.y, 148), "Toolbar in the right rail, below the top edge")
let below = ToolbarPlacement.origin(
    overlay: NSRect(x: 700, y: 490, width: 860, height: 176),
    size: size,
    visibleFrames: [screen]
)
check(near(below.x, 826) && near(below.y, 514),
      "Toolbar stays inside the visible part of a lyric window at the screen edge")
let secondScreen = NSRect(x: 1000, y: -200, width: 1200, height: 700)
let moved = ToolbarPlacement.origin(
    overlay: NSRect(x: 1300, y: 100, width: 860, height: 176),
    size: size,
    visibleFrames: [screen, secondScreen]
)
check(near(moved.x, 1984) && near(moved.y, 148), "Toolbar anchors within the active display")
let safelyKept = OverlayVisibility.origin(
    for: NSRect(x: 1200, y: 100, width: 860, height: 176), visibleFrames: [screen, secondScreen]
)
check(near(safelyKept.x, 1200) && near(safelyKept.y, 100), "Keep visible lyric window")
let rescued = OverlayVisibility.origin(
    for: NSRect(x: 1300, y: 1200, width: 860, height: 176), visibleFrames: [screen]
)
check(near(rescued.x, 140) && near(rescued.y, 424), "Recover lyric window from disconnected display")
let mostlyStranded = OverlayVisibility.origin(
    for: NSRect(x: 960, y: 300, width: 860, height: 176), visibleFrames: [screen]
)
check(near(mostlyStranded.x, 140) && near(mostlyStranded.y, 300),
      "Recover lyric window even when a narrow sliver remains")

let isolated = ToolbarPlacement.origin(
    overlay: NSRect(x: 2400, y: 200, width: 860, height: 176),
    size: size,
    visibleFrames: [screen, secondScreen]
)
check(isolated.x >= secondScreen.minX && isolated.x + size.width <= secondScreen.maxX,
      "Fallback position remains on a visible display")

let noDisplay = ToolbarPlacement.origin(
    overlay: NSRect(x: 100, y: 100, width: 860, height: 176),
    size: size, visibleFrames: []
)
check(near(noDisplay.x, 784) && near(noDisplay.y, 148),
      "Display-less fallback remains inside the lyric frame")
let collapsedPoint = ToolbarPlacement.origin(
    overlay: NSRect(x: 100, y: 100, width: 860, height: 176),
    size: OverlayControls.collapsedSize, visibleFrames: [screen]
)
check(near(collapsedPoint.x + OverlayControls.collapsedSize.width, above.x + size.width),
      "Collapsed toolbar keeps the same right edge")
let thinSliver = NSRect(x: -800, y: 100, width: 860, height: 176)
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
let tinySliver = NSRect(x: -840, y: 100, width: 860, height: 176)
let tinyCollapsed = ToolbarPlacement.origin(overlay: tinySliver,
                                             size: OverlayControls.collapsedSize,
                                             visibleFrames: [screen])
check(tinyCollapsed.x + OverlayControls.collapsedSize.width <= tinySliver.maxX &&
      tinyCollapsed.x + 2 + 34 > screen.minX,
      "When less than a button fits, the visible part still stays inside the lyric sliver")
let edgeScreens = [screen, secondScreen]
let edgeOverlay = NSRect(x: 950, y: 100, width: 860, height: 176)
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
check(controls.controlPanels.count == 8 &&
      controls.controlPanels.allSatisfy {
          !$0.hasShadow && !$0.isOpaque && !$0.hidesOnDeactivate &&
          $0.collectionBehavior.contains(.canJoinAllSpaces) && $0.animationBehavior == .none
      },
      "Only individual 34-point control windows can receive clicks")
controls.follow(overlay: twoRowOverlay, visibleFrames: [screen])
check(controls.controlPanels[5].frame.midY > controls.controlPanels[0].frame.midY,
      "Playback controls sit above the lower row of management actions")
check(controls.controlPanels[5].contentView!.accessibilityLabel() == "上一首" &&
      controls.controlPanels[7].contentView!.accessibilityLabel() == "下一首",
      "Transport controls have accessible names")
controls.setPlaybackAvailability(previous: false, toggle: .unavailable, next: false)
check([5, 6, 7].allSatisfy { !(controls.controlPanels[$0].contentView! as! NSButton).isEnabled },
      "Transport controls are disabled until reliable menu actions are available")
controls.setPlaybackAvailability(previous: true, toggle: .pause, next: true)
check([5, 6, 7].allSatisfy { (controls.controlPanels[$0].contentView! as! NSButton).isEnabled } &&
      controls.controlPanels[6].contentView!.accessibilityLabel() == "暂停",
      "An available playing state exposes a pause control")
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
var tappedPrevious = 0
var tappedPlayback = 0
var tappedNext = 0
controls.onPrevious = { tappedPrevious += 1 }
controls.onTogglePlayback = { tappedPlayback += 1 }
controls.onNext = { tappedNext += 1 }
let toolbarButtons = controls.controlPanels.compactMap { $0.contentView as? NSButton }
toolbarButtons.first(where: { $0.accessibilityLabel() == "锁定歌词位置" })!.performClick(nil)
toolbarButtons.first(where: { $0.accessibilityLabel() == "设置歌词样式" })!.performClick(nil)
toolbarButtons.first(where: { $0.accessibilityLabel() == "收起工具条" })!.performClick(nil)
check(tappedLock == 1 && tappedSettings == 1 && tappedCollapse == 1,
      "Toolbar actions dispatch to their owning controller")
for index in [5, 6, 7] { (controls.controlPanels[index].contentView! as! NSButton).performClick(nil) }
check(tappedPrevious == 1 && tappedPlayback == 1 && tappedNext == 1,
      "All three transport controls dispatch to their controller")
controls.setPlaybackAvailability(previous: false, toggle: .unavailable, next: false)
for index in [5, 6, 7] { (controls.controlPanels[index].contentView! as! NSButton).performClick(nil) }
check(tappedPrevious == 1 && tappedPlayback == 1 && tappedNext == 1,
      "Unavailable transport controls cannot dispatch actions")
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
controls.follow(overlay: NSRect(x: 100, y: 100, width: 860, height: 176),
                visibleFrames: [screen])
check(near(controls.panel.frame.maxX, 950) && near(controls.panel.frame.minY, 148),
      "Collapsed button stays in the inside lower-right rail")
toolbarButtons.first(where: { $0.accessibilityLabel() == "展开歌词工具条" })!.performClick(nil)
check(tappedCollapse == 2, "Collapsed toolbar exposes an expand action")
controls.setCollapsed(false)
check(near(controls.panel.frame.width, 166) && near(controls.panel.frame.height, 80), "Restored toolbar width")
controls.follow(overlay: NSRect(x: 100, y: 100, width: 860, height: 176),
                visibleFrames: [screen])
check(near(controls.panel.frame.origin.x, 784) && near(controls.panel.frame.origin.y, 148),
      "Interactive toolbar follows the lyric panel on its inside")
controls.setVisible(true)
let activeWindows = controls.controlPanels.filter(\.isVisible)
check(activeWindows.count == 7 && activeWindows.allSatisfy { $0.frame.width == 34 },
      "Expanded toolbar exposes seven small hit windows rather than one large one")
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
check(near(controls.controlPanels[4].frame.minY, controls.panel.frame.minY + 3),
      "The collapsed hit window stays in the lower row")
controls.setVisible(false)
check(controls.controlPanels.allSatisfy { !$0.isVisible },
      "Hiding lyrics also removes all toolbar hit targets")

// Exercise the window server's real mouse target selection, not just view hitTest.
// Window ordering and ignoresMouseEvents cross a process boundary, so wait for
// WindowServer's state rather than assuming the next instruction sees the change.
let liveScreen = NSScreen.main!.visibleFrame
let liveOverlay = NSRect(x: liveScreen.midX - 430, y: liveScreen.midY - 88,
                         width: 860, height: 176)
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
    controls.controlPanels.enumerated().filter { $0.offset != 4 }.allSatisfy { _, window in
        mouseTarget(NSPoint(x: window.frame.midX, y: window.frame.midY)) == window.windowNumber
    }
}
let dragCenter = NSPoint(x: controls.controlPanels[0].frame.midX,
                         y: controls.controlPanels[0].frame.midY)
let lockCenter = NSPoint(x: controls.controlPanels[1].frame.midX,
                         y: controls.controlPanels[1].frame.midY)
awaitMouseState("All seven buttons receive clicks; the gap reaches unlocked lyrics") {
    expandedButtonsReceiveClicks() && mouseTarget(clickGap) == lyricPanel.windowNumber
}
// Run a native down/up sequence through the small panel, not NSButton.performClick.
// Posting the up event first lets NSButton's tracking loop consume it after down.
func sendPanelClick(_ window: NSPanel) {
    let location = NSPoint(x: window.contentView!.bounds.midX,
                           y: window.contentView!.bounds.midY)
    let timestamp = ProcessInfo.processInfo.systemUptime
    let down = NSEvent.mouseEvent(with: .leftMouseDown, location: location,
                                  modifierFlags: [], timestamp: timestamp,
                                  windowNumber: window.windowNumber, context: nil,
                                  eventNumber: 1, clickCount: 1, pressure: 1)!
    let up = NSEvent.mouseEvent(with: .leftMouseUp, location: location,
                                modifierFlags: [], timestamp: timestamp + 0.01,
                                windowNumber: window.windowNumber, context: nil,
                                eventNumber: 2, clickCount: 1, pressure: 0)!
    NSApp.postEvent(up, atStart: true)
    window.sendEvent(down)
}
let countsBeforeEvents = (tappedLock, tappedSettings, tappedCollapse)
sendPanelClick(controls.controlPanels[1])
sendPanelClick(controls.controlPanels[2])
sendPanelClick(controls.controlPanels[3])
check(tappedLock == countsBeforeEvents.0 + 1 &&
      tappedSettings == countsBeforeEvents.1 + 1 &&
      tappedCollapse == countsBeforeEvents.2 + 1,
      "Native button-window mouse events dispatch lock, style, and collapse actions")
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
awaitMouseState("All seven controls can receive clicks after expanding again") {
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
var overlayForDrag = NSRect(x: 100, y: 100, width: 860, height: 176)
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

let lyricView = LyricsView(frame: NSRect(x: 0, y: 0, width: 860, height: 176))
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
let detailLabel = lyricView.subviews[3] as! NSTextField
let primaryChip = lyricView.subviews[0]
let detailChip = lyricView.subviews[1]
let expandedInside = NSRect(x: 584, y: 48, width: 166, height: 80)
lyricView.setControlsFrame(expandedInside)
lyricView.show(primary: "合成歌词", secondary: "合成副句", fraction: 0, active: true)
lyricView.layout()
check(near(primaryLabel.frame.midX, lyricView.bounds.midX),
      "Short primary lyrics remain centered with the rail open")
check(near(detailLabel.frame.midX, lyricView.bounds.midX),
      "Short next or translated lyrics remain centered independently")

let mediumLine = String(repeating: "合成", count: 10)
lyricView.applyStyle(OverlayStyle(backgroundRGB: "#123456", textRGB: "#F0E0D0", chipRGB: "#112233",
                                  backgroundOpacity: 0.15, chipOpacity: 0.55))
lyricView.show(primary: mediumLine, secondary: String(repeating: "合成", count: 19),
               fraction: 0, active: true)
lyricView.layout()
check(primaryLabel.frame.midX < lyricView.bounds.midX &&
      detailLabel.frame.midX < lyricView.bounds.midX,
      "Both lyric rows use their dedicated left-side area")
check(primaryChip.frame.maxX <= expandedInside.minX - 20 &&
      detailChip.frame.maxX <= expandedInside.minX - 20,
      "Both text backgrounds leave clearance before the controls")
check(primaryLabel.frame.maxX <= expandedInside.minX - 20 &&
      detailLabel.frame.maxX <= expandedInside.minX - 20,
      "Neither label can draw beneath the toolbar")

lyricView.show(primary: String(repeating: "很长的合成歌词", count: 12),
               secondary: "", fraction: 0, active: true)
lyricView.layout()
check(primaryChip.frame.maxX <= expandedInside.minX - 20 &&
      primaryChip.frame.width <= primaryLabel.frame.width,
      "Long wrapped text and its background do not cover the toolbar")

lyricView.show(primary: mediumLine, secondary: "", fraction: 0, active: true)
lyricView.setControlsFrame(NSRect(x: 712, y: 48, width: 38, height: 38))
lyricView.layout()
check(near(primaryLabel.frame.midX, lyricView.bounds.midX),
      "After collapsing the toolbar, an ordinary line returns to the center")

let twoLineView = LyricsView(frame: NSRect(x: 0, y: 0, width: 860, height: 176))
let rightRail = NSRect(x: 684, y: 48, width: 166, height: 80)
twoLineView.setControlsFrame(rightRail)
twoLineView.show(primary: String(repeating: "合成歌词", count: 16),
                 secondary: String(repeating: "合成副句", count: 14), fraction: 0.3, active: true)
twoLineView.layout()
let twoLinePrimary = twoLineView.subviews[2] as! NSTextField
let twoLineDetail = twoLineView.subviews[3] as! NSTextField
check(twoLinePrimary.maximumNumberOfLines == 2 && twoLineDetail.maximumNumberOfLines == 2,
      "Both lyric lines permit up to two visual rows")
check(twoLinePrimary.stringValue.contains("\n") && twoLinePrimary.font!.pointSize < 24 &&
      twoLinePrimary.font!.pointSize >= 16,
      "A long primary line wraps before shrinking below 16 pt")
check(twoLineDetail.stringValue.contains("\n") &&
      twoLineDetail.font!.pointSize >= 12,
      "The next/translated line also wraps in its own bounded area")
check(twoLinePrimary.frame.maxX <= rightRail.minX - 20 &&
      twoLineDetail.frame.maxX <= rightRail.minX - 20,
      "Neither text line may enter the transport/control rail")
check(twoLinePrimary.frame.minY > twoLineDetail.frame.maxY &&
      twoLineDetail.frame.minY > 18,
      "Two-line lyrics, next line, and progress each have their own vertical band")
twoLineView.show(primary: String(repeating: "特别长的合成歌词", count: 200),
                 secondary: "", fraction: 0.5, active: true)
twoLineView.layout()
check(near(twoLinePrimary.font!.pointSize, 16) &&
      twoLinePrimary.stringValue.hasSuffix("…") &&
      twoLinePrimary.stringValue.components(separatedBy: "\n").count == 2,
      "Extreme lyrics are limited to two rows at minimum size and end with an ellipsis")
check(twoLinePrimary.accessibilityLabel() == String(repeating: "特别长的合成歌词", count: 200),
      "Accessibility retains full lyric content even when visually abbreviated")
twoLineView.show(primary: "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}" + String(repeating: " 合成", count: 180),
                 secondary: "", fraction: 0.4, active: true)
twoLineView.layout()
check(twoLinePrimary.stringValue.first == "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}" &&
      twoLinePrimary.stringValue.hasSuffix("…"),
      "Two-row truncation never cuts through a composed Unicode character")
twoLineView.show(primary: String(repeating: "合成", count: 140),
                 secondary: String(repeating: "翻译", count: 140), fraction: 0.5, active: true)
twoLineView.layout()
check(twoLineDetail.stringValue.hasSuffix("…") &&
      near(twoLineDetail.font!.pointSize, 12) &&
      twoLineDetail.accessibilityLabel() == String(repeating: "翻译", count: 140),
      "Extreme secondary text also truncates at its own font minimum with complete accessibility text")
let waveform = twoLineView.subviews.compactMap { $0 as? WaveformView }.first!
twoLineView.show(primary: "合成", secondary: "", fraction: 0, active: true, playing: true)
check(waveform.isAnimating, "Playback starts the ambient visual waveform")
twoLineView.show(primary: "合成", secondary: "", fraction: 0, active: true, playing: false)
check(!waveform.isAnimating && !waveform.isHidden, "Paused playback leaves static bars visible")
waveform.reduceMotionProvider = { true }
twoLineView.show(primary: "合成", secondary: "", fraction: 0, active: true, playing: true)
check(!waveform.isAnimating, "The system's Reduced Motion preference disables the waveform timer")
waveform.reduceMotionProvider = { false }
waveform.refreshMotionPreference()
check(waveform.isAnimating, "The waveform resumes when Reduced Motion is disabled")
twoLineView.setOverlayVisible(false)
check(!waveform.isAnimating, "Hiding the lyrics stops the waveform timer")
twoLineView.setOverlayVisible(true)
check(waveform.isAnimating, "Showing playing lyrics restarts the waveform")
twoLineView.show(primary: "等待", secondary: "", fraction: 0, active: false)
check(!waveform.isAnimating && waveform.isHidden, "Unavailable playback hides and stops the waveform")
check(!WaveformMotion.shouldAnimate(playing: false, reduceMotion: false) &&
      !WaveformMotion.shouldAnimate(playing: true, reduceMotion: true) &&
      WaveformMotion.shouldAnimate(playing: true, reduceMotion: false),
      "Waveform stops when paused or when Reduced Motion is enabled")

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
