# 居中播放行 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将播放三键从右上工具区移到歌词与声浪之间，整体保持一块无分隔底板的紧凑浮层。

**Architecture:** `OverlayLayout` 唯一定义整体、顶栏、歌词、底部播放行和声浪的相对矩形；`OverlayControls` 继续复用原来八个小按钮窗口，右上透明面板和中下透明面板分别作布局容器、不抢鼠标事件；`main.swift` 仍只让歌词窗口提供整体移动坐标，改变布局后既有拖动、锁定和安全播放逻辑不变。

**Tech Stack:** Swift/AppKit (macOS 13+), Rust/Cargo, ad-hoc 本地 App 签名。

---

### Task 1: 几何与分组测试先红灯

**Files:** Modify `tests/OverlayAppearanceTests/main.swift`; `Sources/DesktopLyrics/OverlayLayout.swift`; `Sources/DesktopLyrics/ToolbarPlacement.swift`.

- [x] Swift 测试固定示例：歌词 `(116,180,848,126)` 对应外框 `(100,100,880,256)`；工具 `(804,310,160,36)`；播放 `(474,144,132,32)`；声浪 `(124,112,832,28)`；顶栏—歌词、歌词—播放、播放—声浪皆为 4 pt。
- [x] 测试两个功能组的独立窗口互不相交、播放水平居中、收起只改变右上锚点，并检查外框屏幕可见范围的上下约束。
- [x] 运行 `./scripts/test-swift.sh` 验证测试红灯，然后修改 `OverlayLayout` 常量／`playbackFrame` 和工具布局并复跑至绿灯。

### Task 2: 两排按钮的窗口命中与交互

**Files:** Modify `Sources/DesktopLyrics/OverlayControls.swift`; `tests/OverlayAppearanceTests/main.swift`.

- [x] 测试顶部四个 34×32 按钮分布在 160×36 区域；三枚播放按钮分布在 132×32 中下区域，侧键 34×30、中键 38×32，和顶栏互不重叠；两占位面板透明穿透。
- [x] 测试收起后只剩右上展开按钮，播放三键仍可见／按钮可执行，锁定后仍可点击播放和解锁；隐藏时全部窗口消失。WindowServer 实际命中含两组间隙；锁屏环境只验证状态并明确跳过命中断言。
- [x] `OverlayControls` 创建透明播放面板；每个按钮独立大小与帧；通过 `OverlayLayout` 跟随歌词锚点；保留原有 AX 按钮目标、启停状态、文字色和拖动回调；禁用按钮仍可见但穿透鼠标，恢复可用后重新接收点击；运行 Swift 测试直到绿灯。

### Task 3: 集成、合成截图、打包本地 App

**Files:** Modify `README.md`; `docs/superpowers/specs/2026-09-30-centered-playback-row-design.md`（仅在实测需要修订时）；`docs/superpowers/plans/2026-09-30-centered-playback-row.md`.

- [x] 更新 README：右上四按钮与歌词下方居中播放三键、收起仅影响工具组、单块背景和约 4 pt 的邻接间距。
- [x] 运行 `./scripts/test-swift.sh`、`xcrun swiftc -target arm64-apple-macos13.0 -warnings-as-errors -framework AppKit -framework Foundation -framework ApplicationServices -typecheck Sources/DesktopLyrics/*.swift`、`cargo test`、`cargo fmt --all --check`、`cargo clippy --all-targets -- -D warnings`、`git diff --check`。
- [x] 构建不同 bundle ID 的 `dist-preview/网易云桌面歌词-居中播放预览.app`，通过 `--stdin` 持续注入合成短句、长句和等待状态，截取完整一块背景并确认无遮挡／无额外底板。
- [x] 停止预览和旧正式进程；备份 `dist/网易云桌面歌词.app` 至 `dist-backup/`；本地重建正式 App、`codesign --verify --deep --strict`，打开并确认进程正常。辅助功能授权只由用户控制。
- [x] 自审布局、播放安全和点击命中回归；`git commit` 并确认工作区干净。不添加 `origin`、不推送。

实测备注：正式 App 与 Rust 引擎已启动并校验签名。当前 macOS 会话处于锁屏，WindowServer 鼠标命中断言已明确标记 SKIPPED；屏幕解锁后运行 `./scripts/test-swift.sh` 可补做实际命中测试。代码和文档已在本地分支提交，不推送。
