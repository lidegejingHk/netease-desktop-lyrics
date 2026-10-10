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
check(baseline.backgroundRGB == "#F6F3EC", "Default background is warm paper")
check(baseline.backgroundOpacity == 0.97, "Default background opacity")
check(baseline.textRGB == "#23262C", "Default text is ink")
check(baseline.chipRGB == "#23262C", "Default text chip is ink")
check(baseline.accentRGB == "#BF4A2E", "Default accent is cinnabar")
check(baseline.chipOpacity == 0, "Default text chip is transparent")
check(baseline.lyricSpacing == 8 && baseline.mainFontSize == 24 && baseline.detailFontSize == 15,
      "Default lyric spacing and font sizes")
check(baseline.showsTitle && baseline.showsWaveform,
      "The optional song title and waveform are on by default")

var edited = baseline
edited.backgroundRGB = "#12ab34"
edited.backgroundOpacity = 0.25
edited.textRGB = "#F0E0D0"
edited.chipRGB = "#345678"
edited.accentRGB = "#0a5cE1"
edited.chipOpacity = 0.6
edited.lyricSpacing = 17
edited.mainFontSize = 30
edited.detailFontSize = 20
edited.showsTitle = false
edited.showsWaveform = false
store.save(edited)
let restored = OverlayStyleStore(defaults: defaults).load()
check(restored.backgroundRGB == "#12AB34", "Normalized hex roundtrip")
check(restored.backgroundOpacity == 0.25, "Background opacity roundtrip")
check(restored.textRGB == "#F0E0D0", "Text color roundtrip")
check(restored.chipRGB == "#345678", "Chip color roundtrip")
check(restored.accentRGB == "#0A5CE1", "Accent colour roundtrip")
check(restored.chipOpacity == 0.6, "Chip opacity roundtrip")
check(restored.lyricSpacing == 17 && restored.mainFontSize == 30 && restored.detailFontSize == 20,
      "Spacing and font size roundtrip")
check(!restored.showsTitle && !restored.showsWaveform,
      "Both optional-element switches roundtrip when switched off")

check(OverlayStyle.rgbHex(NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 0.2)) == "#FF8000", "NSColor to RGB")
check(OverlayStyle.nsColor("#ABCDEF") != nil, "Valid RGB")
check(OverlayStyle.nsColor("#１２ABCD") == nil, "Reject non-ASCII digits")
check(OverlayStyle.nsColor("#12345") == nil, "Reject truncated hex")
check(OverlayStyle.nsColor("red") == nil, "Reject names")

defaults.set("#GG0000", forKey: "overlayStyle.backgroundRGB")
defaults.set("not-a-color", forKey: "overlayStyle.textRGB")
defaults.set("#00000G", forKey: "overlayStyle.chipRGB")
defaults.set("cinnabar", forKey: "overlayStyle.accentRGB")
defaults.set(Double.nan, forKey: "overlayStyle.backgroundOpacity")
defaults.set(1.1, forKey: "overlayStyle.chipOpacity")
let invalid = store.load()
check(invalid.backgroundRGB == baseline.backgroundRGB, "Invalid background fallback")
check(invalid.textRGB == baseline.textRGB, "Invalid text fallback")
check(invalid.chipRGB == baseline.chipRGB, "Invalid chip fallback")
check(invalid.accentRGB == baseline.accentRGB, "Invalid accent fallback")
check(invalid.backgroundOpacity == baseline.backgroundOpacity, "NaN fallback")
check(invalid.chipOpacity == baseline.chipOpacity, "Out of range fallback")

defaults.set(-0.01, forKey: "overlayStyle.backgroundOpacity")
defaults.set(Double.infinity, forKey: "overlayStyle.chipOpacity")
check(store.load().backgroundOpacity == baseline.backgroundOpacity, "Negative fallback")
check(store.load().chipOpacity == baseline.chipOpacity, "Infinity fallback")
defaults.set(true, forKey: "overlayStyle.backgroundOpacity")
check(store.load().backgroundOpacity == baseline.backgroundOpacity, "Boolean opacity fallback")
defaults.set(41.0, forKey: "overlayStyle.lyricSpacing")
defaults.set(13.0, forKey: "overlayStyle.mainFontSize")
defaults.set(Double.nan, forKey: "overlayStyle.detailFontSize")
let invalidNumbers = store.load()
check(invalidNumbers.lyricSpacing == baseline.lyricSpacing &&
      invalidNumbers.mainFontSize == baseline.mainFontSize &&
      invalidNumbers.detailFontSize == baseline.detailFontSize,
      "Spacing and font sizes outside their ranges fall back instead of clamping")
defaults.set(true, forKey: "overlayStyle.mainFontSize")
check(store.load().mainFontSize == baseline.mainFontSize, "Boolean font size fallback")
defaults.set(1, forKey: "overlayStyle.showsTitle")
defaults.set("no", forKey: "overlayStyle.showsWaveform")
check(store.load().showsTitle && store.load().showsWaveform,
      "A non-boolean switch value falls back to the visible default")

// Tool actions stay above; transport sits between lyrics and waveform on one background.
let lyricRect = NSRect(x: 116, y: 180, width: 848, height: 126)
let screen = NSRect(x: 0, y: 0, width: 1000, height: 600)
let outerRect = OverlayLayout.outerFrame(for: lyricRect)
let toolbarRect = OverlayLayout.toolbarFrame(for: lyricRect)
let playbackRect = OverlayLayout.playbackFrame(for: lyricRect)
let railRect = OverlayLayout.railFrame(for: lyricRect)
let envelope = OverlayLayout.envelope(for: lyricRect)
check(OverlayLayout.lyricSize == lyricRect.size &&
      outerRect == NSRect(x: 100, y: 136, width: 880, height: 220),
      "One compact 880×220 background encloses all four content zones")
check(toolbarRect == NSRect(x: 844, y: 310, width: 120, height: 36) &&
      near(toolbarRect.minY - lyricRect.maxY, 4) && outerRect.contains(toolbarRect),
      "Only placement and appearance tools occupy the compact top-right row")
check(playbackRect == NSRect(x: 474, y: 312, width: 132, height: 32) &&
      near(playbackRect.midY, toolbarRect.midY) &&
      near(playbackRect.midX, outerRect.midX) && outerRect.contains(playbackRect),
      "Transport is centered in the top row, on the same line as the tools")
check(railRect == NSRect(x: 124, y: 148, width: 832, height: 28) &&
      near(lyricRect.minY - railRect.maxY, 4) && outerRect.contains(railRect),
      "The full-width waveform sits four points beneath the lyric band")
check(outerRect.contains(lyricRect) && envelope == outerRect &&
      !toolbarRect.intersects(lyricRect) && !railRect.intersects(lyricRect) &&
      !playbackRect.intersects(lyricRect) && !playbackRect.intersects(railRect) &&
      !playbackRect.intersects(toolbarRect),
      "Tools, text, transport and waveform do not overlap")
check(ToolbarPlacement.origin(overlay: lyricRect,
                              size: OverlayLayout.toolbarSize) == toolbarRect.origin,
      "Toolbar placement uses the enclosing frame's top-right inset")
let titleRect = OverlayLayout.titleFrame(for: lyricRect)
check(near(titleRect.minX, outerRect.minX + 24) &&
      near(titleRect.maxX, playbackRect.minX - 12) &&
      near(titleRect.midY, toolbarRect.midY) &&
      outerRect.contains(titleRect) &&
      !titleRect.intersects(toolbarRect) && !titleRect.intersects(lyricRect) &&
      !titleRect.intersects(railRect) && !titleRect.intersects(playbackRect),
      "The single-line song title shares the top row and never reaches transport or tools")
let secondScreen = NSRect(x: 1000, y: -200, width: 1200, height: 700)
let pinned = OverlayLayout.snappedRightOrigin(for: lyricRect, visibleFrames: [screen])
let pinnedGroup = OverlayLayout.envelope(for: NSRect(origin: pinned, size: lyricRect.size))
check(near(pinnedGroup.maxX, screen.maxX - OverlayVisibility.snapMargin) &&
      near(pinnedGroup.minY, envelope.minY),
      "Pinning keeps the whole group on the display's right edge without moving it vertically")
let pinnedElsewhere = OverlayLayout.snappedRightOrigin(
    for: lyricRect.offsetBy(dx: 1100, dy: -20), visibleFrames: [screen, secondScreen])
check(near(OverlayLayout.envelope(for: NSRect(origin: pinnedElsewhere,
                                              size: lyricRect.size)).maxX,
           secondScreen.maxX - OverlayVisibility.snapMargin),
      "A group on another display pins to that display's right edge")
let narrowScreen = NSRect(x: 0, y: 0, width: 700, height: 600)
check(OverlayLayout.envelope(for: NSRect(
        origin: OverlayLayout.snappedRightOrigin(for: lyricRect, visibleFrames: [narrowScreen]),
        size: lyricRect.size)).maxX <= narrowScreen.maxX,
      "A display narrower than the group still pins the right edge inside the screen")
check(OverlayVisibility.origin(for: envelope, visibleFrames: [screen]) == envelope.origin,
      "Keep the complete framed group on screen without jumping")
let rescued = OverlayVisibility.origin(
    for: envelope.offsetBy(dx: 1200, dy: 700), visibleFrames: [screen])
check(near(rescued.x, 120) && near(rescued.y, 380),
      "A disconnected screen recovers the whole enclosing frame")
let clippedLyric = lyricRect.offsetBy(dx: -140, dy: -140)
let corrected = OverlayLayout.constrainedOrigin(for: clippedLyric, visibleFrames: [screen])
check(near(corrected.x, 16) && near(corrected.y, 44),
      "Dragging clips the outer frame before losing its toolbar or lower waveform")
let topEdge = OverlayVisibility.origin(
    for: envelope.offsetBy(dx: 80, dy: 450), visibleFrames: [screen])
check(near(topEdge.y, 380), "Screen top reserves room for the framed toolbar")
let secondEnvelope = envelope.offsetBy(dx: 1100, dy: -20)
check(OverlayVisibility.origin(for: secondEnvelope,
                               visibleFrames: [screen, secondScreen]) == secondEnvelope.origin,
      "A framed group on another display retains its placement")

// The band hugs the lyrics, so a taller or shorter region keeps the same rhythm
// between the top row, the transport keys and the waveform.
let tallLyricRect = NSRect(x: lyricRect.minX, y: lyricRect.minY,
                           width: lyricRect.width, height: 180)
let tallOuter = OverlayLayout.outerFrame(for: tallLyricRect)
check(tallOuter == NSRect(x: 100, y: 136, width: 880, height: 274) &&
      near(OverlayLayout.toolbarFrame(for: tallLyricRect).minY - tallLyricRect.maxY, 4) &&
      near(OverlayLayout.playbackFrame(for: tallLyricRect).midY,
           OverlayLayout.toolbarFrame(for: tallLyricRect).midY) &&
      near(tallLyricRect.minY - OverlayLayout.railFrame(for: tallLyricRect).maxY, 4) &&
      near(OverlayLayout.railFrame(for: tallLyricRect).minY - tallOuter.minY, 12),
      "A taller lyric band moves the lower edge without breaking the rhythm")
let shortLyricRect = NSRect(x: lyricRect.minX, y: lyricRect.minY,
                            width: lyricRect.width, height: 46)
check(near(OverlayLayout.outerFrame(for: shortLyricRect).height, 140) &&
      near(OverlayLayout.toolbarFrame(for: shortLyricRect).minY - shortLyricRect.maxY, 4) &&
      OverlayLayout.outerFrame(for: shortLyricRect)
          .contains(OverlayLayout.railFrame(for: shortLyricRect)),
      "A short band shrinks the background without losing the lower rail")
check(OverlayLayout.clampedBandHeight(10) == 40 && OverlayLayout.clampedBandHeight(90) == 90 &&
      OverlayLayout.clampedBandHeight(999) == 320 &&
      OverlayLayout.clampedBandHeight(.nan) == OverlayLayout.lyricSize.height,
      "Measured band heights stay inside their guard rails")

// The pointer alone decides whether the controls exist: the whole background is
// the target, and a short grace period keeps a grazing pointer from flickering.
var reveal = OverlayHover()
check(OverlayHover.inside(point: NSPoint(x: envelope.midX, y: envelope.midY),
                          envelope: envelope) &&
      OverlayHover.inside(point: NSPoint(x: envelope.minX - 4, y: envelope.minY - 4),
                          envelope: envelope) &&
      !OverlayHover.inside(point: NSPoint(x: envelope.minX - 20, y: envelope.midY),
                           envelope: envelope),
      "Hover covers the complete overlay with a small forgiving margin")
check(reveal.update(now: 0, inside: true) &&
      reveal.update(now: 1, inside: false) &&
      reveal.update(now: 1.2, inside: false) &&
      !reveal.update(now: 1.5, inside: false),
      "Leaving hides the controls only after the grace period")
check(reveal.update(now: 2, inside: true) && reveal.controlsVisible,
      "Re-entering the overlay reveals the controls immediately")

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
check(controls.controlPanels.count == 6 &&
      controls.controlPanels.allSatisfy {
          !$0.hasShadow && !$0.isOpaque && !$0.hidesOnDeactivate &&
          $0.collectionBehavior.contains(.canJoinAllSpaces) && $0.animationBehavior == .none
      },
      "Only individual control icon windows can receive clicks")
controls.setVisible(true)
controls.setControlsVisible(false)
check(!controls.panel.isVisible && !controls.playbackPanel.isVisible &&
      controls.controlPanels.allSatisfy { !$0.isVisible },
      "A pointer outside the overlay removes the tools and the transport keys")
controls.setControlsVisible(true)
check(controls.playbackPanel.isVisible && (3...5).allSatisfy { controls.controlPanels[$0].isVisible },
      "Coming back reveals the transport keys again")
controls.setControlsVisible(false)
check(controls.controlPanels.allSatisfy { !$0.isVisible },
      "Hidden controls leave only the lyric and the waveform")
controls.setControlsVisible(true)
check(controls.controlPanels.allSatisfy { $0.isVisible },
      "Coming back reveals the tools and the transport keys together")
controls.setVisible(false)
controls.follow(overlay: lyricRect)
check(controls.panel.frame == toolbarRect && controls.playbackPanel.frame == playbackRect &&
      (0...2).allSatisfy { controls.panel.frame.contains(controls.controlPanels[$0].frame) } &&
      (3...5).allSatisfy { controls.playbackPanel.frame.contains(controls.controlPanels[$0].frame) },
      "Three tools occupy the upper-right row and three transport buttons sit beneath lyrics")
check((3...5).allSatisfy { near(controls.controlPanels[$0].frame.midY, playbackRect.midY) } &&
      near(controls.controlPanels[4].frame.midX, outerRect.midX) &&
      controls.controlPanels[3].frame.maxX < controls.controlPanels[4].frame.minX &&
      controls.controlPanels[4].frame.maxX < controls.controlPanels[5].frame.minX &&
      controls.controlPanels[4].frame.size == NSSize(width: 38, height: 32) &&
      controls.controlPanels[3].frame.size == NSSize(width: 34, height: 30) &&
      controls.controlPanels[5].frame.size == NSSize(width: 34, height: 30),
      "Playback trio is centered with a slightly larger middle button and ten-point gaps")
check(controls.controlPanels[3].contentView!.accessibilityLabel() == "上一首" &&
      controls.controlPanels[5].contentView!.accessibilityLabel() == "下一首",
      "Transport controls have accessible names")
controls.setPlaybackAvailability(previous: false, toggle: .unavailable, next: false)
check([3, 4, 5].allSatisfy {
    !(controls.controlPanels[$0].contentView! as! NSButton).isEnabled &&
    controls.controlPanels[$0].ignoresMouseEvents
}, "Unavailable transport icons remain visible but cannot intercept desktop input")
controls.setPlaybackAvailability(previous: true, toggle: .pause, next: true)
check([3, 4, 5].allSatisfy { (controls.controlPanels[$0].contentView! as! NSButton).isEnabled } &&
      (3...5).allSatisfy { !controls.controlPanels[$0].ignoresMouseEvents } &&
      controls.controlPanels[4].contentView!.accessibilityLabel() == "暂停",
      "An available playing state exposes a pause control")
let styledToolbar = OverlayStyle(backgroundRGB: "#112233", textRGB: "#20CF80", chipRGB: "#000000",
                                 backgroundOpacity: 0.3, chipOpacity: 0.5,
                                 lyricSpacing: 8, mainFontSize: 24, detailFontSize: 15)
controls.applyStyle(styledToolbar)
check(near(controls.panel.contentView!.layer!.backgroundColor!.alpha, 0) &&
      near(controls.playbackPanel.contentView!.layer!.backgroundColor!.alpha, 0) &&
      (controls.controlPanels[4].contentView! as! NSButton).contentTintColor!.alphaComponent >
      (controls.controlPanels[3].contentView! as! NSButton).contentTintColor!.alphaComponent,
      "Separated groups share tint, with a brighter middle button and no second card")
check(controls.controlPanels.compactMap { $0.contentView as? NSButton }
    .allSatisfy { OverlayStyle.rgbHex($0.contentTintColor!) == "#20CF80" },
      "All toolbar icons follow the lyric text color")
func movementEvent(x: CGFloat, y: CGFloat, deltaX: Int64, deltaY: Int64) -> NSEvent {
    let cgEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged,
                          mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)!
    cgEvent.setIntegerValueField(.mouseEventDeltaX, value: deltaX)
    cgEvent.setIntegerValueField(.mouseEventDeltaY, value: deltaY)
    return NSEvent(cgEvent: cgEvent)!
}
var tappedLock = 0
var tappedSettings = 0
var tappedPin = 0
controls.onToggleLock = { tappedLock += 1 }
controls.onToggleSettings = { tappedSettings += 1 }
controls.onSnapRight = { tappedPin += 1 }
var tappedPrevious = 0
var tappedPlayback = 0
var tappedNext = 0
controls.onPrevious = { tappedPrevious += 1 }
controls.onTogglePlayback = { tappedPlayback += 1 }
controls.onNext = { tappedNext += 1 }
let toolbarButtons = controls.controlPanels.compactMap { $0.contentView as? NSButton }
toolbarButtons.first(where: { $0.accessibilityLabel() == "锁定歌词位置" })!.performClick(nil)
toolbarButtons.first(where: { $0.accessibilityLabel() == "设置歌词样式" })!.performClick(nil)
toolbarButtons.first(where: { $0.accessibilityLabel() == "吸附到屏幕右边" })!.performClick(nil)
check(tappedLock == 1 && tappedSettings == 1 && tappedPin == 1,
      "Toolbar actions dispatch to their owning controller")
for index in [3, 4, 5] { (controls.controlPanels[index].contentView! as! NSButton).performClick(nil) }
check(tappedPrevious == 1 && tappedPlayback == 1 && tappedNext == 1,
      "All three transport controls dispatch to their controller")
controls.setPlaybackAvailability(previous: false, toggle: .unavailable, next: false)
for index in [3, 4, 5] { (controls.controlPanels[index].contentView! as! NSButton).performClick(nil) }
check(tappedPrevious == 1 && tappedPlayback == 1 && tappedNext == 1 &&
      (3...5).allSatisfy { controls.controlPanels[$0].ignoresMouseEvents },
      "Unavailable transport controls cannot dispatch actions")
controls.setLocked(true)
check((0...2).allSatisfy { !controls.controlPanels[$0].ignoresMouseEvents } &&
      (3...5).allSatisfy { controls.controlPanels[$0].ignoresMouseEvents },
      "Lock keeps every tool interactive while disabled transport passes clicks through")
toolbarButtons.first(where: { $0.accessibilityLabel() == "吸附到屏幕右边" })!.performClick(nil)
check(tappedPin == 2 && !controls.controlPanels[2].ignoresMouseEvents,
      "The locked pin stays clickable and dispatches its own action")
controls.setPlaybackAvailability(previous: true, toggle: .play, next: true)
for index in [3, 4, 5] { (controls.controlPanels[index].contentView! as! NSButton).performClick(nil) }
check(tappedPrevious == 2 && tappedPlayback == 2 && tappedNext == 2,
      "A locked, pinned tool row leaves the transport keys operational")
controls.follow(overlay: lyricRect)
check(controls.panel.frame == toolbarRect &&
      controls.panel.frame.size == OverlayLayout.toolbarSize,
      "The pinned tool row keeps its upper-right geometry")
check(controls.panel.frame == toolbarRect && controls.playbackPanel.frame == playbackRect &&
      !controls.panel.frame.intersects(lyricRect) &&
      !controls.playbackPanel.frame.intersects(lyricRect),
      "Both icon rows follow the lyrics without stealing lyric space")
controls.setVisible(true)
controls.setPlaybackAvailability(previous: true, toggle: .pause, next: true)
let activeWindows = controls.controlPanels.filter(\.isVisible)
check(activeWindows.count == 6 &&
      (0...2).allSatisfy { controls.controlPanels[$0].isVisible } &&
      (3...5).allSatisfy { controls.controlPanels[$0].isVisible } &&
      controls.playbackPanel.isVisible,
      "Both groups expose six small hit windows rather than one large panel")
check(activeWindows.allSatisfy { !$0.ignoresMouseEvents }, "Icon panels remain interactive")
let gap = NSPoint(x: controls.panel.frame.minX + 41, y: controls.panel.frame.minY + 18)
let playbackGap = NSPoint(x: controls.playbackPanel.frame.minX + 42,
                          y: controls.playbackPanel.frame.midY)
check(controls.panel.frame.contains(gap) && controls.playbackPanel.frame.contains(playbackGap) &&
      !activeWindows.contains(where: { $0.frame.contains(gap) || $0.frame.contains(playbackGap) }),
      "Both transparent icon gaps contain no mouse-intercepting window")
check(near(controls.controlPanels[2].frame.maxX, controls.panel.frame.maxX - 3) &&
      near(controls.controlPanels[0].frame.minX, controls.panel.frame.minX + 3),
      "The pin hit window closes the tool row on its unchanged right margin")
check(near(controls.controlPanels[2].frame.minY, controls.panel.frame.minY + 2),
      "The pin hit window stays vertically centered like the other tools")
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
func everyControlReceivesClicks() -> Bool {
    controls.controlPanels.allSatisfy { window in
        mouseTarget(NSPoint(x: window.frame.midX, y: window.frame.midY)) == window.windowNumber
    }
}
let lockCenter = NSPoint(x: controls.controlPanels[0].frame.midX,
                         y: controls.controlPanels[0].frame.midY)
awaitMouseState("Both icon rows receive clicks; their gaps are click-through") {
    everyControlReceivesClicks() &&
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
let countsBeforeEvents = (tappedLock, tappedSettings, tappedPin)
sendPanelClick(controls.controlPanels[0])
sendPanelClick(controls.controlPanels[1])
sendPanelClick(controls.controlPanels[2])
check(tappedLock == countsBeforeEvents.0 + 1 &&
      tappedSettings == countsBeforeEvents.1 + 1 &&
      tappedPin == countsBeforeEvents.2 + 1,
      "Native button-window mouse events dispatch lock, style, and pin actions")
controls.setVisible(false)
awaitMouseState("Hidden controls leave no mouse targets over the desktop") {
    mouseTarget(lockCenter) != controls.controlPanels[0].windowNumber &&
    mouseTarget(NSPoint(x: controls.controlPanels[4].frame.midX,
                        y: controls.controlPanels[4].frame.midY)) != controls.controlPanels[4].windowNumber
}
controls.setVisible(true)
awaitMouseState("Buttons work immediately after showing the toolbar again") {
    everyControlReceivesClicks() && mouseTarget(clickGap) != controls.panel.windowNumber
}
let pinPanel = controls.controlPanels[2]
awaitMouseState("The pin control keeps a real mouse target beside the other tools") {
    mouseTarget(NSPoint(x: pinPanel.frame.midX, y: pinPanel.frame.midY)) == pinPanel.windowNumber &&
    everyControlReceivesClicks()
}
controls.setLocked(true)
lyricPanel.ignoresMouseEvents = true
awaitMouseState("Locked lyrics pass clicks through, but lock stays clickable") {
    mouseTarget(lockCenter) == controls.controlPanels[0].windowNumber &&
    (3...5).allSatisfy { index in
        let window = controls.controlPanels[index]
        return mouseTarget(NSPoint(x: window.frame.midX, y: window.frame.midY)) == window.windowNumber
    } &&
    mouseTarget(clickGap) != controls.panel.windowNumber &&
    mouseTarget(clickPlaybackGap) != controls.playbackPanel.windowNumber
}
controls.setPlaybackAvailability(previous: false, toggle: .unavailable, next: false)
awaitMouseState("Locked disabled transport remains visible without blocking underlying apps") {
    (3...5).allSatisfy { index in
        let window = controls.controlPanels[index]
        return window.isVisible && window.ignoresMouseEvents &&
            mouseTarget(NSPoint(x: window.frame.midX, y: window.frame.midY)) != window.windowNumber
    } && mouseTarget(lockCenter) == controls.controlPanels[0].windowNumber
}
controls.setPlaybackAvailability(previous: true, toggle: .pause, next: true)
awaitMouseState("Re-enabled transport immediately accepts clicks after locked pass-through") {
    (3...5).allSatisfy { index in
        let window = controls.controlPanels[index]
        return mouseTarget(NSPoint(x: window.frame.midX, y: window.frame.midY)) == window.windowNumber
    }
}
controls.setVisible(false)
lyricPanel.orderOut(nil)

controls.setLocked(false)

let outer = OverlayFrame()
outer.follow(lyrics: lyricRect)
check(outer.panel.level.rawValue > NSWindow.Level.normal.rawValue &&
      outer.panel.level.rawValue < NSWindow.Level.floating.rawValue,
      "The background must stay below floating lyric and waveform windows during every drag")
check(outer.panel.frame == outerRect && !outer.panel.ignoresMouseEvents &&
      outer.panel.contentView!.layer!.cornerRadius == 21,
      "The unified outer frame accepts pointer input when unlocked")
outer.show(title: nil)
check(outer.titleView.isHidden && outer.titleView.text.isEmpty,
      "No verified title leaves the top-left row empty")
outer.show(title: "   ")
check(outer.titleView.isHidden && outer.titleView.text.isEmpty,
      "A blank title is never drawn")
outer.titleView.reduceMotionProvider = { false }
outer.show(title: "短歌名")
let titleWindowRect = outer.titleView.frame
    .offsetBy(dx: outer.panel.frame.minX, dy: outer.panel.frame.minY)
check(!outer.titleView.isHidden && !outer.titleView.isScrolling &&
      titleWindowRect == OverlayLayout.titleFrame(for: lyricRect) &&
      !titleWindowRect.intersects(playbackRect) && !titleWindowRect.intersects(toolbarRect),
      "A fitting title rests inside the reserved top row without touching transport or tools")
outer.show(title: String(repeating: "很长的合成歌名", count: 20))
check(outer.titleView.isScrolling &&
      !outer.titleView.frame.offsetBy(dx: outer.panel.frame.minX,
                                      dy: outer.panel.frame.minY).intersects(playbackRect),
      "A long title scrolls inside its single reserved line instead of covering the transport")
check(outer.titleView.accessibilityLabel() == outer.titleView.text &&
      outer.titleView.text.hasPrefix("很长的合成歌名"),
      "Assistive technology reads the whole single-line title")
let marqueeDistance = outer.titleView.scrollDistance
check(marqueeDistance > outer.titleView.bounds.width,
      "The marquee loop is longer than the visible row")
outer.titleView.advance(by: 1)
let scrolledOnce = outer.titleView.scrollOffset
check(near(scrolledOnce, MarqueeTitleView.pointsPerSecond),
      "One second of marquee moves the title by the slow configured speed")
outer.titleView.advance(by: TimeInterval(marqueeDistance / MarqueeTitleView.pointsPerSecond))
check(near(outer.titleView.scrollOffset, scrolledOnce),
      "A full loop period puts the copies back where the scroll started")
outer.titleView.reduceMotionProvider = { true }
check(!outer.titleView.isScrolling && outer.titleView.scrollOffset == 0,
      "Reduce Motion turns the marquee back into a still line")
outer.titleView.reduceMotionProvider = { false }
outer.setTitleVisible(false)
check(outer.titleView.isHidden, "Leaving the overlay hides the verified title")
outer.setTitleVisible(true)
check(!outer.titleView.isHidden, "Re-entering the overlay restores the verified title")
var titleOffStyle = OverlayStyle.defaultValue
titleOffStyle.showsTitle = false
outer.applyStyle(titleOffStyle)
check(outer.titleView.isHidden && !outer.titleView.text.isEmpty,
      "Switching the song title off hides the row without discarding the verified name")
outer.applyStyle(.defaultValue)
check(!outer.titleView.isHidden, "Switching the song title back on restores the same row")
let titlePoint = NSPoint(x: outer.titleView.frame.midX, y: outer.titleView.frame.midY)
check(outer.titleView.hitTest(NSPoint(x: outer.titleView.bounds.midX,
                                      y: outer.titleView.bounds.midY)) == nil &&
      outer.panel.contentView!.hitTest(titlePoint) === outer.panel.contentView,
      "The title never takes over dragging from the blank background")
var transparentSurface = OverlayStyle.defaultValue
transparentSurface.backgroundOpacity = 0
outer.applyStyle(transparentSurface)
check(near(outer.panel.contentView!.layer!.backgroundColor!.alpha, 0) &&
      near(NSColor(cgColor: outer.panel.contentView!.layer!.borderColor!)!.alphaComponent, 0),
      "A fully transparent background draws no rim either")
outer.applyStyle(.defaultValue)
check(NSColor(cgColor: outer.panel.contentView!.layer!.borderColor!)!.alphaComponent > 0,
      "The rim returns with an opaque background")
let lyricView = LyricsView(frame: NSRect(origin: .zero, size: OverlayLayout.lyricSize))
let customStyle = OverlayStyle(backgroundRGB: "#123456", textRGB: "#F0E0D0",
                               chipRGB: "#112233", backgroundOpacity: 0.15, chipOpacity: 0.55,
                               lyricSpacing: 8, mainFontSize: 24, detailFontSize: 15)
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
dragLyricPanel.setFrameOrigin(lyricRect.origin)
outer.follow(lyrics: lyricRect)
backgroundDragCount = 0
// Both events exist before either callback moves the panel: queued deltas must
// stay independent of the window position each callback leaves behind.
outer.panel.contentView!.mouseDragged(with: movementEvent(x: 140, y: 290, deltaX: -20, deltaY: -15))
outer.panel.contentView!.mouseDragged(with: movementEvent(x: 155, y: 300, deltaX: -15, deltaY: 10))
check(backgroundDragCount == 2 &&
      near(dragLyricPanel.frame.minX, lyricRect.minX - 35) &&
      near(dragLyricPanel.frame.minY, lyricRect.minY + 5),
      "Queued drag events move by their independent deltas, not moving-window coordinates")
let backgroundDragsBeforeClamp = backgroundDragCount
outer.panel.contentView!.mouseDragged(with: movementEvent(
    x: 240, y: 215, deltaX: 0, deltaY: -900))
check(backgroundDragCount == backgroundDragsBeforeClamp + 1 &&
      near(dragLyricPanel.frame.minX, lyricRect.minX - 35) &&
      near(dragLyricPanel.frame.minY, 424) &&
      outer.panel.frame == OverlayLayout.outerFrame(for: dragLyricPanel.frame),
      "Blank-background drag keeps the complete group within visible bounds")
outer.follow(lyrics: lyricRect)
controls.follow(overlay: lyricRect)
lyricView.show(primary: "合成歌词", secondary: "合成副句")
lyricView.layout()
check(near(lyricView.layer!.backgroundColor!.alpha, 0) &&
      lyricView.layer!.borderWidth == 0, "Lyric area draws no second card")
check(lyricView.subviews.count == 5 &&
      !lyricView.subviews[0].isHidden && !lyricView.subviews[1].isHidden &&
      !lyricView.subviews[4].isHidden,
      "The lyric lines, their backings and the sweep layer share the center region")
check(near(lyricView.subviews[0].layer!.backgroundColor!.alpha, 0.55), "Live chip alpha")
let primaryLabel = lyricView.subviews[2] as! NSTextField
let detailLabel = lyricView.subviews[3] as! NSTextField
let primaryChip = lyricView.subviews[0]
let detailChip = lyricView.subviews[1]
check(near(primaryLabel.frame.midX, lyricView.bounds.midX) &&
      near(detailLabel.frame.midX, lyricView.bounds.midX) &&
      near(primaryChip.frame.midX, lyricView.bounds.midX) &&
      near(detailChip.frame.midX, lyricView.bounds.midX) &&
      near(lyricView.subviews[4].frame.midX, lyricView.bounds.midX) &&
      near(lyricView.subviews[4].frame.minY, primaryLabel.frame.minY) &&
      near(lyricView.subviews[4].frame.height, primaryLabel.frame.height),
      "Both lyric lines, their backings and the sweep row center on the window width")
lyricView.applyStyle(.defaultValue)
lyricView.layout()
check(primaryChip.isHidden && detailChip.isHidden,
      "Default text background is transparent")
lyricView.show(primary: "等待网易云音乐…", secondary: "")
lyricView.layout()
check(near(primaryLabel.frame.minY, CGFloat(OverlayStyle.defaultValue.lyricSpacing)) &&
      near(lyricView.desiredBandHeight,
           primaryLabel.frame.height + 2 * CGFloat(OverlayStyle.defaultValue.lyricSpacing)) &&
      detailLabel.isHidden && detailChip.isHidden,
      "A lone status line hugs the bottom of a band that matches its own height")

// Spacing and font sizes are settings, so the band follows them instead of a
// constant: the same pair of lines reports a taller band after either change.
var airyStyle = OverlayStyle.defaultValue
airyStyle.lyricSpacing = 30
lyricView.applyStyle(airyStyle)
lyricView.show(primary: "合成歌词", secondary: "合成副句")
lyricView.layout()
let huggingHeight = primaryLabel.frame.height + detailLabel.frame.height + LyricStack.gap
check(near(lyricView.desiredBandHeight, huggingHeight + 60) &&
      near(primaryLabel.frame.minY - detailLabel.frame.maxY, LyricStack.gap) &&
      near(detailLabel.frame.minY, 30),
      "Equal spacing above and below follows the spacing setting")
lyricView.setFrameSize(NSSize(width: lyricView.bounds.width,
                              height: lyricView.desiredBandHeight))
lyricView.layout()
check(near(primaryLabel.frame.maxY, lyricView.bounds.maxY - 30),
      "A resized band keeps the same air above the visible pair")
var largeFontStyle = OverlayStyle.defaultValue
largeFontStyle.mainFontSize = 34
largeFontStyle.detailFontSize = 22
lyricView.applyStyle(largeFontStyle)
lyricView.show(primary: "合成歌词", secondary: "合成副句")
lyricView.layout()
check(near(primaryLabel.font!.pointSize, 34) && near(detailLabel.font!.pointSize, 22) &&
      lyricView.desiredBandHeight > huggingHeight,
      "Selected font sizes drive both the drawn text and the band height")
var smallFontStyle = OverlayStyle.defaultValue
smallFontStyle.mainFontSize = 14
lyricView.applyStyle(smallFontStyle)
lyricView.show(primary: String(repeating: "特别长的合成歌词", count: 200), secondary: "")
lyricView.layout()
check(near(primaryLabel.font!.pointSize, 14) && primaryLabel.stringValue.hasSuffix("…"),
      "The shrink floor never rises above the selected font size")
lyricView.setFrameSize(NSRect(origin: .zero, size: OverlayLayout.lyricSize).size)
lyricView.applyStyle(.defaultValue)

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
check(near(primaryLabel.frame.minY - detailLabel.frame.maxY, 12) &&
      detailLabel.frame.minY >= 4 && primaryLabel.frame.maxY <= lyricView.bounds.maxY - 4,
      "Shrunken wrapped lines keep the tight gap inside the lyric band")
check(primaryLabel.frame.minY > detailLabel.frame.maxY &&
      primaryChip.frame.maxX <= lyricView.bounds.maxX - 24 &&
      detailChip.frame.maxX <= lyricView.bounds.maxX - 24 &&
      near(playbackRect.midY, toolbarRect.midY),
      "Separate rows and their backgrounds never overlap or leave the lyric frame")
check(near(primaryLabel.frame.minY - detailLabel.frame.maxY, 12) &&
      detailLabel.frame.minY >= 4 && detailChip.frame.minY >= 4,
      "The two visible lyric lines sit close together without reaching the playback row")
lyricView.show(primary: "较短的主句", secondary: "短副句")
lyricView.layout()
check(near(primaryLabel.frame.minY - detailLabel.frame.maxY, 12) &&
      detailLabel.frame.minY >= 4 &&
      near(primaryLabel.frame.midX, lyricView.bounds.midX) &&
      near(detailLabel.frame.midX, lyricView.bounds.midX),
      "Short lines keep the same tight gap as wrapped lines")
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
var waveformOffStyle = OverlayStyle.defaultValue
waveformOffStyle.showsWaveform = false
rail.applyStyle(waveformOffStyle)
check(!rail.panel.isVisible && !waveform.isAnimating,
      "Switching the waveform off hides the lower panel and stops its animation")
rail.applyStyle(.defaultValue)
check(rail.panel.isVisible && waveform.isAnimating,
      "Switching the waveform back on restores the lower panel and its motion")
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
    mouseTarget(lockCenter) == controls.controlPanels[0].windowNumber &&
    (3...5).allSatisfy { index in
        let window = controls.controlPanels[index]
        return mouseTarget(NSPoint(x: window.frame.midX, y: window.frame.midY)) == window.windowNumber
    }
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
check(wells.count == 4 && sliders.count == 5 &&
      wells.contains { $0.accessibilityLabel() == "强调颜色" },
      "Colours, opacity, spacing and both font sizes are adjustable")
check(sliders.contains(where: { $0.accessibilityLabel() == "浮层背景不透明度" }),
      "Opacity labels describe the actual slider semantics")
let toggleBoxes = settings.panel.contentView!.subviews.compactMap { $0 as? NSButton }
    .filter { $0.title == "显示歌曲名" || $0.title == "显示声浪" }
check(toggleBoxes.count == 2 && toggleBoxes.allSatisfy { $0.state == .on },
      "The optional song title and waveform start switched on")
check(toggleBoxes.allSatisfy { $0.accessibilityLabel() == $0.title },
      "Both optional-element switches carry accessible names")
let switchRects = toggleBoxes.map(\.frame)
check(settings.panel.contentView!.subviews.allSatisfy { view in
        switchRects.allSatisfy { settings.panel.contentView!.bounds.contains($0) } &&
        (toggleBoxes.contains(where: { $0 === view }) ||
         switchRects.allSatisfy { !view.frame.intersects($0) })
      },
      "Both switches fit the panel without covering an appearance control")
let spacingSlider = sliders.first(where: { $0.accessibilityLabel() == "歌词上下留白" })!
let mainFontSizeSlider = sliders.first(where: { $0.accessibilityLabel() == "歌词字号" })!
let detailFontSizeSlider = sliders.first(where: { $0.accessibilityLabel() == "翻译字号" })!
check(spacingSlider.minValue == OverlayStyle.spacingRange.lowerBound &&
      spacingSlider.maxValue == OverlayStyle.spacingRange.upperBound &&
      mainFontSizeSlider.minValue == OverlayStyle.mainFontRange.lowerBound &&
      mainFontSizeSlider.maxValue == OverlayStyle.mainFontRange.upperBound &&
      detailFontSizeSlider.minValue == OverlayStyle.detailFontRange.lowerBound &&
      detailFontSizeSlider.maxValue == OverlayStyle.detailFontRange.upperBound,
      "Every slider exposes the stored range it validates against")
check((spacingSlider.doubleValue, mainFontSizeSlider.doubleValue,
       detailFontSizeSlider.doubleValue) == (8, 24, 15),
      "The panel opens on the same defaults the store falls back to")
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
spacingSlider.doubleValue = 22
deliverChange(spacingSlider)
check(sentStyle?.lyricSpacing == 22, "Spacing sends live update")
mainFontSizeSlider.doubleValue = 31
deliverChange(mainFontSizeSlider)
check(sentStyle?.mainFontSize == 31, "Main font size sends live update")
detailFontSizeSlider.doubleValue = 19
deliverChange(detailFontSizeSlider)
check(sentStyle?.detailFontSize == 19, "Secondary font size sends live update")
let titleToggle = toggleBoxes.first(where: { $0.title == "显示歌曲名" })!
titleToggle.state = .off
deliverChange(titleToggle)
check(sentStyle?.showsTitle == false, "Switching the song title off reaches the overlay live")
let waveformToggle = toggleBoxes.first(where: { $0.title == "显示声浪" })!
waveformToggle.state = .off
deliverChange(waveformToggle)
check(sentStyle?.showsWaveform == false, "Switching the waveform off reaches the overlay live")
settings.panel.contentView!.subviews.compactMap { $0 as? NSButton }
    .first(where: { $0.title == "恢复默认" })!.performClick(nil)
check(sentStyle == .defaultValue &&
      titleToggle.state == .on && waveformToggle.state == .on,
      "Reset restores the colors, opacity, spacing, font sizes and both switches")

// The shared colour panel keeps its own history position, so it must be placed
// next to the swatch that opened it before it appears.
let swatch = NSRect(x: 1200, y: 300, width: 96, height: 28)
let besidePanel = NSRect(x: 900, y: 200, width: 380, height: 310)
let colorPanelSize = NSSize(width: 260, height: 360)
let leftOrigin = StyleSettingsPanel.colorPanelOrigin(
    well: swatch, panel: besidePanel, colorPanel: colorPanelSize, visibleFrames: [screen])
check(near(leftOrigin.x, besidePanel.minX - StyleSettingsPanel.colorPanelGap - colorPanelSize.width) &&
      near(leftOrigin.y, swatch.midY - colorPanelSize.height / 2),
      "The colour panel opens beside the settings panel, centred on its swatch")
let rightOrigin = StyleSettingsPanel.colorPanelOrigin(
    well: NSRect(x: 320, y: 300, width: 96, height: 28),
    panel: NSRect(x: 20, y: 200, width: 380, height: 310),
    colorPanel: colorPanelSize, visibleFrames: [screen])
check(near(rightOrigin.x, 410),
      "A settings panel against the left screen edge puts the colour panel on the right")
check(near(StyleSettingsPanel.colorPanelOrigin(
        well: NSRect(x: 700, y: 5, width: 96, height: 28), panel: besidePanel,
        colorPanel: colorPanelSize, visibleFrames: [screen]).y, 8) &&
      near(StyleSettingsPanel.colorPanelOrigin(
        well: NSRect(x: 700, y: 590, width: 96, height: 28), panel: besidePanel,
        colorPanel: colorPanelSize, visibleFrames: [screen]).y, screen.maxY - colorPanelSize.height - 8),
      "The colour panel is clamped inside the visible area near the screen edges")
guard let anchoredWell = wells.first(where: { $0.accessibilityLabel() == "浮层背景颜色" })
    as? AnchoredColorWell else {
    fatalError("Colour swatches must anchor the shared colour panel")
}
settings.panel.setFrameOrigin(NSPoint(x: 700, y: 200))
let anchor = anchoredWell.colorPanelAnchor?()
check(anchor != nil &&
      (anchor!.x <= settings.panel.frame.minX - StyleSettingsPanel.colorPanelGap ||
       anchor!.x >= settings.panel.frame.maxX + StyleSettingsPanel.colorPanelGap) &&
      NSScreen.screens.contains(where: { $0.visibleFrame.contains(anchor!) }),
      "Every swatch anchors the shared colour panel beside the settings panel")

// The shared colour panel is part of the same flow: it cannot be dragged away
// and offers no window buttons, because it closes with the style panel.
func colourPanelButtonsHidden() -> Bool {
    [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].allSatisfy {
        NSColorPanel.shared.standardWindowButton($0)?.isHidden ?? true
    }
}
check(!NSColorPanel.shared.isMovable && colourPanelButtonsHidden(),
      "The shared colour panel cannot be dragged and shows no title-bar buttons")

// A lightweight style panel: no title-bar button, no dragging, and it goes away
// as soon as the user moves on.
check(!settings.panel.styleMask.contains(.closable) &&
      (settings.panel.standardWindowButton(.closeButton)?.isHidden ?? true) &&
      !settings.panel.isMovable,
      "The style panel has no close button and cannot be dragged around")
settings.show(near: toolbarRect, visibleFrames: [screen])
check(settings.shouldDismissAfterLosingKey(colourPanelIsKey: false) &&
      !settings.shouldDismissAfterLosingKey(colourPanelIsKey: true),
      "Losing focus to another window dismisses the panel but picking a colour does not")
settings.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification,
                                         object: settings.panel))
check(!settings.isVisible,
      "The style panel closes as soon as it loses focus")

// The panel opens from the toolbar, so it must close the way a popover does
// instead of only through its title-bar button.
func keyEvent(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                     timestamp: 0, windowNumber: settings.panel.windowNumber, context: nil,
                     characters: characters, charactersIgnoringModifiers: characters,
                     isARepeat: false, keyCode: keyCode)!
}
settings.show(near: toolbarRect, visibleFrames: [screen])
check(settings.isVisible && settings.isWatchingOutsideClicks,
      "Opening the style panel starts watching for outside clicks")
check(!NSColorPanel.shared.isMovable && colourPanelButtonsHidden(),
      "Showing the style panel re-applies the colour panel chrome")
settings.panel.keyDown(with: keyEvent("\u{1b}", keyCode: 53, modifiers: []))
check(!settings.isVisible && !settings.isWatchingOutsideClicks,
      "Escape closes the style panel and stops watching")
settings.show(near: toolbarRect, visibleFrames: [screen])
check(settings.panel.performKeyEquivalent(with: keyEvent("w", keyCode: 13, modifiers: .command)) &&
      !settings.isVisible,
      "Command-W closes the style panel")
settings.show(near: toolbarRect, visibleFrames: [screen])
check(!settings.dismissIfClickingOutside(settings.panel) &&
      !settings.dismissIfClickingOutside(NSColorPanel.shared) && settings.isVisible,
      "Clicking the panel or its colour panel keeps the style panel open")
check(settings.dismissIfClickingOutside(controls.panel) && !settings.isVisible,
      "Clicking the overlay outside the panel dismisses it")
settings.show(near: toolbarRect, visibleFrames: [screen])
check(settings.dismissIfClickingOutside(nil) && !settings.isVisible,
      "A click in another app dismisses the style panel")

// The current line can carry its own timing: the sung characters light up while
// the engine's snapshots arrive every 300 ms, driven by the host's own clock.
let now = Date().timeIntervalSinceReferenceDate
lyricView.applyStyle(.defaultValue)
lyricView.show(primary: "合成歌词", secondary: "合成副句")
lyricView.layout()
lyricView.showLine(primary: "合成歌词", secondary: "合成副句",
                   line: LineTiming(lineStart_ms: 1_000, nextStart_ms: 5_000,
                                    position_ms: 1_000),
                   playing: true, now: now)
lyricView.layout()
check(lyricView.isSweepActive,
      "A verified current line with a following timestamp starts its sweep")
let headCaret = lyricView.sweepCaretOffset ?? -1
check(headCaret >= 0 && headCaret < primaryLabel.frame.width / 5,
      "The sweep boundary starts on the first character, not mid-line")
lyricView.showLine(primary: "合成歌词", secondary: "合成副句",
                   line: LineTiming(lineStart_ms: 1_000, nextStart_ms: 5_000,
                                    position_ms: 3_100),
                   playing: true, now: now)
lyricView.layout()
let midCaret = lyricView.sweepCaretOffset ?? -1
check(midCaret > 0 && midCaret < (primaryLabel.frame.width / 2),
      "Two characters of four put the boundary inside the first half")

// One clock-driven tick repaints the row without waiting for the next snapshot.
lyricView.advanceSweepForTesting()
check(lyricView.isSweepActive,
      "A clock tick keeps the sweep alive between engine snapshots")

// The sung prefix walks the row monotonically as the line is sung.
lyricView.setSweepProgressForTesting(0.25)
let quarterCaret = lyricView.sweepCaretOffset ?? -1
lyricView.setSweepProgressForTesting(0.75)
let threeQuarterCaret = lyricView.sweepCaretOffset ?? -1
check(quarterCaret > 0 && threeQuarterCaret > quarterCaret &&
      threeQuarterCaret < primaryLabel.frame.width,
      "The sweep advances smoothly across the current line")

// A seek far outside the reported line holds the old row instead of guessing.
lyricView.setSweepProgressForTesting(0.5)
lyricView.showLine(primary: "合成歌词", secondary: "合成副句",
                   line: LineTiming(lineStart_ms: 1_000, nextStart_ms: 5_000,
                                    position_ms: 90_000),
                   playing: true, now: now)
lyricView.layout()
check(!lyricView.isSweepActive,
      "A stale line holds its sweep until the engine reports the owning line")

// Pausing freezes the sweep at the moment the snapshot arrived.
lyricView.setSweepProgressForTesting(0.5)
lyricView.showLine(primary: "合成歌词", secondary: "合成副句",
                   line: LineTiming(lineStart_ms: 1_000, nextStart_ms: 5_000,
                                    position_ms: 3_100),
                   playing: false, now: now)
lyricView.layout()
check(!lyricView.isSweepActive,
      "A paused snapshot never sweeps")
lyricView.setSweepProgressForTesting(0.5)
lyricView.showLine(primary: "末句歌词", secondary: "",
                   line: LineTiming(lineStart_ms: 1_000, nextStart_ms: nil,
                                    position_ms: 3_100),
                   playing: true, now: now)
lyricView.layout()
check(!lyricView.isSweepActive,
      "The final line has no following timestamp and never fakes a boundary")
lyricView.setSweepProgressForTesting(0.5)
lyricView.show(primary: "等待网易云音乐…", secondary: "")
lyricView.layout()
check(!lyricView.isSweepActive && lyricView.sweepCaretOffset == nil,
      "A status line clears the sweep instead of painting over waiting text")

print("Overlay appearance: all assertions passed")
