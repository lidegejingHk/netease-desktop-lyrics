# 歌词框内嵌工具条 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把可点击的歌词操作放在歌词框右上角，并防止长句与按钮重叠。

**Architecture:** 沿用独立 `NSPanel`，更改纯函数 `ToolbarPlacement` 为内部右上角屏幕安全布局。AppController 将工具条实际局部矩形交给 `LyricsView`；视图仅在实际冲突时改变文字标签区域。工具条高于歌词窗口，且透明、无独立阴影；歌词窗口点击穿透不影响其按钮。

**Tech Stack:** Swift/AppKit（macOS 13），Rust/Cargo，现有 `scripts/test-swift.sh` 与本地 ad-hoc 打包脚本。

---

## 文件职责

- `Sources/DesktopLyrics/ToolbarPlacement.swift`：屏幕安全的框内右上角位置。
- `Sources/DesktopLyrics/OverlayControls.swift`：透明且独立可交互的工具条、颜色同步与收起/展开。
- `Sources/DesktopLyrics/LyricsView.swift`：文字与背景片避开真实的工具条占用矩形。
- `Sources/DesktopLyrics/main.swift`：同步窗口位置、样式与歌词视图占用区域。
- `tests/OverlayAppearanceTests/main.swift`：布局/视觉状态与按钮回归测试。
- `README.md`：更新操作说明与可能重新授权的注意事项。

### Task 1：内部锚定与工具条外观

- [ ] 先在 `tests/OverlayAppearanceTests/main.swift` 将原先期望的上方/下方坐标改为框内坐标，添加局部与屏幕交集/右侧锚定断言；运行 `./scripts/test-swift.sh` 确认红灯。
- [ ] 在 `ToolbarPlacement.swift` 中令 `desiredX=overlay.maxX-size.width-10`、`desiredY=overlay.maxY-size.height-6`；先把目标坐标夹到 `overlay.intersection(screen)`（仅当该轴足够容纳窗口及两侧 8 pt），否则夹到屏幕 `visibleFrame`。没有显示器时直接返回目标坐标。
- [ ] 在 `OverlayControls.swift` 去除背景实色、边框、圆角与工具条阴影；将其 `panel.level` 设为 `NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)`；添加 `applyStyle(_:)`，用 `OverlayStyle.nsColor(style.textRGB) ?? .white` 更新手柄与按钮图标颜色，锁定时仅降低手柄 alpha。
- [ ] 更新测试，运行 `./scripts/test-swift.sh` 与 `xcrun swiftc -target arm64-apple-macos13.0 -warnings-as-errors -framework AppKit -framework Foundation -typecheck Sources/DesktopLyrics/*.swift`；提交几何、工具条及其测试。

### Task 2：长句避让与生命周期同步

- [ ] 在 `tests/OverlayAppearanceTests/main.swift` 增加真实 `LyricsView` 标签/文字背底帧断言：普通短句仍居中；长句和有背底的句子不与工具条相交；更改占用矩形模拟收起后恢复居中。运行 `./scripts/test-swift.sh` 确认红灯。
- [ ] 在 `LyricsView.swift` 增加 `setControlsFrame(_:)`；布局前保留默认标签框，只在标签实际文字宽度或文字背底与工具条占用矩形冲突时，选择较宽的左/右可用区域作为标签框。将 `layoutChip` 的中心改为 `label.frame.midX` 且限制片宽不超过 `label.frame.width`。
- [ ] 在 `main.swift` 的 `updateControlsPosition()` 调用 `controls.follow` 后，将 `controls.panel.frame` 转换成 `panel` 局部坐标并传给 `content.setControlsFrame`；初始化/收起/拖动/跨屏复用此路径；设置更改时对 `controls` 同步调用 `applyStyle(_:)`。
- [ ] 运行 `./scripts/test-swift.sh`、Swift macOS 13 编译、`cargo test`、`cargo fmt --check`、`cargo clippy --all-targets -- -D warnings`；提交代码与测试。

### Task 3：预览、文档、正式包

- [ ] 在 `README.md` 将“浮层右上方”改为“歌词框内右上角”，说明长句避让、收起与点击穿透；提交文档。
- [ ] 使用 `./scripts/build-app.sh --output dist-preview/网易云桌面歌词-预览.app --bundle-id com.local.netease-desktop-lyrics-preview` 构建预览包，`codesign --verify --deep --strict` 校验；用合成 `--stdin` 歌词验证视觉、工具条锁定/收起/展开/样式与文字避让。预览包的辅助功能权限与正式 App 独立。
- [ ] 自查所有变更与 `git diff --check`，确保工作区干净；只退出正在运行的正式 App，先备份，再执行 `./scripts/build-app.sh` 一次，签名校验并 `open dist/网易云桌面歌词.app`。不再重建正式包；如果辅助功能权限失效，在设置页停下让用户手动授权，之后重启验证真实歌词。

**完成标准：**工具条位于截图红框所示内部区域；长句与文字底片不遮挡按钮；锁定可点击穿透但工具条可点；正式 App 已安装并能显示歌词或明确提示授权步骤；所有代码均已在本地提交，未推送。
