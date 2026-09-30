# 浮层工具与样式面板交互 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让拖动把手的图标可读，样式面板能用 Esc／⌘W／点面板外关闭，颜色面板出现在它唤起的位置旁边。

**Architecture:** `OverlayControls` 的把手仍是独立小窗口，只把字形换成系统四向移动符号；`StyleSettingsPanel` 自己处理 Esc／⌘W／外部点击并在关闭时清理监视器与共享颜色面板；颜色面板位置由纯函数计算，`AnchoredColorWell` 在激活前应用。

**Tech Stack:** Swift/AppKit（macOS 13+）、Rust/Cargo（不改动）、本地 ad-hoc 签名。

---

### Task 1: 拖动把手图标

**Files:** `Sources/DesktopLyrics/OverlayControls.swift`, `tests/OverlayAppearanceTests/main.swift`.

- [x] 测试断言把手子视图是图片视图、图像非空、tint 等于文字颜色、锁定后透明度低于 0.5 且仍可点击穿透；先红灯。
- [x] 换成 `arrow.up.and.down.and.arrow.left.and.right`，保留 42%/94% 透明度与穿透；复跑 Swift 测试。

### Task 2: 样式面板的关闭方式

**Files:** `Sources/DesktopLyrics/StyleSettingsPanel.swift`, `tests/OverlayAppearanceTests/main.swift`.

- [x] 测试 Esc、⌘W、面板外点击都关闭面板，点面板本身与共享颜色面板不关闭；先红灯。
- [x] 用 `NSPanel` 子类处理 Esc／⌘W，本地与全局鼠标监视器处理外部点击（面板关闭时移除监视器）；复跑 Swift 测试。

实测备注：`StyleSettingsWindow.handleDismissKey` 同时处理 Esc（keyCode 53）与 ⌘W，`cancelOperation` 兜住第一响应者吃掉 Esc 的情况；外部点击用本地+全局鼠标监视器，`isWatchingOutsideClicks` 让测试能断言监视器随关闭释放。

### Task 3: 颜色面板定位

**Files:** `Sources/DesktopLyrics/StyleSettingsPanel.swift`, `tests/OverlayAppearanceTests/main.swift`, `README.md`.

- [x] 测试纯函数：默认放样式面板左侧并与色块中线对齐；左侧放不下时放右侧；上下越界时夹紧到可见区域。
- [x] `AnchoredColorWell` 在 `mouseDown` 里先把共享颜色面板摆好再 `super`；更新 README 描述关闭方式与颜色面板位置；复跑测试。

实测备注：真实预览包日志确认 `mouseDown` 时先算出 anchor（如 `(1064, 368.5)`）再 `super`，颜色面板随后在锚点显示（`visible=true frame=(1064, 368, 250, 397)`，正好贴在样式面板左侧、与被点色块对齐）；点样式面板内与颜色面板内都不会关闭，点其他 App 或在浮层上点击会关闭，Esc 与 ⌘W 各关闭一次。

### Task 4: 验收与本地提交

实测备注：预览包已用 `--stdin` 合成事件 + 真实 `CGEvent` 点击/按键逐项验证并把日志与截图留档；产物已移到废纸篓。

**Files:** `README.md`, above implementation/tests/docs.

- [x] `./scripts/test-swift.sh`、`xcrun swiftc -target arm64-apple-macos13.0 -warnings-as-errors -framework AppKit -framework Foundation -framework ApplicationServices -typecheck Sources/DesktopLyrics/*.swift`、`cargo test`、`cargo fmt --all --check`、`cargo clippy --all-targets -- -D warnings`、`git diff --check`。
- [x] 独立 `dist-preview` 预览包截图确认把手图标、面板关闭方式与颜色面板位置；停预览并清理预览产物。
- [x] 自审监视器生命周期、颜色面板豁免与布局回归；代码每阶段完成后本地 commit，最后工作区干净，不推送。
