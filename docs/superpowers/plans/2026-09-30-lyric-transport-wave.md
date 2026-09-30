# 桌面歌词双排控制与声浪 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 右侧双排播放/管理按钮、最多两行自适应歌词和声浪，仍可锁定点击穿透。

**Architecture:** Swift/AppKit 在 `LyricsView` 中管理左侧受限文本与声浪，在 `OverlayControls` 中用独立可点击 NSPanel 排两行；`PlaybackTransport` 只对网易云音乐辅助功能控制菜单做确切选择和 AXPress，不能访问时按钮禁用。Rust 歌词引擎保持只读、不改协议。

**Tech Stack:** Swift/AppKit 和 ApplicationServices（macOS 13+），Rust/Cargo；`scripts/test-swift.sh`、`scripts/build-app.sh`。

---

## 任务 1：固定双排控件与可用状态

- [ ] 更新 `Sources/DesktopLyrics/ToolbarPlacement.swift` 的目标尺寸/右侧位置，并在 `tests/OverlayAppearanceTests/main.swift` 加入旧按钮回归及新 7+1 按钮的窗口几何、边缘屏幕、锁定穿透、收起后右缘测试；先运行 `./scripts/test-swift.sh` 确认红灯。
- [ ] 修改 `Sources/DesktopLyrics/OverlayControls.swift`，第一排三枚播放按钮，第二排四枚原有操作及独立展开按钮；扩展 `onPrevious/onTogglePlayback/onNext`、`setPlaybackAvailability` 并保留色彩、透明间隙、无动画和无激活面板。
- [ ] 由 `Sources/DesktopLyrics/main.swift` 扩大窗口，并保持歌词视图与工具条的相对坐标、显示/隐藏/锁定状态同步；运行 Swift 测试、macOS 13 `xcrun swiftc -target arm64-apple-macos13.0 -warnings-as-errors -framework AppKit -framework Foundation -framework ApplicationServices -typecheck Sources/DesktopLyrics/*.swift` 后 commit。

## 任务 2：菜单安全操作

- [ ] 新建 `Sources/DesktopLyrics/PlaybackTransport.swift` 与 `tests/OverlayAppearanceTests` 或独立 Swift 测试：纯模型验证每个操作严格匹配唯一启用菜单项、冲突/禁用/缺项全部不可用；测试先失败。
- [ ] 实现读网易云音乐的控制菜单并仅对经过再次校验的目标执行 `AXPress`；在 `main.swift` 将状态异步刷新回主线程，按钮仅在可靠时启用。预览 `--stdin` 禁用真播放操作；更新 `scripts/test-swift.sh` 的文件/框架清单。Swift 测试通过后 commit。

## 任务 3：两行适配与声浪

- [ ] 在 `tests/OverlayAppearanceTests/main.swift` 增加短句居中、两行/极长省略、字体下限、文字背底/按钮避让、展开/收起和播放/暂停/减少动态效果的断言；先见红灯。
- [ ] 修改 `Sources/DesktopLyrics/LyricsView.swift`：各文本最多两行，测量后逐步调整字体，仍超长则第二行尾省略；控件占区时改用左侧区域、把 chip 缩至实际绘制范围。新增可测试的 5 柱 `WaveformView`（或同文件小视图），暂停/无歌曲/减少动态效果静止、播放时才启动周期动画。
- [ ] 在 `Sources/DesktopLyrics/main.swift` 把歌词流状态传给视图，不引入音频/麦克风权限。Swift 测试通过后 commit。

## 任务 4：完整验证及打包

- [ ] 更新 `README.md` 的操作、两行、声浪说明；提交。
- [ ] 执行 Swift 测试、严格编译、`cargo test`（预期 63 passed）、`cargo fmt --all --check`、`cargo clippy --all-targets -- -D warnings`、`git diff --check`；代码审查并修复阻塞问题。
- [ ] 用 `./scripts/build-app.sh --output dist-preview/网易云桌面歌词-预览.app --bundle-id com.local.netease-desktop-lyrics-preview` 构建预览，`codesign --verify --deep --strict`，`--stdin` 合成短/长歌词检查外观与不误控真实播放器。
- [ ] 退出旧正式 App，备份 `dist/网易云桌面歌词.app`，执行 `./scripts/build-app.sh` 一次并签名验证、打开正式 App；授权若失效，仅打开授权页告知用户手动重授，不修改安全设置。最终检查本地 commit、干净工作区、没有推送。
