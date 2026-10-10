# 技术实现（架构细节）

README 第 3 节「项目架构」的展开版：进程分工、五条数据通道与浮层几何的实现细节。

![运行结构：网易云客户端（只读本地日志与控制菜单）→ Rust 引擎（HTTPS 歌词）→ Swift 宿主（JSON 事件流与 AXPress 播放控制）](architecture.svg)

# 技术实现（架构细节）

整体是**两个进程**：宿主 App（Swift/AppKit，`Sources/DesktopLyrics/`）负责所有窗口与鼠标交互；歌词引擎（Rust，`src/`）只读采集播放状态、请求歌词，并把结果写成 JSON 行。

下图是这套结构的运行关系与五条数据通道：

- **数据通道**。宿主把引擎作为子进程启动（`--lyrics-json --interval-ms 300`），逐行读取它的 stdout；每行是一条有界事件（`loading`／`title`／`intro`／`line`／`unavailable`），携带歌词文本、翻译、播放标记、估算位置 `position_ms`、时长 `duration_ms` 与短状态码，不含歌曲 ID。宿主限制单行 64 KiB、超限即丢弃，在主线程解码并刷新界面。`--stdin` 模式改为读合成事件，不启动引擎、也不控制真实播放器。
- **播放状态（Rust）**。只读解析网易云 Local Storage 的 LevelDB 物理日志（`leveldb_log.rs` 校验记录，`reader.rs`／`decoder.rs` 读取与解码），再与通过辅助功能读到的网易云「控制」菜单文案和启用状态（`accessibility.rs`，只读、不展开菜单）交叉印证；`timeline.rs` 用单调时钟估算位置、暂停时冻结时间轴，`playback.rs` 只在歌曲与状态互相确认后产出观测，`held_paused=true` 表示沿用同一进程内此前核验过的观测。
- **歌词与歌名（Rust）**。确认数字歌曲 ID 后，经系统 `/usr/bin/curl`（仅 HTTPS、不经 shell）请求 `music.163.com` 的歌词接口，`lrc.rs` 解析时间轴并配对原文与翻译；歌名走同域歌曲详情接口，限制体积与超时，ID 完全一致且标题非空才显示。不使用账号 Cookie，不落盘，缓存只活在本进程内。
- **播放控制（Swift）**。`PlaybackTransport.swift` 用辅助功能在网易云「控制」菜单里匹配唯一、启用且支持 AXPress 的菜单项并按下，不在播放器窗口做盲点击；AX 调用带 0.35 s 超时、串行在后台队列执行，结果回到主线程。可用性每 2 s 复查一次，动作失败后锁存为禁用，由菜单栏的「重新检查」解除。
- **桌面浮层（Swift/AppKit）**。不是一张大窗口，而是一组无边框 `NSPanel`：圆角背景＋单行歌名（`OverlayFrameView`）、歌词区（`LyricsView`）、工具条与播放键各自独立的图标命中窗口（`OverlayControls`，7 个图标面板＋2 个透明布局面板）、底部声浪（`WaveformRailView`）。全部位于 floating 层且不激活 App；只有图标接收鼠标事件，锁定后背景、歌词与声浪 `ignoresMouseEvents` 点击穿透。歌词带高度来自与 `layout()` 相同的测量（`LyricBand`），所以字号或留白变化只让浮层下缘移动；控件显隐由 `OverlayHover` 每 0.15 s 比较 `NSEvent.mouseLocation` 与背景范围决定，锁定的浮层收不到跟踪事件，因此不用 `NSTrackingArea`。拖动按位移增量移动，`OverlayVisibility` 约束整块浮层不越出可见屏幕；几何常量集中在 `OverlayLayout.swift` 与 `ToolbarPlacement.swift`，纯函数都有断言测试。样式经共享 `NSColorPanel` 调色后写入 `UserDefaults`。
- **构建与测试**。`scripts/build-app.sh` 组装 App：Rust release 引擎进 `Contents/Resources/`，`swiftc -O` 编译宿主进 `Contents/MacOS/`，改写 Info.plist 的 bundle id，ad-hoc 签名（引擎单独签 `…engine`）。`./scripts/test-swift.sh` 把宿主源码与 `tests/OverlayAppearanceTests/main.swift` 编成单二进制跑几何与交互断言，`cargo test` 覆盖引擎的日志解析、时间线与歌词逻辑。

