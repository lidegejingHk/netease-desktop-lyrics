# 浮层窗口层级、整首歌进度与歌名 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复拖动后歌词和声浪被背景盖住；按整首歌显示声浪进度，缩紧双句间隔，在左上显示经验证的歌曲标题。

**Architecture:** 背景 NSPanel 独立低层，歌词与声浪仍为 `.floating`；由歌词窗坐标驱动所有层。Rust JSONL 增加从当前播放快照提供的 `duration_ms` 与只经验证后才发布的 `title`，详情请求在歌词请求结果发出之后异步完成，`LyricsSession` 用 ID + epoch 防切歌竞态；AppKit 保持一块背景、一排工具、一排播放和两行歌词排版。

**Tech Stack:** Rust/Cargo、Swift/AppKit macOS 13+、本地 ad-hoc App。

---

### Task 1: 拖动后内容仍在背景前

**Files:** `Sources/DesktopLyrics/OverlayFrameView.swift`, `tests/OverlayAppearanceTests/main.swift`.

- [x] 添加窗口顺序测试：实例化背景、歌词窗及声浪，按启动顺序 order front，然后重复 `setFrameOrigin`/`follow`；从 `CGWindowListCopyWindowInfo` 确认两内容窗在背景之前；锁定与解锁后亦成立。
- [x] 运行 `./scripts/test-swift.sh` 确认红灯，随后让背景窗层级低于 `.floating`，不改变按钮层级/拖动约束；复跑 Swift 测试并截图确认。

实测备注：单纯 `setFrameOrigin`/`follow` 不会改变同层顺序，红灯来自**鼠标按下**——AppKit 把被点击的窗口提到同层最前，点在外框空白后 91% 不透明的背景就盖住歌词与声浪（隔离验证：只把层级改回 `.floating`、屏蔽层级断言时，新断言报 "Clicking the background never hides lyrics or the waveform behind it"）。修复为 `OverlayFrame.backgroundLevel = .floating - 1`，锁定与解锁都对新断言成立。用真实 `CGEvent` 拖动独立预览包后截图复核：歌词两行、翻译、播放三键与声浪均在背景之前。

### Task 2: 整首歌曲声浪进度

**Files:** `src/lyrics_stream.rs`, `Sources/DesktopLyrics/main.swift`, `Sources/DesktopLyrics/WaveformRailView.swift`, `tests/OverlayAppearanceTests/main.swift`, `README.md`.

- [x] Rust tests 用有/无 `duration_ms` 的合成快照验证 intro/line JSON 字段和不暴露歌曲 ID；Swift 测试验证 1/4 时长为 25%，暂停冻结、跳转立即改变、缺失时长无伪进度但可动画。
- [x] Rust 事件携带 `position_ms`, `duration_ms`；Swift `WholeSongProgress` 对非零时长限幅计算 fraction，未知时长禁用进度轨但不禁用声浪动效；复跑 Rust/Swift 测试。

实测备注：`duration_ms` 以 `Option<u64>` 序列化，未知时长输出 `null`（Swift 解出 nil）。`WaveformRail.show(fraction:playing:)` 改为可空 fraction：`nil` 隐藏进度轨与柱状高亮、但 `playing` 时声浪继续动；暂停只冻结动效，不改变整首歌位置。合成 `--stdin` 预览验证 intro 在 30s/120s 时点亮轨道的左 1/4，缺失时长的事件只显示歌词不画进度。

### Task 3: 两句收紧与左上歌名

**Files:** `Sources/DesktopLyrics/LyricsView.swift`, `Sources/DesktopLyrics/OverlayFrameView.swift`, `src/lyrics.rs`, `src/lyrics_stream.rs`, `src/main.rs`, `Sources/DesktopLyrics/main.swift`, `tests/OverlayAppearanceTests/main.swift`, `README.md`.

- [x] Swift 测试含常见短句、两行双句和极端省略，断言主/副句的**可见文字区域**更近且不重叠、不触碰下排播放；左上标题单行截断，长歌名不覆盖右上操作，背景依旧可拖。
- [x] Rust 测试本地合成详情 JSON：状态码、单歌曲、精确 ID、标题边界和错误返回；`LyricsSession` 切歌或 unavailable 后拒绝旧标题结果；标题失败不影响已有歌词事件。
- [x] 让歌词的主/副句垂直位置相互靠近；新增单行左上标题显示于背景内容视图但不接管拖动。有效 ID 请求采用 HTTPS、体积/时间上限，歌词请求先返回后再异步请求歌名；只维护当前歌曲内存标题，Swift 状态事件清除旧歌名。复跑各项测试。

实测备注：副句与主句的**可见**间距固定为 12 pt（`LyricStack.gap`），成对居中、下沿至少留 4 pt，字体缩小后间距不变；单行状态仍垂直居中。标题放在背景内容视图左上、与工具同一行（`OverlayLayout.titleFrame`，右端与工具栏留 12 pt），`hitTest` 返回 nil 所以点标题仍能拖动整块浮层，空白标题与任何状态事件都清空它。歌名走同一条 `curl` HTTPS 路径（体积 64 KiB、连接 3 s／总 8 s 上限），只在返回单曲、ID 完全一致且标题非空时发布，超长标题在 120 字符处截断；真实请求已验证 `ids=[186016]` 返回“晴天”。

### Task 4: 打包验收及本地提交

**Files:** `README.md`, above implementation/tests/docs.

- [ ] `./scripts/test-swift.sh`、`xcrun swiftc -target arm64-apple-macos13.0 -warnings-as-errors -framework AppKit -framework Foundation -framework ApplicationServices -typecheck Sources/DesktopLyrics/*.swift`、`cargo test`、`cargo fmt --all --check`、`cargo clippy --all-targets -- -D warnings`、`git diff --check`。
- [ ] 构建独立 `dist-preview` App，用持续合成 `--stdin` 事件截含标题、长短句、等待、拖动后顺序的完整截图，确认内容不被盖住；停预览。自审协议隐私、歌名竞态和布局。
- [ ] 停正式 App、备份 `dist/网易云桌面歌词.app` 到 `dist-backup/`；重建正式包、签名校验并打开。代码每阶段完成后本地 commit，最后工作区干净，不推送。
