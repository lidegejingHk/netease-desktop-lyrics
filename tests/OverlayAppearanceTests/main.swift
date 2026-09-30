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
check(pausedMenu.allows(.previous) && pausedMenu.allows(.play) && pausedMenu.allows(.next) &&
      !pausedMenu.allows(.pause) &&
      !PlaybackTransport.Availability.unavailable.allows(.next),
      "The controller only dispatches actions from the last verified menu state")
let failedPrevious = pausedMenu.suppressing(.previous)
check(!failedPrevious.allows(.previous) && failedPrevious.allows(.play) && failedPrevious.allows(.next),
      "A failed previous press disables only that transport action")
let failedPlay = pausedMenu.suppressing(.play)
check(!failedPlay.allows(.play) && failedPlay.previous && failedPlay.next,
      "A failed play press does not immediately re-enable the failed toggle")
var failureLatch = PlaybackTransport.FailureLatch()
failureLatch.record(.play, in: pausedMenu)
check(!failureLatch.visibleState(for: pausedMenu).allows(.play) &&
      !failureLatch.visibleState(for: pausedMenu).allows(.play),
      "The same failing menu action stays disabled over repeated polling")
check(failureLatch.visibleState(for: .unavailable) == .unavailable &&
      !failureLatch.visibleState(for: pausedMenu).allows(.play),
      "A temporary AX read failure cannot re-enable an unchanged failed action")
let partialChange = PlaybackTransport.Availability(previous: false, toggle: .play, next: true)
check(!failureLatch.visibleState(for: partialChange).allows(.play) &&
      failureLatch.hasFailure,
      "Changing unrelated menu actions does not re-enable a failing play action")
let changedMenu = PlaybackTransport.Availability(previous: false, toggle: .pause, next: true)
check(failureLatch.visibleState(for: changedMenu).allows(.pause) &&
      failureLatch.failed == nil,
      "A changed player menu clears a failed-action latch")
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
let partiallyPressable = [
    PlaybackTransport.Item(role: "AXMenuItem", title: "播放", enabled: true, pressable: true),
    PlaybackTransport.Item(role: "AXMenuItem", title: "暂停", enabled: true, pressable: false)
]
check(PlaybackTransport.availability(partiallyPressable).toggle == .play &&
      PlaybackTransport.uniqueIndex(for: .play, in: partiallyPressable) == 0 &&
      PlaybackTransport.uniqueIndex(for: .pause, in: partiallyPressable) == nil,
      "Menu availability and execution agree when only one item offers AXPress")
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

// Tool actions stay above; transport sits between lyrics and waveform on one background.
let lyricRect = NSRect(x: 116, y: 180, width: 848, height: 126)
let screen = NSRect(x: 0, y: 0, width: 1000, height: 600)
let outerRect = OverlayLayout.outerFrame(for: lyricRect)
let toolbarRect = OverlayLayout.toolbarFrame(for: lyricRect)
let collapsedRect = OverlayLayout.toolbarFrame(for: lyricRect, collapsed: true)
let playbackRect = OverlayLayout.playbackFrame(for: lyricRect)
let railRect = OverlayLayout.railFrame(for: lyricRect)
let envelope = OverlayLayout.envelope(for: lyricRect)
check(OverlayLayout.lyricSize == lyricRect.size &&
      outerRect == NSRect(x: 100, y: 100, width: 880, height: 256),
      "One compact 880×256 background encloses all four content zones")
check(toolbarRect == NSRect(x: 804, y: 310, width: 160, height: 36) &&
      near(toolbarRect.minY - lyricRect.maxY, 4) && outerRect.contains(toolbarRect),
      "Only placement and appearance tools occupy the compact top-right row")
check(near(collapsedRect.maxX, toolbarRect.maxX) &&
      near(collapsedRect.maxY, toolbarRect.maxY),
      "Collapsing keeps the upper-right anchor")
check(playbackRect == NSRect(x: 474, y: 144, width: 132, height: 32) &&
      near(lyricRect.minY - playbackRect.maxY, 4) &&
      near(playbackRect.midX, outerRect.midX) && outerRect.contains(playbackRect),
      "Transport has its own centered row four points beneath the lyric region")
check(railRect == NSRect(x: 124, y: 112, width: 832, height: 28) &&
      near(playbackRect.minY - railRect.maxY, 4) && outerRect.contains(railRect),
      "The full-width waveform sits four points beneath the transport row")
check(outerRect.contains(lyricRect) && envelope == outerRect &&
      !toolbarRect.intersects(lyricRect) && !railRect.intersects(lyricRect) &&
      !playbackRect.intersects(lyricRect) && !playbackRect.intersects(railRect),
      "Tools, text, transport and waveform do not overlap")
check(ToolbarPlacement.origin(overlay: lyricRect,
                              size: OverlayControls.expandedSize) == toolbarRect.origin,
      "Toolbar placement uses the enclosing frame's top-right inset")
let secondScreen = NSRect(x: 1000, y: -200, width: 1200, height: 700)
check(OverlayVisibility.origin(for: envelope, visibleFrames: [screen]) == envelope.origin,
      "Keep the complete framed group on screen without jumping")
let rescued = OverlayVisibility.origin(
    for: envelope.offsetBy(dx: 1200, dy: 700), visibleFrames: [screen])
check(near(rescued.x, 120) && near(rescued.y, 344),
      "A disconnected screen recovers the whole enclosing frame")
let clippedLyric = lyricRect.offsetBy(dx: -140, dy: -140)
let corrected = OverlayLayout.constrainedOrigin(for: clippedLyric, visibleFrames: [screen])
check(near(corrected.x, 16) && near(corrected.y, 80),
      "Dragging clips the outer frame before losing its toolbar or lower waveform")
let topEdge = OverlayVisibility.origin(
    for: envelope.offsetBy(dx: 80, dy: 450), visibleFrames: [screen])
check(near(topEdge.y, 344), "Screen top reserves room for the framed toolbar")
let secondEnvelope = envelope.offsetBy(dx: 1100, dy: -20)
check(OverlayVisibility.origin(for: secondEnvelope,
                               visibleFrames: [screen, secondScreen]) == secondEnvelope.origin,
      "A framed group on another display retains its placement")

let _ = NSApplication.shared
let controls = OverlayControls()
check(!controls.panel.hasShadow &&
      controls.controlPanels.allSatisfy { $0.level.rawValue > NSWindow.Level.floating.rawValue },
      "Individual transparent controls float above the lyrics without detached shadows")
check(controls.panel.ignoresMouseEvents && controls.playbackPanel.ignoresMouseEvents &&
      !controls.panel.isVisible && !controls.playbackPanel.isVisible &&
      controls.panel.contentView?.layer?.backgroundColor?.alpha == 0 &&
      controls.playbackPanel.contentView?.layer?.backgroundColor?.alpha == 0 &&
      controls.panel.contentView?.layer?.borderWidth == 0 &&
      controls.playbackPanel.contentView?.layer?.borderWidth == 0,
      "Both functional groups use invisible click-through layout surfaces")
check(controls.controlPanels.count == 8 &&
      controls.controlPanels.allSatisfy {
          !$0.hasShadow && !$0.isOpaque && !$0.hidesOnDeactivate &&
          $0.collectionBehavior.contains(.canJoinAllSpaces) && $0.animationBehavior == .none
      },
      "Only individual control icon windows can receive clicks")
controls.follow(overlay: lyricRect)
check(controls.panel.frame == toolbarRect && controls.playbackPanel.frame == playbackRect &&
      (0...3).allSatisfy { controls.panel.frame.contains(controls.controlPanels[$0].frame) } &&
      (5...7).allSatisfy { controls.playbackPanel.frame.contains(controls.controlPanels[$0].frame) },
      "Four tools occupy the upper-right row and three transport buttons sit beneath lyrics")
check((5...7).allSatisfy { near(controls.controlPanels[$0].frame.midY, playbackRect.midY) } &&
      near(controls.controlPanels[6].frame.midX, outerRect.midX) &&
      controls.controlPanels[5].frame.maxX < controls.controlPanels[6].frame.minX &&
      controls.controlPanels[6].frame.maxX < controls.controlPanels[7].frame.minX &&
      controls.controlPanels[6].frame.size == NSSize(width: 38, height: 32) &&
      controls.controlPanels[5].frame.size == NSSize(width: 34, height: 30) &&
      controls.controlPanels[7].frame.size == NSSize(width: 34, height: 30),
      "Playback trio is centered with a slightly larger middle button and ten-point gaps")
check(controls.controlPanels[5].contentView!.accessibilityLabel() == "上一首" &&
      controls.controlPanels[7].contentView!.accessibilityLabel() == "下一首",
      "Transport controls have accessible names")
controls.setPlaybackAvailability(previous: false, toggle: .unavailable, next: false)
check([5, 6, 7].allSatisfy {
    !(controls.controlPanels[$0].contentView! as! NSButton).isEnabled &&
    controls.controlPanels[$0].ignoresMouseEvents
}, "Unavailable transport icons remain visible but cannot intercept desktop input")
controls.setPlaybackAvailability(previous: true, toggle: .pause, next: true)
check([5, 6, 7].allSatisfy { (controls.controlPanels[$0].contentView! as! NSButton).isEnabled } &&
      (5...7).allSatisfy { !controls.controlPanels[$0].ignoresMouseEvents } &&
      controls.controlPanels[6].contentView!.accessibilityLabel() == "暂停",
      "An available playing state exposes a pause control")
let handle = controls.controlPanels[0].contentView!
check(handle.hitTest(NSPoint(x: 17, y: 16)) === handle,
      "Drag handle receives pointer input in its own small panel")
let styledToolbar = OverlayStyle(backgroundRGB: "#112233", textRGB: "#20CF80", chipRGB: "#000000",
                                 backgroundOpacity: 0.3, chipOpacity: 0.5)
controls.applyStyle(styledToolbar)
let handleGlyph = handle.subviews.first as! NSTextField
check(OverlayStyle.rgbHex(handleGlyph.textColor!) == "#20CF80" &&
      near(controls.panel.contentView!.layer!.backgroundColor!.alpha, 0) &&
      near(controls.playbackPanel.contentView!.layer!.backgroundColor!.alpha, 0) &&
      (controls.controlPanels[6].contentView! as! NSButton).contentTintColor!.alphaComponent >
      (controls.controlPanels[5].contentView! as! NSButton).contentTintColor!.alphaComponent,
      "Separated groups share tint, with a brighter middle button and no second card")
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
check(tappedPrevious == 1 && tappedPlayback == 1 && tappedNext == 1 &&
      (5...7).allSatisfy { controls.controlPanels[$0].ignoresMouseEvents },
      "Unavailable transport controls cannot dispatch actions")
controls.setLocked(true)
check(controls.controlPanels[0].ignoresMouseEvents &&
      (1...4).allSatisfy { !controls.controlPanels[$0].ignoresMouseEvents } &&
      (5...7).allSatisfy { controls.controlPanels[$0].ignoresMouseEvents },
      "Lock passes through drag and disabled transport; remaining tools stay interactive")
check(handleGlyph.textColor!.alphaComponent < 0.5,
      "Locked drag handle dims while remaining visible")
dragDelta = .zero
handle.mouseDown(with: mouseDown)
handle.mouseDragged(with: movementEvent(x: 35, y: 22, deltaX: 25, deltaY: -12))
check(near(dragDelta.x, 0) && near(dragDelta.y, 0), "Locked drag handle never moves lyrics")
controls.setCollapsed(true)
check(near(controls.panel.frame.width, 42) && near(controls.panel.frame.height, 36) &&
      controls.panel.contentView!.frame.size == OverlayControls.collapsedSize &&
      controls.playbackPanel.frame == playbackRect,
      "Collapsing the tool row never moves the centered transport row")
controls.follow(overlay: lyricRect)
check(near(controls.panel.frame.maxX, toolbarRect.maxX) &&
      near(controls.panel.frame.maxY, toolbarRect.maxY),
      "Collapsed button keeps the upper-right edge")
toolbarButtons.first(where: { $0.accessibilityLabel() == "展开歌词工具条" })!.performClick(nil)
check(tappedCollapse == 2, "Collapsed toolbar exposes an expand action")
controls.setPlaybackAvailability(previous: true, toggle: .play, next: true)
for index in [5, 6, 7] { (controls.controlPanels[index].contentView! as! NSButton).performClick(nil) }
check(tappedPrevious == 2 && tappedPlayback == 2 && tappedNext == 2,
      "Collapsed tools leave the transport row operational")
controls.setCollapsed(false)
check(controls.panel.frame.size == OverlayLayout.toolbarSize, "Restored toolbar geometry")
controls.follow(overlay: lyricRect)
check(controls.panel.frame == toolbarRect && controls.playbackPanel.frame == playbackRect &&
      !controls.panel.frame.intersects(lyricRect) &&
      !controls.playbackPanel.frame.intersects(lyricRect),
      "Both icon rows follow the lyrics without stealing lyric space")
controls.setVisible(true)
controls.setPlaybackAvailability(previous: true, toggle: .pause, next: true)
let activeWindows = controls.controlPanels.filter(\.isVisible)
check(activeWindows.count == 7 &&
      (0...3).allSatisfy { controls.controlPanels[$0].isVisible } &&
      (5...7).allSatisfy { controls.controlPanels[$0].isVisible } &&
      !controls.controlPanels[4].isVisible &&
      controls.playbackPanel.isVisible,
      "Both groups expose seven small hit windows rather than one large panel")
check(activeWindows.allSatisfy { !$0.ignoresMouseEvents || $0 === controls.controlPanels[0] },
      "Icon panels remain interactive")
let gap = NSPoint(x: controls.panel.frame.minX + 41, y: controls.panel.frame.minY + 18)
let playbackGap = NSPoint(x: controls.playbackPanel.frame.minX + 42,
                          y: controls.playbackPanel.frame.midY)
check(controls.panel.frame.contains(gap) && controls.playbackPanel.frame.contains(playbackGap) &&
      !activeWindows.contains(where: { $0.frame.contains(gap) || $0.frame.contains(playbackGap) }),
      "Both transparent icon gaps contain no mouse-intercepting window")
controls.setCollapsed(true)
check(controls.controlPanels.filter(\.isVisible).count == 4 &&
      controls.controlPanels[4].isVisible &&
      (5...7).allSatisfy { controls.controlPanels[$0].isVisible } &&
      controls.playbackPanel.isVisible,
      "Collapsing tools leaves the centered playback trio available")
check(near(controls.controlPanels[4].frame.maxX, controls.panel.frame.maxX - 4),
      "The collapsed hit window stays on the same right edge")
check(near(controls.controlPanels[4].frame.minY, controls.panel.frame.minY + 2),
      "The collapsed hit window stays vertically centered")
controls.setVisible(false)
check(controls.controlPanels.allSatisfy { !$0.isVisible } &&
      !controls.panel.isVisible && !controls.playbackPanel.isVisible,
      "Hiding lyrics removes both groups and all hit targets")

// Exercise the window server's real mouse target selection, not just view hitTest.
// Window ordering and ignoresMouseEvents cross a process boundary, so wait for
// WindowServer's state rather than assuming the next instruction sees the change.
let liveScreen = NSScreen.main!.visibleFrame
let liveOverlay = NSRect(x: liveScreen.midX - OverlayLayout.lyricSize.width / 2,
                         y: liveScreen.midY - OverlayLayout.lyricSize.height / 2,
                         width: OverlayLayout.lyricSize.width,
                         height: OverlayLayout.lyricSize.height)
let lyricPanel = NSPanel(contentRect: liveOverlay, styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
lyricPanel.level = .floating
lyricPanel.orderFrontRegardless()
controls.follow(overlay: liveOverlay)
controls.setCollapsed(false)
controls.setLocked(false)
controls.setVisible(true)
let clickGap = NSPoint(x: controls.panel.frame.minX + 41,
                       y: controls.panel.frame.minY + 18)
let clickPlaybackGap = NSPoint(x: controls.playbackPanel.frame.minX + 42,
                               y: controls.playbackPanel.frame.midY)
func mouseTarget(_ point: NSPoint) -> Int {
    NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
}
let sessionInfo = CGSessionCopyCurrentDictionary() as? [String: Any]
let sessionLocked = sessionInfo?["CGSSessionScreenIsLocked"] as? Bool ?? false
if sessionLocked { print("SKIPPED WindowServer pointer assertions: macOS session is locked") }
func awaitMouseState(_ message: String, _ matches: () -> Bool) {
    // Loginwindow's secure overlay wins hit testing while the display is locked.
    // Keep AppKit state tests, but never report these desktop-hit assertions as passed.
    if sessionLocked { return }
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
awaitMouseState("Both icon rows receive clicks; their gaps are click-through") {
    expandedButtonsReceiveClicks() &&
    mouseTarget(clickGap) != controls.panel.windowNumber &&
    mouseTarget(clickPlaybackGap) != controls.playbackPanel.windowNumber &&
    !controls.controlPanels.contains(where: {
        $0.windowNumber == mouseTarget(clickGap) ||
        $0.windowNumber == mouseTarget(clickPlaybackGap)
    })
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
awaitMouseState("Hidden controls leave no mouse targets over the desktop") {
    mouseTarget(dragCenter) != controls.controlPanels[0].windowNumber &&
    mouseTarget(lockCenter) != controls.controlPanels[1].windowNumber &&
    mouseTarget(dragCenter) != controls.panel.windowNumber &&
    mouseTarget(NSPoint(x: controls.controlPanels[6].frame.midX,
                        y: controls.controlPanels[6].frame.midY)) != controls.controlPanels[6].windowNumber
}
controls.setVisible(true)
awaitMouseState("Buttons work immediately after showing the toolbar again") {
    expandedButtonsReceiveClicks() && mouseTarget(clickGap) != controls.panel.windowNumber
}
controls.setCollapsed(true)
let expandPanel = controls.controlPanels[4]
let expandCenter = NSPoint(x: expandPanel.frame.midX, y: expandPanel.frame.midY)
awaitMouseState("Collapsed tools retain expand and all playback hit targets") {
    mouseTarget(expandCenter) == expandPanel.windowNumber &&
    (5...7).allSatisfy { index in
        let window = controls.controlPanels[index]
        return mouseTarget(NSPoint(x: window.frame.midX, y: window.frame.midY)) == window.windowNumber
    } &&
    mouseTarget(dragCenter) != controls.controlPanels[0].windowNumber
}
controls.setCollapsed(false)
awaitMouseState("All seven controls can receive clicks after expanding again") {
    expandedButtonsReceiveClicks() && mouseTarget(clickGap) != controls.panel.windowNumber
}
controls.setLocked(true)
lyricPanel.ignoresMouseEvents = true
awaitMouseState("Locked lyrics and drag handle pass clicks through, but lock stays clickable") {
    mouseTarget(lockCenter) == controls.controlPanels[1].windowNumber &&
    (5...7).allSatisfy { index in
        let window = controls.controlPanels[index]
        return mouseTarget(NSPoint(x: window.frame.midX, y: window.frame.midY)) == window.windowNumber
    } &&
    mouseTarget(dragCenter) != controls.controlPanels[0].windowNumber &&
    mouseTarget(dragCenter) != lyricPanel.windowNumber &&
    mouseTarget(clickGap) != controls.panel.windowNumber &&
    mouseTarget(clickPlaybackGap) != controls.playbackPanel.windowNumber
}
controls.setPlaybackAvailability(previous: false, toggle: .unavailable, next: false)
awaitMouseState("Locked disabled transport remains visible without blocking underlying apps") {
    (5...7).allSatisfy { index in
        let window = controls.controlPanels[index]
        return window.isVisible && window.ignoresMouseEvents &&
            mouseTarget(NSPoint(x: window.frame.midX, y: window.frame.midY)) != window.windowNumber
    } && mouseTarget(lockCenter) == controls.controlPanels[1].windowNumber
}
controls.setPlaybackAvailability(previous: true, toggle: .pause, next: true)
awaitMouseState("Re-enabled transport immediately accepts clicks after locked pass-through") {
    (5...7).allSatisfy { index in
        let window = controls.controlPanels[index]
        return mouseTarget(NSPoint(x: window.frame.midX, y: window.frame.midY)) == window.windowNumber
    }
}
controls.setVisible(false)
lyricPanel.orderOut(nil)

controls.setLocked(false)
var overlayForDrag = lyricRect
controls.onDrag = { delta in
    overlayForDrag.origin.x += delta.x
    overlayForDrag.origin.y += delta.y
    controls.follow(overlay: overlayForDrag)
}
// Construct both events before the first callback moves the toolbar: queued events must not double-count it.
let queuedA = movementEvent(x: 140, y: 290, deltaX: 20, deltaY: -15)
let queuedB = movementEvent(x: 155, y: 300, deltaX: 15, deltaY: 10)
handle.mouseDown(with: mouseDown)
handle.mouseDragged(with: queuedA)
handle.mouseDragged(with: queuedB)
check(near(overlayForDrag.minX, 151) && near(overlayForDrag.minY, 185),
      "Queued drag events move by their independent deltas, not moving-window coordinates")

let outer = OverlayFrame()
outer.follow(lyrics: lyricRect)
check(outer.panel.level.rawValue > NSWindow.Level.normal.rawValue &&
      outer.panel.level.rawValue < NSWindow.Level.floating.rawValue,
      "The background must stay below floating lyric and waveform windows during every drag")
check(outer.panel.frame == outerRect && !outer.panel.ignoresMouseEvents &&
      outer.panel.contentView!.layer!.cornerRadius == 21,
      "The unified outer frame accepts pointer input when unlocked")
let lyricView = LyricsView(frame: NSRect(origin: .zero, size: OverlayLayout.lyricSize))
let customStyle = OverlayStyle(backgroundRGB: "#123456", textRGB: "#F0E0D0",
                               chipRGB: "#112233", backgroundOpacity: 0.15, chipOpacity: 0.55)
lyricView.applyStyle(customStyle)
outer.applyStyle(customStyle)
check(near(outer.panel.contentView!.layer!.backgroundColor!.alpha, 0.15),
      "The only full-frame background uses the user-selected opacity exactly")
let dragLyricPanel = NSPanel(contentRect: lyricRect,
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
var backgroundDragCount = 0
outer.onDrag = { delta in
    backgroundDragCount += 1
    let proposed = dragLyricPanel.frame.offsetBy(dx: delta.x, dy: delta.y)
    dragLyricPanel.setFrameOrigin(OverlayLayout.constrainedOrigin(
        for: proposed, visibleFrames: [screen]))
    outer.follow(lyrics: dragLyricPanel.frame)
    controls.follow(overlay: dragLyricPanel.frame)
}
let backgroundDown = NSEvent.mouseEvent(with: .leftMouseDown,
    location: NSPoint(x: 90, y: 215), modifierFlags: [], timestamp: 0,
    windowNumber: outer.panel.windowNumber, context: nil, eventNumber: 0,
    clickCount: 1, pressure: 1)!
// Route a real AppKit mouse sequence through NSPanel before testing deltas
// directly. A hit-test alone cannot prove the background actually tracks drags.
let nativeDrag = NSEvent.mouseEvent(with: .leftMouseDragged,
    location: NSPoint(x: 100, y: 215), modifierFlags: [], timestamp: 0.01,
    windowNumber: outer.panel.windowNumber, context: nil, eventNumber: 1,
    clickCount: 1, pressure: 1)!
outer.setVisible(true)
outer.panel.sendEvent(backgroundDown)
outer.panel.sendEvent(nativeDrag)
check(backgroundDragCount == 1, "AppKit routes native drags to the gray background")
backgroundDragCount = 0
outer.panel.contentView!.mouseDragged(with: movementEvent(
    x: 190, y: 215, deltaX: 20, deltaY: -10))
check(backgroundDragCount == 1 &&
      near(dragLyricPanel.frame.minX, lyricRect.minX + 20) &&
      near(dragLyricPanel.frame.minY, lyricRect.minY + 10) &&
      outer.panel.frame == OverlayLayout.outerFrame(for: dragLyricPanel.frame) &&
      controls.panel.frame == OverlayLayout.toolbarFrame(for: dragLyricPanel.frame) &&
      controls.playbackPanel.frame == OverlayLayout.playbackFrame(for: dragLyricPanel.frame),
      "Dragging blank background moves lyrics, frame and both control groups together")
outer.panel.contentView!.mouseDragged(with: movementEvent(
    x: 240, y: 215, deltaX: 0, deltaY: -900))
check(backgroundDragCount == 2 &&
      near(dragLyricPanel.frame.minX, 136) &&
      near(dragLyricPanel.frame.minY, 424) &&
      outer.panel.frame == OverlayLayout.outerFrame(for: dragLyricPanel.frame),
      "Blank-background drag keeps the complete group within visible bounds")
outer.follow(lyrics: lyricRect)
controls.follow(overlay: lyricRect)
lyricView.show(primary: "合成歌词", secondary: "合成副句")
lyricView.layout()
check(near(lyricView.layer!.backgroundColor!.alpha, 0) &&
      lyricView.layer!.borderWidth == 0, "Lyric area draws no second card")
check(lyricView.subviews.count == 4 &&
      !lyricView.subviews[0].isHidden && !lyricView.subviews[1].isHidden,
      "Only the lyric lines and text-sized backings remain in the center region")
check(near(lyricView.subviews[0].layer!.backgroundColor!.alpha, 0.55), "Live chip alpha")
let primaryLabel = lyricView.subviews[2] as! NSTextField
let detailLabel = lyricView.subviews[3] as! NSTextField
let primaryChip = lyricView.subviews[0]
let detailChip = lyricView.subviews[1]
check(near(primaryLabel.frame.midX, lyricView.bounds.midX) &&
      near(detailLabel.frame.midX, lyricView.bounds.midX) &&
      near(primaryChip.frame.midX, lyricView.bounds.midX) &&
      near(detailChip.frame.midX, lyricView.bounds.midX),
      "Both lyric lines and text backgrounds center on the complete window width")
lyricView.applyStyle(.defaultValue)
lyricView.layout()
check(primaryChip.isHidden && detailChip.isHidden,
      "Default text background is transparent")
lyricView.show(primary: "等待网易云音乐…", secondary: "")
lyricView.layout()
check(near(primaryLabel.frame.midY, lyricView.bounds.midY) &&
      detailLabel.isHidden && detailChip.isHidden,
      "Single-line permission or waiting status is vertically centered without instructions")

lyricView.applyStyle(customStyle)
lyricView.show(primary: String(repeating: "合成歌词", count: 19),
               secondary: String(repeating: "合成副句", count: 16))
lyricView.layout()
check(primaryLabel.maximumNumberOfLines == 2 && detailLabel.maximumNumberOfLines == 2 &&
      primaryLabel.stringValue.contains("\n") && detailLabel.stringValue.contains("\n"),
      "Long primary and translated lines wrap independently into at most two rows")
check(primaryLabel.font!.pointSize <= 24 && primaryLabel.font!.pointSize >= 16 &&
      detailLabel.font!.pointSize <= 15 && detailLabel.font!.pointSize >= 12,
      "Long text shrinks as needed without violating minimum font sizes")
check(primaryLabel.frame.minX >= 24 && primaryLabel.frame.maxX <= lyricView.bounds.maxX - 24 &&
      detailLabel.frame.minX >= 24 && detailLabel.frame.maxX <= lyricView.bounds.maxX - 24 &&
      near(primaryLabel.frame.midX, lyricView.bounds.midX) &&
      near(detailLabel.frame.midX, lyricView.bounds.midX),
      "Two-line lyrics use the full centered band, not an internal control rail")
check(primaryLabel.frame.minY > detailLabel.frame.maxY &&
      primaryChip.frame.maxX <= lyricView.bounds.maxX - 24 &&
      detailChip.frame.maxX <= lyricView.bounds.maxX - 24 &&
      lyricRect.minY - playbackRect.maxY == 4,
      "Separate rows and their backgrounds never overlap or leave the lyric frame")
lyricView.show(primary: String(repeating: "特别长的合成歌词", count: 200), secondary: "")
lyricView.layout()
check(near(primaryLabel.font!.pointSize, 16) &&
      primaryLabel.stringValue.hasSuffix("…") &&
      primaryLabel.stringValue.components(separatedBy: "\n").count == 2,
      "Extreme lyrics use no more than two rows, minimum font size and an ellipsis")
check(primaryLabel.accessibilityLabel() == String(repeating: "特别长的合成歌词", count: 200),
      "Accessibility still exposes the entire original line")
lyricView.show(primary: "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}" +
               String(repeating: " 合成", count: 180), secondary: "")
lyricView.layout()
check(primaryLabel.stringValue.first == "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}" &&
      primaryLabel.stringValue.hasSuffix("…"),
      "Two-row truncation never splits a composed Unicode grapheme")
lyricView.show(primary: String(repeating: "合成", count: 140),
               secondary: String(repeating: "翻译", count: 140))
lyricView.layout()
check(detailLabel.stringValue.hasSuffix("…") &&
      near(detailLabel.font!.pointSize, 12) &&
      detailLabel.accessibilityLabel() == String(repeating: "翻译", count: 140),
      "Extreme secondary text truncates independently and preserves accessibility text")

// Lyric text, including its label, must use the same constrained drag path.
// Native AppKit background movement would bypass the complete-frame boundary.
let draggableLyrics = LyricsView(frame: NSRect(origin: .zero, size: lyricRect.size))
draggableLyrics.show(primary: "拖动这句合成歌词", secondary: "")
draggableLyrics.layout()
dragLyricPanel.contentView = draggableLyrics
dragLyricPanel.level = .floating
dragLyricPanel.isMovableByWindowBackground = false
var lyricDragCount = 0
draggableLyrics.onDrag = { delta in
    lyricDragCount += 1
    let proposed = dragLyricPanel.frame.offsetBy(dx: delta.x, dy: delta.y)
    dragLyricPanel.setFrameOrigin(OverlayLayout.constrainedOrigin(
        for: proposed, visibleFrames: [screen]))
    outer.follow(lyrics: dragLyricPanel.frame)
    controls.follow(overlay: dragLyricPanel.frame)
}
dragLyricPanel.setFrameOrigin(lyricRect.origin)
outer.follow(lyrics: lyricRect)
controls.follow(overlay: lyricRect)
dragLyricPanel.orderFrontRegardless()
let label = draggableLyrics.subviews[2] as! NSTextField
let labelCenter = NSPoint(x: label.frame.midX, y: label.frame.midY)
check(draggableLyrics.hitTest(labelCenter) === draggableLyrics,
      "Clicking visible lyric characters routes drag tracking to the lyric view")
let lyricDown = NSEvent.mouseEvent(with: .leftMouseDown, location: labelCenter,
    modifierFlags: [], timestamp: 0, windowNumber: dragLyricPanel.windowNumber,
    context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
let lyricDrag = NSEvent.mouseEvent(with: .leftMouseDragged, location: labelCenter,
    modifierFlags: [], timestamp: 0.01, windowNumber: dragLyricPanel.windowNumber,
    context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
dragLyricPanel.sendEvent(lyricDown)
dragLyricPanel.sendEvent(lyricDrag)
check(lyricDragCount == 1, "Native lyric-label drag reaches the constrained callback")
lyricDragCount = 0
draggableLyrics.mouseDragged(with: movementEvent(
    x: 250, y: 250, deltaX: 0, deltaY: -900))
check(lyricDragCount == 1 &&
      near(dragLyricPanel.frame.minY, 424) &&
      outer.panel.frame == OverlayLayout.outerFrame(for: dragLyricPanel.frame) &&
      controls.panel.frame == OverlayLayout.toolbarFrame(for: dragLyricPanel.frame) &&
      controls.playbackPanel.frame == OverlayLayout.playbackFrame(for: dragLyricPanel.frame),
      "Dragging lyric text cannot move any part of the group off-screen")
dragLyricPanel.orderOut(nil)
outer.follow(lyrics: lyricRect)
controls.follow(overlay: lyricRect)

let rail = WaveformRail()
rail.follow(lyrics: lyricRect)
check(rail.panel.frame == railRect && rail.panel.ignoresMouseEvents &&
      rail.panel.collectionBehavior.contains(.canJoinAllSpaces),
      "Full-width lower region follows lyrics and cannot intercept mouse input")
rail.applyStyle(customStyle)
check(near(rail.content.layer!.backgroundColor!.alpha, 0) &&
      rail.content.layer!.borderWidth == 0,
      "Waveform content draws no third card")
// The rail highlights the whole song: Rust reports position_ms and duration_ms for
// the intro and for every line, and an unknown length must never fake progress.
check(WholeSongProgress.fraction(position_ms: 25_000, duration_ms: 100_000) == 0.25 &&
      WholeSongProgress.fraction(position_ms: 0, duration_ms: 215_000) == 0 &&
      WholeSongProgress.fraction(position_ms: 100_000, duration_ms: 100_000) == 1 &&
      WholeSongProgress.fraction(position_ms: 400_000, duration_ms: 100_000) == 1,
      "Whole-song progress is position over duration, clamped to a full rail")
check(WholeSongProgress.fraction(position_ms: 3_000, duration_ms: nil) == nil &&
      WholeSongProgress.fraction(position_ms: 3_000, duration_ms: 0) == nil,
      "An unknown or zero song length reports no progress instead of a guessed one")
rail.show(fraction: WholeSongProgress.fraction(position_ms: 25_000, duration_ms: 100_000),
          playing: true)
rail.content.layout()
let waveform = rail.content.waveform
check(waveform.isAnimating &&
      waveform.layer!.sublayers!.count >= 80 &&
      waveform.frame.width >= railRect.width - 24,
      "A playing lyric animates a dense waveform along the entire lower region")
check(rail.content.showsProgressTrack &&
      near(rail.content.progressFraction, 0.25) &&
      near(rail.content.progressWidth, rail.content.progressTrackWidth * 0.25),
      "A quarter of the whole song highlights a quarter of the rail, not the current line")
rail.show(fraction: WholeSongProgress.fraction(position_ms: 25_000, duration_ms: 100_000),
          playing: false)
rail.content.layout()
check(!waveform.isAnimating && !waveform.isHidden &&
      rail.content.showsProgressTrack &&
      near(rail.content.progressFraction, 0.25) &&
      near(rail.content.progressWidth, rail.content.progressTrackWidth * 0.25),
      "Pausing freezes the bars and keeps the whole-song position")
rail.show(fraction: WholeSongProgress.fraction(position_ms: 75_000, duration_ms: 100_000),
          playing: true)
rail.content.layout()
check(waveform.isAnimating &&
      near(rail.content.progressFraction, 0.75) &&
      near(rail.content.progressWidth, rail.content.progressTrackWidth * 0.75),
      "A seek moves the whole-song highlight in the same update")
rail.show(fraction: WholeSongProgress.fraction(position_ms: 400_000, duration_ms: 100_000),
          playing: false)
rail.content.layout()
check(!waveform.isAnimating && near(rail.content.progressFraction, 1) &&
      near(rail.content.progressWidth, rail.content.progressTrackWidth) &&
      !waveform.isHidden, "A played-out song clamps to a full rail instead of overflowing")
rail.show(fraction: -1, playing: true)
check(near(rail.content.progressFraction, 0),
      "A nonsense fraction stays bounded instead of drawing outside the rail")
waveform.reduceMotionProvider = { true }
rail.show(fraction: WholeSongProgress.fraction(position_ms: 50_000, duration_ms: 100_000),
          playing: true)
check(!waveform.isAnimating && near(rail.content.progressFraction, 0.5) &&
      rail.content.showsProgressTrack,
      "Reduced Motion freezes the waveform and keeps whole-song progress")
waveform.reduceMotionProvider = { false }
waveform.refreshMotionPreference()
check(waveform.isAnimating, "Waveform resumes after Reduced Motion is disabled")
rail.setVisible(false)
check(!waveform.isAnimating && !rail.panel.isVisible,
      "Hiding the unified overlay stops animation and hides the lower window")
rail.setVisible(true)
check(waveform.isAnimating && rail.panel.isVisible,
      "Showing the group restores the lower panel and playback animation")
rail.show(fraction: WholeSongProgress.fraction(position_ms: 3_000, duration_ms: nil),
          playing: true)
rail.content.layout()
check(!rail.content.showsProgressTrack && near(rail.content.progressWidth, 0) &&
      near(rail.content.progressFraction, 0) && waveform.isAnimating && !waveform.isHidden,
      "An unknown song length hides the progress track but still animates the waveform")
rail.show(fraction: nil, playing: false)
rail.content.layout()
check(!waveform.isAnimating && !waveform.isHidden && !rail.content.showsProgressTrack &&
      near(rail.content.progressWidth, 0),
      "No song leaves a static ambient rail without a running timer or active progress")
check(!WaveformMotion.shouldAnimate(playing: false, reduceMotion: false) &&
      !WaveformMotion.shouldAnimate(playing: true, reduceMotion: true) &&
      WaveformMotion.shouldAnimate(playing: true, reduceMotion: false),
      "Paused and Reduce Motion playback never animates")
outer.follow(lyrics: liveOverlay)
outer.setVisible(true)
rail.follow(lyrics: liveOverlay)
rail.setVisible(true)
controls.follow(overlay: liveOverlay)
controls.setLocked(false)
controls.setVisible(true)
let railCenter = NSPoint(x: rail.panel.frame.midX, y: rail.panel.frame.midY)
let emptyBackground = NSPoint(x: outer.panel.frame.minX + 90,
                              y: outer.panel.frame.maxY - 20)
awaitMouseState("Waveform and empty areas route unlocked clicks to the background") {
    mouseTarget(railCenter) == outer.panel.windowNumber &&
    mouseTarget(emptyBackground) == outer.panel.windowNumber &&
    mouseTarget(clickGap) == outer.panel.windowNumber &&
    mouseTarget(clickPlaybackGap) == outer.panel.windowNumber
}
outer.setLocked(true)
controls.setLocked(true)
awaitMouseState("Locked background passes through while transport and lock still work") {
    mouseTarget(railCenter) != outer.panel.windowNumber &&
    mouseTarget(emptyBackground) != outer.panel.windowNumber &&
    mouseTarget(clickGap) != outer.panel.windowNumber &&
    mouseTarget(clickPlaybackGap) != outer.panel.windowNumber &&
    mouseTarget(lockCenter) == controls.controlPanels[1].windowNumber &&
    (5...7).allSatisfy { index in
        let window = controls.controlPanels[index]
        return mouseTarget(NSPoint(x: window.frame.midX, y: window.frame.midY)) == window.windowNumber
    } &&
    mouseTarget(dragCenter) != controls.controlPanels[0].windowNumber
}
outer.setLocked(false)
controls.setLocked(false)
awaitMouseState("Unlocking immediately restores whole-background hit targets") {
    mouseTarget(emptyBackground) == outer.panel.windowNumber
}
// WindowServer stacking order: the one opaque background must stay behind the lyric
// and waveform panels. Clicking the exposed background ring raised it above both
// same-level panels and hid the lyrics behind the 91%-opaque fill, so assert the
// published window order instead of trusting view or level bookkeeping.
func windowServerOrder(_ windows: [NSWindow]) -> [Int] {
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let wanted = Set(windows.map(\.windowNumber))
    return info.compactMap { entry in
        guard let pid = entry[kCGWindowOwnerPID as String] as? Int, pid == Int(getpid()),
              let number = entry[kCGWindowNumber as String] as? Int, wanted.contains(number) else {
            return nil
        }
        return number
    }
}
func contentAboveBackground() -> Bool {
    let order = windowServerOrder([outer.panel, lyricPanel, rail.panel])
    guard let background = order.firstIndex(of: outer.panel.windowNumber),
          let lyric = order.firstIndex(of: lyricPanel.windowNumber),
          let waveform = order.firstIndex(of: rail.panel.windowNumber) else { return false }
    return lyric < background && waveform < background
}
func awaitStackingOrder(_ message: String) {
    let deadline = Date().addingTimeInterval(2)
    while Date() < deadline {
        if contentAboveBackground() { return }
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
    fatalError(message)
}
// The native AppKit path that reorders windows inside one level: a mouse-down on
// the exposed background ring, followed by a real drag and release.
func dragBackgroundRing() {
    let start = NSPoint(x: outer.panel.frame.minX + 6, y: outer.panel.frame.midY)
    let end = NSPoint(x: start.x + 30, y: start.y - 18)
    let down = NSEvent.mouseEvent(with: .leftMouseDown, location: start, modifierFlags: [],
        timestamp: 0, windowNumber: outer.panel.windowNumber, context: nil, eventNumber: 0,
        clickCount: 1, pressure: 1)!
    let drag = NSEvent.mouseEvent(with: .leftMouseDragged, location: end, modifierFlags: [],
        timestamp: 0.01, windowNumber: outer.panel.windowNumber, context: nil, eventNumber: 1,
        clickCount: 1, pressure: 1)!
    let up = NSEvent.mouseEvent(with: .leftMouseUp, location: end, modifierFlags: [],
        timestamp: 0.02, windowNumber: outer.panel.windowNumber, context: nil, eventNumber: 2,
        clickCount: 1, pressure: 0)!
    outer.panel.sendEvent(down)
    outer.panel.sendEvent(drag)
    outer.panel.sendEvent(up)
}
outer.onDrag = { delta in
    let proposed = lyricPanel.frame.offsetBy(dx: delta.x, dy: delta.y)
    lyricPanel.setFrameOrigin(OverlayLayout.constrainedOrigin(for: proposed, visibleFrames: [screen]))
    outer.follow(lyrics: lyricPanel.frame)
    rail.follow(lyrics: lyricPanel.frame)
}
lyricPanel.setFrameOrigin(liveOverlay.origin)
lyricPanel.orderFrontRegardless()
outer.follow(lyrics: liveOverlay)
rail.follow(lyrics: liveOverlay)
awaitStackingOrder("Lyrics and the waveform start in front of the only background")
for _ in 0..<3 {
    let origin = lyricPanel.frame.origin
    lyricPanel.setFrameOrigin(NSPoint(x: origin.x + 6, y: origin.y - 4))
    outer.follow(lyrics: lyricPanel.frame)
    rail.follow(lyrics: lyricPanel.frame)
}
awaitStackingOrder("Repeated repositioning keeps lyrics and the waveform in front")
dragBackgroundRing()
awaitStackingOrder("Clicking the background never hides lyrics or the waveform behind it")
outer.setLocked(true)
dragBackgroundRing()
awaitStackingOrder("A locked background that passes clicks through still stays behind")
outer.setLocked(false)
rail.setVisible(false)
outer.setVisible(false)
controls.setVisible(false)

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
