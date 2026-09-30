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
    let line_start_ms: UInt64?
    let next_start_ms: UInt64?
}

private final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: NSPanel!
    private var content: LyricsView!
    private var statusItem: NSStatusItem!
    private var toggleItem: NSMenuItem!
    private var lockItem: NSMenuItem!
    private var controls: OverlayControls!
    private var settingsWindow: StyleSettingsPanel!
    private let styleStore = OverlayStyleStore()
    private let launchMode = DesktopLaunchMode(arguments: ProcessInfo.processInfo.arguments)
    private var bridge: Process?
    private var shouldStop = false
    private var locked = UserDefaults.standard.bool(forKey: "overlayLocked")
    private var showing = UserDefaults.standard.object(forKey: "overlayShowing") as? Bool ?? true
    private var collapsed = UserDefaults.standard.bool(forKey: "toolbarCollapsed")
    private let transportQueue = DispatchQueue(label: "local.desktop-lyrics.transport", qos: .userInitiated)
    private var transportTimer: Timer?
    private var transportRequest = 0
    private var transportChecking = false
    private var transportBusy = false
    private var transportAvailability = PlaybackTransport.Availability.unavailable

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureWindow()
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
        if launchMode == .stdin {
            observe(FileHandle.standardInput)
        } else {
            launchBridge()
        }
    }

    private func configureWindow() {
        let frame = NSRect(x: 0, y: 0, width: 860, height: 176)
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.ignoresMouseEvents = locked
        panel.delegate = self
        content = LyricsView(frame: frame)
        content.applyStyle(styleStore.load())
        content.setOverlayVisible(showing)
        panel.contentView = content
        if let point = UserDefaults.standard.dictionary(forKey: "overlayOrigin"),
           let x = point["x"] as? Double, let y = point["y"] as? Double,
           x.isFinite, y.isFinite, let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: x, y: y)) }) {
            let validX = min(max(x, screen.visibleFrame.minX),
                             max(screen.visibleFrame.minX, screen.visibleFrame.maxX - frame.width))
            let validY = min(max(y, screen.visibleFrame.minY),
                             max(screen.visibleFrame.minY, screen.visibleFrame.maxY - frame.height))
            panel.setFrameOrigin(NSPoint(x: validX, y: validY))
        } else if let screen = NSScreen.main {
            let area = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: area.midX - frame.width / 2, y: area.minY + 85))
        } else {
            panel.center()
        }
        if showing { panel.orderFrontRegardless() }
    }

    private func configureControls() {
        controls = OverlayControls()
        controls.setLocked(locked)
        controls.setCollapsed(collapsed)
        controls.onDrag = { [weak self] delta in
            guard let self, !self.locked else { return }
            self.panel.setFrameOrigin(NSPoint(x: self.panel.frame.minX + delta.x,
                                               y: self.panel.frame.minY + delta.y))
        }
        controls.onToggleLock = { [weak self] in self?.changeLock() }
        controls.onToggleCollapsed = { [weak self] in self?.changeCollapsed() }
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
            self?.controls.applyStyle(style)
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
                self.transportAvailability = state
                self.controls.setPlaybackAvailability(previous: state.previous,
                                                     toggle: state.toggle, next: state.next)
            }
        }
    }

    private func runTransport(_ action: PlaybackTransport.Action) {
        guard launchMode == .app, !shouldStop, !transportBusy,
              transportAvailability.allows(action) else { return }
        transportBusy = true
        transportChecking = false
        transportRequest &+= 1 // invalidate slower in-flight availability reads
        transportAvailability = .unavailable
        controls.setPlaybackAvailability(previous: false, toggle: .unavailable, next: false)
        transportQueue.async { [weak self] in
            let succeeded = PlaybackTransport.perform(action)
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.shouldStop else { return }
                self.transportBusy = false
                if !succeeded { NSSound.beep() }
                self.refreshTransport()
            }
        }
    }

    private func updateControlsPosition() {
        guard let controls, let panel else { return }
        controls.follow(overlay: panel.frame, visibleFrames: NSScreen.screens.map(\.visibleFrame))
        content.setControlsFrame(controls.panel.frame.offsetBy(dx: -panel.frame.minX,
                                                               dy: -panel.frame.minY))
    }

    func windowDidMove(_ notification: Notification) {
        guard panel != nil else { return }
        UserDefaults.standard.set(["x": Double(panel.frame.minX), "y": Double(panel.frame.minY)], forKey: "overlayOrigin")
        updateControlsPosition()
    }

    func windowDidChangeScreen(_ notification: Notification) { updateControlsPosition() }

    @objc private func screenParametersChanged(_ notification: Notification) {
        guard panel != nil else { return }
        let origin = OverlayVisibility.origin(for: panel.frame,
                                              visibleFrames: NSScreen.screens.map(\.visibleFrame))
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
        if showing { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
        controls.setVisible(showing)
        content.setOverlayVisible(showing)
        if !showing { settingsWindow.close() }
        UserDefaults.standard.set(showing, forKey: "overlayShowing")
        toggleItem.title = showing ? "隐藏歌词" : "显示歌词"
    }

    @objc private func toggleLock(_ sender: NSMenuItem) { changeLock() }

    private func changeLock() {
        locked.toggle()
        panel.ignoresMouseEvents = locked
        controls.setLocked(locked)
        UserDefaults.standard.set(locked, forKey: "overlayLocked")
        lockItem.title = locked ? "解锁位置（可拖动）" : "锁定位置（点击穿透）"
    }

    private func changeCollapsed() {
        collapsed.toggle()
        controls.setCollapsed(collapsed)
        updateControlsPosition()
        UserDefaults.standard.set(collapsed, forKey: "toolbarCollapsed")
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
        case "intro":
            content.show(primary: "♪ 即将开始", secondary: event.next ?? "", fraction: 0,
                         active: true, playing: event.playing == true)
        case "line":
            let subtitle = event.translation?.isEmpty == false
                ? event.translation! : (event.next ?? "")
            let secondary = event.playing == false ? "Ⅱ  \(subtitle)" : subtitle
            let elapsed = event.position_ms ?? 0
            let start = event.line_start_ms ?? 0
            let end = event.next_start_ms ?? start
            let fraction: CGFloat = end > start
                ? CGFloat(min(elapsed.saturatingSubtracting(start), end - start)) / CGFloat(end - start)
                : 1
            content.show(primary: event.text ?? "", secondary: secondary, fraction: fraction,
                         active: true, playing: event.playing == true)
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

    private func showStatus(_ message: String) {
        content.show(primary: message, secondary: "右上角按钮可拖动、锁定并设置颜色与透明度", fraction: 0, active: false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        shouldStop = true
        transportTimer?.invalidate()
        if let bridge, bridge.isRunning { bridge.terminate() }
    }
}

private extension UInt64 {
    func saturatingSubtracting(_ other: UInt64) -> UInt64 { self >= other ? self - other : 0 }
}

let app = NSApplication.shared
private let controller = AppController()
app.delegate = controller
app.run()
