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
    private var bridge: Process?
    private var shouldStop = false
    private var locked = UserDefaults.standard.bool(forKey: "overlayLocked")
    private var showing = UserDefaults.standard.object(forKey: "overlayShowing") as? Bool ?? true

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureWindow()
        configureMenu()
        showStatus("正在等待网易云音乐…")
        if ProcessInfo.processInfo.arguments.contains("--stdin") {
            observe(FileHandle.standardInput)
        } else {
            launchBridge()
        }
    }

    private func configureWindow() {
        let frame = NSRect(x: 0, y: 0, width: 760, height: 112)
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
        panel.contentView = content
        if let point = UserDefaults.standard.dictionary(forKey: "overlayOrigin"),
           let x = point["x"] as? Double, let y = point["y"] as? Double,
           x.isFinite, y.isFinite, let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: x, y: y)) }) {
            let validX = min(max(x, screen.visibleFrame.minX), screen.visibleFrame.maxX - frame.width)
            let validY = min(max(y, screen.visibleFrame.minY), screen.visibleFrame.maxY - frame.height)
            panel.setFrameOrigin(NSPoint(x: validX, y: validY))
        } else if let screen = NSScreen.main {
            let area = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: area.midX - frame.width / 2, y: area.minY + 85))
        } else {
            panel.center()
        }
        if showing { panel.orderFrontRegardless() }
    }

    func windowDidMove(_ notification: Notification) {
        guard panel != nil else { return }
        UserDefaults.standard.set(["x": Double(panel.frame.minX), "y": Double(panel.frame.minY)], forKey: "overlayOrigin")
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
        UserDefaults.standard.set(showing, forKey: "overlayShowing")
        toggleItem.title = showing ? "隐藏歌词" : "显示歌词"
    }

    @objc private func toggleLock(_ sender: NSMenuItem) {
        locked.toggle()
        panel.ignoresMouseEvents = locked
        UserDefaults.standard.set(locked, forKey: "overlayLocked")
        lockItem.title = locked ? "解锁位置（可拖动）" : "锁定位置（点击穿透）"
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
            content.show(primary: "♪ 即将开始", secondary: event.next ?? "", fraction: 0, active: true)
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
            content.show(primary: event.text ?? "", secondary: secondary, fraction: fraction, active: true)
        case "unavailable": showStatus(Self.message(for: event.reason))
        default: showStatus("未知的歌词引擎状态")
        }
    }

    private static func message(for reason: String?) -> String {
        switch reason {
        case "not_running": return "打开网易云音乐后，歌词会出现在这里"
        case "no_song": return "等待当前歌曲…"
        case "accessibility_permission_denied": return "需要辅助功能权限：允许桌面歌词或运行它的终端"
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
        content.show(primary: message, secondary: "菜单栏 ♫ · 拖动位置 · 锁定后点击穿透", fraction: 0, active: false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        shouldStop = true
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
