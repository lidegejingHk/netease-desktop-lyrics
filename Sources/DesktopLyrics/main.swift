import AppKit
import Foundation

private struct LyricEvent: Decodable {
    let kind: String
    let text: String?
    let translation: String?
    let next: String?
    let reason: String?
    let playing: Bool?
    let held_paused: Bool?
    let position_ms: UInt64?
    let duration_ms: UInt64?
    let title: String?
}

private final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: NSPanel!
    private var content: LyricsView!
    private var outerFrame: OverlayFrame!
    private var rail: WaveformRail!
    private var statusItem: NSStatusItem!
    private var toggleItem: NSMenuItem!
    private var lockItem: NSMenuItem!
    private var retryTransportItem: NSMenuItem!
    private var controls: OverlayControls!
    private var settingsWindow: StyleSettingsPanel!
    private let styleStore = OverlayStyleStore()
    private let launchMode = DesktopLaunchMode(arguments: ProcessInfo.processInfo.arguments)
    private var bridge: Process?
    private var shouldStop = false
    private var locked = UserDefaults.standard.bool(forKey: "overlayLocked")
    private var showing = UserDefaults.standard.object(forKey: "overlayShowing") as? Bool ?? true
    private var snappedRight = UserDefaults.standard.bool(forKey: "overlaySnappedRight")
    private let transportQueue = DispatchQueue(label: "local.desktop-lyrics.transport", qos: .userInitiated)
    private var transportTimer: Timer?
    private var transportRequest = 0
    private var transportChecking = false
    private var transportBusy = false
    private var transportAvailability = PlaybackTransport.Availability.unavailable
    private var failedTransport = PlaybackTransport.FailureLatch()
    private var hoverTimer: Timer?
    private var hover = OverlayHover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureWindow()
        configureOuterFrame()
        configureRail()
        configureControls()
        configureMenu()
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersChanged(_:)),
                                               name: NSApplication.didChangeScreenParametersNotification,
                                               object: nil)
        showStatus("正在等待网易云音乐…")
        refreshTransport()
        transportTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshTransport()
        }
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.refreshControlReveal()
        }
        if launchMode == .stdin {
            observe(FileHandle.standardInput)
        } else {
            launchBridge()
        }
    }

    private func configureWindow() {
        let frame = NSRect(origin: .zero, size: OverlayLayout.lyricSize)
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = locked
        panel.delegate = self
        content = LyricsView(frame: frame)
        content.onDrag = { [weak self] delta in self?.moveOverlay(by: delta) }
        panel.contentView = content
        content.applyStyle(styleStore.load())
        let size = NSSize(width: frame.width,
                          height: OverlayLayout.clampedBandHeight(content.desiredBandHeight))
        panel.setContentSize(size)
        content.frame = NSRect(origin: .zero, size: size)
        content.onBandHeightChange = { [weak self] height in self?.applyBandHeight(height) }
        if let point = UserDefaults.standard.dictionary(forKey: "overlayOrigin"),
           let x = point["x"] as? Double, let y = point["y"] as? Double,
           x.isFinite, y.isFinite {
            let proposed = NSRect(origin: NSPoint(x: x, y: y), size: size)
            panel.setFrameOrigin(settledOrigin(for: proposed))
        } else if let screen = NSScreen.main {
            let area = screen.visibleFrame
            let target = NSRect(x: area.midX - OverlayLayout.outerSize.width / 2 +
                                   OverlayLayout.lyricInset.x,
                                y: area.minY + 85 + OverlayLayout.lyricInset.y,
                                width: size.width, height: size.height)
            panel.setFrameOrigin(settledOrigin(for: target))
        } else {
            panel.center()
        }
    }

    /// One placement authority for every non-drag move: free positions are clamped
    /// into the screens, a pinned overlay instead keeps the display's right edge.
    private func settledOrigin(for lyrics: NSRect) -> NSPoint {
        let frames = NSScreen.screens.map(\.visibleFrame)
        return snappedRight
            ? OverlayLayout.snappedRightOrigin(for: lyrics, visibleFrames: frames)
            : OverlayLayout.constrainedOrigin(for: lyrics, visibleFrames: frames)
    }

    private func configureOuterFrame() {
        outerFrame = OverlayFrame()
        outerFrame.applyStyle(styleStore.load())
        outerFrame.setLocked(locked)
        outerFrame.onDrag = { [weak self] delta in self?.moveOverlay(by: delta) }
        outerFrame.follow(lyrics: panel.frame)
        outerFrame.setVisible(showing)
        if showing { panel.orderFrontRegardless() }
    }

    private func configureRail() {
        rail = WaveformRail()
        rail.applyStyle(styleStore.load())
        rail.follow(lyrics: panel.frame)
        rail.setVisible(showing)
    }

    private func configureControls() {
        controls = OverlayControls()
        controls.setLocked(locked)
        controls.onDrag = { [weak self] delta in self?.moveOverlay(by: delta) }
        controls.onToggleLock = { [weak self] in self?.changeLock() }
        controls.onSnapRight = { [weak self] in self?.snapOverlayToRightEdge() }
        controls.onToggleSettings = { [weak self] in self?.showOrHideSettings() }
        controls.onPrevious = { [weak self] in self?.runTransport(.previous) }
        controls.onNext = { [weak self] in self?.runTransport(.next) }
        controls.onTogglePlayback = { [weak self] in
            guard let self else { return }
            switch self.transportAvailability.toggle {
            case .play: self.runTransport(.play)
            case .pause: self.runTransport(.pause)
            case .unavailable: break
            }
        }
        settingsWindow = StyleSettingsPanel(style: styleStore.load())
        settingsWindow.onStyleChange = { [weak self] style in
            self?.styleStore.save(style)
            self?.content.applyStyle(style)
            self?.outerFrame.applyStyle(style)
            self?.controls.applyStyle(style)
            self?.rail.applyStyle(style)
        }
        controls.applyStyle(styleStore.load())
        updateControlsPosition()
        if showing { controls.setVisible(true) }
    }

    private func refreshTransport() {
        guard !shouldStop, !transportBusy, !transportChecking else { return }
        transportChecking = true
        transportRequest &+= 1
        let request = transportRequest
        transportQueue.async { [weak self] in
            let state = PlaybackTransport.currentAvailability()
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.shouldStop, request == self.transportRequest else { return }
                self.transportChecking = false
                guard !self.transportBusy else { return }
                let visibleState = self.failedTransport.visibleState(for: state)
                self.retryTransportItem.isHidden = !self.failedTransport.hasFailure
                self.transportAvailability = visibleState
                self.controls.setPlaybackAvailability(previous: visibleState.previous,
                                                     toggle: visibleState.toggle,
                                                     next: visibleState.next)
            }
        }
    }

    private func runTransport(_ action: PlaybackTransport.Action) {
        guard launchMode == .app, !shouldStop, !transportBusy,
              transportAvailability.allows(action) else { return }
        let attemptedState = transportAvailability
        transportBusy = true
        transportChecking = false
        transportRequest &+= 1 // invalidate slower in-flight availability reads
        transportAvailability = .unavailable
        controls.setPlaybackAvailability(previous: false, toggle: .unavailable, next: false)
        transportQueue.async { [weak self] in
            let succeeded = PlaybackTransport.perform(action)
            DispatchQueue.main.async { [weak self, attemptedState] in
                guard let self, !self.shouldStop else { return }
                self.transportBusy = false
                if !succeeded {
                    self.failedTransport.record(action, in: attemptedState)
                    self.retryTransportItem.isHidden = false
                    NSSound.beep()
                }
                self.refreshTransport()
            }
        }
    }

    /// The lyric panel is the group's single position source. The enclosing panel
    /// never moves itself, so there is no two-window delegate feedback loop.
    private func moveOverlay(by delta: NSPoint) {
        guard !locked, let panel else { return }
        releaseRightEdge() // dragging is how the user takes the overlay off the rail
        let proposed = panel.frame.offsetBy(dx: delta.x, dy: delta.y)
        let origin = OverlayLayout.constrainedOrigin(
            for: proposed, visibleFrames: NSScreen.screens.map(\.visibleFrame))
        guard origin != panel.frame.origin else { return }
        panel.setFrameOrigin(origin)
        syncOverlayPosition()
    }

    private func updateControlsPosition() {
        guard let panel else { return }
        outerFrame?.follow(lyrics: panel.frame)
        controls?.follow(overlay: panel.frame)
        rail?.follow(lyrics: panel.frame)
    }

    /// The band hugs the lyric text: the top of the group stays put while only the
    /// lower edge moves, then the whole group is re-clamped into the screens.
    private func applyBandHeight(_ height: CGFloat) {
        guard let panel else { return }
        let size = NSSize(width: panel.frame.width,
                          height: OverlayLayout.clampedBandHeight(height))
        guard abs(size.height - panel.frame.height) > 0.5 else { return }
        let proposed = NSRect(x: panel.frame.minX, y: panel.frame.maxY - size.height,
                              width: size.width, height: size.height)
        let origin = settledOrigin(for: proposed)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        content?.frame = NSRect(origin: .zero, size: size)
        syncOverlayPosition()
    }

    /// Polled rather than tracked: a locked overlay passes every mouse event
    /// through, so tracking areas would never report the pointer.
    private func refreshControlReveal() {
        guard let panel, let controls, let outerFrame, showing else { return }
        let envelope = OverlayLayout.envelope(for: panel.frame)
        let inside = OverlayHover.inside(point: NSEvent.mouseLocation, envelope: envelope)
        let visible = hover.update(now: ProcessInfo.processInfo.systemUptime, inside: inside)
        controls.setControlsVisible(visible)
        outerFrame.setTitleVisible(visible)
    }

    private func syncOverlayPosition() {
        guard let panel else { return }
        updateControlsPosition()
        UserDefaults.standard.set(["x": Double(panel.frame.minX), "y": Double(panel.frame.minY)],
                                  forKey: "overlayOrigin")
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel, notification.object as? NSWindow === panel else { return }
        syncOverlayPosition()
    }

    func windowDidChangeScreen(_ notification: Notification) { updateControlsPosition() }

    @objc private func screenParametersChanged(_ notification: Notification) {
        guard panel != nil else { return }
        let origin = settledOrigin(for: panel.frame)
        if origin != panel.frame.origin { panel.setFrameOrigin(origin) }
        updateControlsPosition()
    }

    private func configureMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "网易云桌面歌词")
            if button.image == nil { button.title = "词" }
        }
        let menu = NSMenu(title: "网易云桌面歌词")
        toggleItem = NSMenuItem(title: showing ? "隐藏歌词" : "显示歌词", action: #selector(toggleVisible(_:)), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        lockItem = NSMenuItem(title: locked ? "解锁位置（可拖动）" : "锁定位置（点击穿透）", action: #selector(toggleLock(_:)), keyEquivalent: "")
        lockItem.target = self
        menu.addItem(lockItem)
        let settings = NSMenuItem(title: "歌词样式…", action: #selector(toggleSettings(_:)), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        retryTransportItem = NSMenuItem(title: "播放控制失败，重新检查…",
                                        action: #selector(retryTransport(_:)), keyEquivalent: "")
        retryTransportItem.target = self
        retryTransportItem.isHidden = true
        menu.addItem(retryTransportItem)
        menu.addItem(.separator())
        let permission = NSMenuItem(title: "打开辅助功能设置…", action: #selector(openAccessibility(_:)), keyEquivalent: "")
        permission.target = self
        menu.addItem(permission)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出桌面歌词", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func toggleVisible(_ sender: NSMenuItem) {
        showing.toggle()
        outerFrame.setVisible(showing)
        if showing { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
        controls.setVisible(showing)
        rail.setVisible(showing)
        if !showing { settingsWindow.close() }
        UserDefaults.standard.set(showing, forKey: "overlayShowing")
        toggleItem.title = showing ? "隐藏歌词" : "显示歌词"
        refreshControlReveal()
    }

    @objc private func retryTransport(_ sender: NSMenuItem) {
        failedTransport = PlaybackTransport.FailureLatch()
        retryTransportItem.isHidden = true
        transportAvailability = .unavailable
        controls.setPlaybackAvailability(previous: false, toggle: .unavailable, next: false)
        refreshTransport()
    }

    @objc private func toggleLock(_ sender: NSMenuItem) { changeLock() }

    private func changeLock() {
        locked.toggle()
        panel.ignoresMouseEvents = locked
        outerFrame.setLocked(locked)
        controls.setLocked(locked)
        UserDefaults.standard.set(locked, forKey: "overlayLocked")
        lockItem.title = locked ? "解锁位置（可拖动）" : "锁定位置（点击穿透）"
    }

    /// The top-right arrow is a magnetic edge, not a collapse: the whole group
    /// moves onto the current display's right edge and keeps that edge while the
    /// lyric band resizes. Dragging the overlay releases it.
    private func snapOverlayToRightEdge() {
        guard let panel else { return }
        snappedRight = true
        UserDefaults.standard.set(true, forKey: "overlaySnappedRight")
        let origin = settledOrigin(for: panel.frame)
        if origin != panel.frame.origin { panel.setFrameOrigin(origin) }
        syncOverlayPosition()
    }

    private func releaseRightEdge() {
        guard snappedRight else { return }
        snappedRight = false
        UserDefaults.standard.set(false, forKey: "overlaySnappedRight")
    }

    @objc private func toggleSettings(_ sender: NSMenuItem) { showOrHideSettings() }

    private func showOrHideSettings() {
        guard settingsWindow != nil else { return }
        if settingsWindow.isVisible {
            settingsWindow.close()
        } else {
            settingsWindow.show(near: controls.panel.frame,
                                visibleFrames: NSScreen.screens.map(\.visibleFrame))
        }
    }

    @objc private func openAccessibility(_ sender: NSMenuItem) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit(_ sender: NSMenuItem) { NSApp.terminate(nil) }

    private func launchBridge() {
        guard let executable = Bundle.main.path(forResource: "netease-lyrics-rs", ofType: nil) else {
            showStatus("未找到 Rust 歌词引擎，请重新构建应用")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["--lyrics-json", "--interval-ms", "300"]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        do {
            try process.run()
            bridge = process
            observe(output.fileHandleForReading)
        } catch {
            showStatus("歌词引擎启动失败，请从终端运行诊断命令")
        }
    }

    private func observe(_ handle: FileHandle) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var pending = Data()
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                pending.append(chunk)
                while let end = pending.firstIndex(of: 10) {
                    let line = pending.prefix(upTo: end)
                    pending.removeSubrange(...end)
                    guard line.count <= 65_536 else {
                        DispatchQueue.main.async { [weak self] in self?.showStatus("歌词数据过长，已跳过") }
                        continue
                    }
                    if let event = try? JSONDecoder().decode(LyricEvent.self, from: line) {
                        DispatchQueue.main.async { [weak self] in self?.apply(event) }
                    }
                }
                if pending.count > 65_536 {
                    pending.removeAll(keepingCapacity: true)
                    DispatchQueue.main.async { [weak self] in self?.showStatus("歌词数据过长，已跳过") }
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.shouldStop else { return }
                self.showStatus("歌词引擎已停止，请从菜单栏退出后重新打开")
            }
        }
    }

    private func apply(_ event: LyricEvent) {
        switch event.kind {
        case "loading": showStatus("正在获取当前歌曲歌词…")
        // A verified title arrives on its own, after the lyric request answered.
        case "title": outerFrame.show(title: event.title)
        case "intro":
            content.show(primary: "♪ 即将开始", secondary: event.next ?? "")
            rail.show(fraction: wholeSongFraction(event), playing: event.playing == true)
        case "line":
            let subtitle = event.translation?.isEmpty == false
                ? event.translation! : (event.next ?? "")
            let secondary = event.playing == false ? "Ⅱ  \(subtitle)" : subtitle
            content.show(primary: event.text ?? "", secondary: secondary)
            rail.show(fraction: wholeSongFraction(event), playing: event.playing == true)
        case "unavailable": showStatus(message(for: event.reason))
        default: showStatus("未知的歌词引擎状态")
        }
    }

    private func message(for reason: String?) -> String {
        switch reason {
        case "not_running": return "打开网易云音乐后，歌词会出现在这里"
        case "no_song": return "等待当前歌曲…"
        case "accessibility_permission_denied": return launchMode.accessibilityPermissionStatus
        case "permission_denied": return "无法读取网易云本地播放记录：权限不足"
        case "network": return "歌词网络不可用，稍后自动重试"
        case "no_lyrics": return "当前歌曲暂无逐行歌词"
        case "lyrics_invalid": return "歌词接口返回异常，稍后自动重试"
        case "format_changed": return "网易云本地格式变化，需要重新适配"
        case "missing_field": return "无法读取网易云播放状态"
        case "invalid_track_id": return "当前歌曲没有可用于请求歌词的标识"
        default: return "等待可用的播放信息…"
        }
    }

    /// Whole-song progress from the verified snapshot; the current line never resets it.
    private func wholeSongFraction(_ event: LyricEvent) -> CGFloat? {
        WholeSongProgress.fraction(position_ms: event.position_ms ?? 0,
                                   duration_ms: event.duration_ms)
    }

    private func showStatus(_ message: String) {
        content.show(primary: message, secondary: "")
        rail?.show(fraction: nil, playing: false)
        // Every status means "no verified current song", so no old title survives.
        outerFrame?.show(title: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        shouldStop = true
        transportTimer?.invalidate()
        hoverTimer?.invalidate()
        if let bridge, bridge.isRunning { bridge.terminate() }
    }
}

let app = NSApplication.shared
private let controller = AppController()
app.delegate = controller
app.run()
