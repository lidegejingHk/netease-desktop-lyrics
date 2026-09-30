# 桌面歌词单体浮层 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把现有分层窗口呈现为一块紧凑、整体可拖、锁定可穿透的桌面歌词 App。

**Architecture:** `OverlayLayout` 统一几何，`OverlayFrame` 独自绘制可调背景并把解锁后的空白拖动 delta 交给 `AppController`；歌词、工具背景、声浪三个透明窗口仅承载内容，按钮各自的小窗口保持点击和锁定穿透。`AppController` 以歌词窗口位置为单一坐标源驱动其余窗口及位置持久化。

**Tech Stack:** Swift/AppKit（macOS 13+）、Rust/Cargo、本地 ad-hoc 签名。

---

### Task 1: 单一背景与紧凑间距

**Files:** `Sources/DesktopLyrics/OverlayLayout.swift`, `OverlayFrameView.swift`, `OverlayControls.swift`, `LyricsView.swift`, `WaveformRailView.swift`, `tests/OverlayAppearanceTests/main.swift`。

- [ ] 在 Swift 测试中要求外框为 880 × 236 pt，歌词／顶栏／底栏均处于指定内缩位置且间隔分别为 8／6 pt；三个内区透明、无独立描边，外框背景 alpha 与样式直接一致。运行 `./scripts/test-swift.sh` 验证红灯。
- [ ] 更新几何和绘制；可选的文字背底保留原有设置与测试。Swift 测试绿灯。

### Task 2: 空白拖动与锁定点击穿透

**Files:** `Sources/DesktopLyrics/OverlayFrameView.swift`, `Sources/DesktopLyrics/main.swift`, `tests/OverlayAppearanceTests/main.swift`。

- [ ] 增加 WindowServer 命中测试：解锁后灰色空白及按钮间隙命中外框，锁定后穿透，图标按钮仍命中；模拟空白拖动并验证整组窗口联动及屏幕边界。测试先红灯。
- [ ] 外框加拖动事件回调，应用用统一位置约束移动歌词窗口并联动外框、声浪和工具栏；锁定状态同步外框及歌词命中。避免窗口委托间的递归；测试绿灯。

### Task 3: 集成验收与正式本地 App

**Files:** `README.md`；根据验收修复对应实现及测试。

- [ ] README 与界面行为保持一致；运行 `./scripts/test-swift.sh`、macOS 13 严格 Swift typecheck、`cargo test`、`cargo fmt --all --check`、`cargo clippy --all-targets -- -D warnings`、`git diff --check`。
- [ ] `./scripts/build-app.sh --output dist-preview/网易云桌面歌词-整体预览.app --bundle-id com.local.netease-desktop-lyrics-unified-preview`，`--stdin` 连续注入不含真实歌曲信息的短句、长句和等待态。截取完整浮层，核对无三区独立底色、间距、控件、歌词与声浪。
- [ ] 退出原 App，备份 `dist/网易云桌面歌词.app` 至 `dist-backup/`；正式重建、`codesign --verify --deep --strict` 并打开。确认本地提交及干净工作区，不推送；辅助功能授权若失效仅告知用户手动处理。
