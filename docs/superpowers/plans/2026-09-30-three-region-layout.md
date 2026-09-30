# 桌面歌词三区布局 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 精确落实草图的右上操作、中间歌词、下方横向声浪三个互不重叠区域，打包可用的 macOS App。

**Architecture:** 以 `OverlayLayout` 作为三块屏幕几何的单一来源；`AppController` 管理歌词、顶部操作、底部声浪的窗口生命周期；`LyricsView` 只负责居中歌词；独立 `WaveformRailView` 负责全宽可视化及进度，复用独立按钮的鼠标命中策略。

**Tech Stack:** Swift/AppKit、macOS 13+、Rust/Cargo、本机 ad-hoc 签名。

---

### Task 1: 固定三区几何与窗口命中

**Files:** `Sources/DesktopLyrics/OverlayVisibility.swift`, `ToolbarPlacement.swift`, `OverlayControls.swift`, `main.swift`, `tests/OverlayAppearanceTests/main.swift`。

- [ ] 更新测试断言：主窗 860×152，上栏 276×48 位于主窗右上外侧，下栏 856×32 位于主窗下方；原先“内侧双排”断言应变红。运行 `./scripts/test-swift.sh`，预期失败在布局断言。
- [ ] 实现 `OverlayLayout.toolbarFrame(for:)`、`railFrame(for:)`、`envelope(for:)`；用外包框约束屏幕位置。`ToolbarPlacement.origin` 对折叠与展开保持同一右缘。
- [ ] 将七枚操作按钮排为单行小命中窗口，装饰背景面板点击穿透；保留原有播放可用性、按钮回调、辅助功能文案和“锁定后拖动按钮穿透”。
- [ ] 在 `AppController` 中让三区共移、共显隐，背景与按钮同步应用样式；更新 WindowServer 真实命中测试。运行 `./scripts/test-swift.sh` 与 macOS 13 严格类型检查，提交。

### Task 2: 完整歌词及全宽声浪

**Files:** `Sources/DesktopLyrics/LyricsView.swift`, `WaveformView.swift`, 新建 `WaveformRailView.swift`, `main.swift`, `scripts/test-swift.sh`, `tests/OverlayAppearanceTests/main.swift`。

- [ ] 添加测试：歌词文字与两种文字背底围绕整个框居中、不再为控件让位；两行上限、极长省略和 Unicode 保留；下栏声浪铺满、进度长度按 0～1 限幅、无音频采集；暂停／隐藏／Reduce Motion 停止计时。运行 Swift 测试，预期先失败。
- [ ] 从 `LyricsView` 移走内部进度与五柱动画、删除内置按钮占位；单一状态主句垂直居中，保持有副句时的独立两行布局。`AppController` 同步 `show` 状态至底栏。
- [ ] 实现单个定时器驱动、横贯下栏的确定性细柱声浪和逐句进度；外层背景沿用用户设置，底栏窗口始终点击穿透。运行 Swift 测试并提交。

### Task 3: 预览、验证和交付

**Files:** `README.md`, `docs/validation-checklist.md`（仅在必要时修改）。

- [ ] 更新 README 中双排／小五柱／框内进度旧描述，记录三区布局和下栏动效非音频采样。提交。
- [ ] 执行 `./scripts/test-swift.sh`、`xcrun swiftc -target arm64-apple-macos13.0 -warnings-as-errors -framework AppKit -framework Foundation -framework ApplicationServices -typecheck Sources/DesktopLyrics/*.swift`、`cargo test`、`cargo fmt --all --check`、`cargo clippy --all-targets -- -D warnings`、`git diff --check`。自审播放和鼠标命中安全边界。
- [ ] 用 `./scripts/build-app.sh --output dist-preview/网易云桌面歌词-三区预览.app --bundle-id com.local.netease-desktop-lyrics-three-region-preview` 打预览包；以 `--stdin` 合成短句、长句、状态验证三块的合成屏幕图及窗口命中，不操作真实网易云。
- [ ] 退出旧正式包，备份至 `dist-backup/`；`./scripts/build-app.sh` 构建正式包，`codesign --verify --deep --strict` 并打开。若 ad-hoc 重签导致授权失效，不自动修改系统权限。检查本地分支 commit 和干净状态，不推送。
