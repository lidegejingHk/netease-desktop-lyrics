# 网易云音乐 macOS 桌面歌词

本地可运行的桌面歌词 MVP：**Rust** 只读识别网易云音乐的当前歌曲、播放位置和播放/暂停状态，获取并同步逐行歌词；**Swift/AppKit** 仅负责菜单栏与桌面浮层。不会注入或控制网易云音乐。

在 Apple Silicon、macOS **26.6.2**、网易云音乐 `com.netease.163music` **3.1.12** 上验证。网易云内部格式、菜单及歌词接口均非公开稳定 API，其他客户端版本须重新验收。

## 独立 App（推荐）

需要本机安装 Rust/Cargo、Apple Command Line Tools（`xcrun swiftc`）、网易云音乐，并联网。首次构建或代码更新后：

```bash
./scripts/build-app.sh
open "dist/网易云桌面歌词.app"
```

也可以在 Finder 双击 `dist/网易云桌面歌词.app`。App 自带 Rust 引擎，**不会借用终端的辅助功能授权**。本机已验证授权后的独立 App 可显示歌词。首次启动若出现“需要辅助功能权限”，在「系统设置 → 隐私与安全性 → 辅助功能」中允许**网易云桌面歌词**，然后退出并重新打开。不会代替你更改系统授权。

构建脚本使用本机 ad-hoc 签名，非公证/商店分发。**更新 App 会重新签名**：macOS 可能不再认可旧的辅助功能授权；若新包再次提示无权限，从辅助功能列表中移除旧的“网易云桌面歌词”，重新添加同一路径下的 App、打开开关，然后重启 App。不要在运行时重新构建或移动 App。

## 桌面就近操作

歌词框**内部右上角**有一排操作：**✥ 拖动位置、锁定/解锁、歌词样式、收起**。按钮视觉上贴在歌词框内，但保留独立的可点击窗口；锁定时歌词区域点击穿透，按钮仍可操作。收起后右上角只保留一个可展开的小按钮；较长的主歌词与文字背底会避开展开的按钮，收起后短句仍居中。按钮图标跟随歌词文字颜色。设置窗可分别选择浮层背景色、文字颜色、文字背底色，调节浮层背景与文字背底不透明度（0% 为完全透明，100% 为不透明），变化即时生效。文字背底仅包住文本，默认完全透明；“恢复默认”还原原来的深色背景和白字。样式、工具条收起、位置和锁定状态只保存在本机 App 偏好设置，不保存音乐资料。

菜单栏音符仍保留显示/隐藏、位置锁定/解锁、歌词样式、辅助功能设置和退出作为兜底；隐藏歌词会一起隐藏工具条，重新显示需使用菜单栏。

## 终端脚本模式（备选）

若使用下面的脚本，请在辅助功能设置中允许**运行命令的终端**；它不会复用独立 App 的授权。

```bash
./scripts/run-desktop.sh
```

首次运行会在 `dist/` 构建应用；后续直接从该目录启动。关闭命令所在的终端或按 `Ctrl-C` 会结束浮层。改代码后先退出 App，再运行 `./scripts/build-app.sh`；不要在应用运行时重新构建。

本机检查：`./scripts/test-swift.sh`（样式和工具条布局）、`cargo test`（Rust 引擎）。

## 诊断与隐私

```bash
cargo test
cargo run -- --once
cargo run -- --samples 120 --interval-ms 500
cargo run -- --lyrics-json --once
```

不传参数则每 500 ms 持续采样。普通 CLI 输出歌曲 ID、原始位置 `raw_ms`、估算位置 `estimated_ms`、`playing`、`held_paused`；**普通 CLI 可能显示真实歌曲 ID，不要上传输出**。JSON 行流只包含当前歌词、播放标记、相对位置与短状态码，不含歌曲 ID 或原始日志；它本身仍会显示歌词，亦请勿分享真实输出。`raw_ms` 是最近一次本地记录，不一定实时；`estimated_ms` 用单调时钟估算，暂停时冻结；`held_paused=true` 表示沿用同一进程内此前核验过的观测，不是新采样。

歌词由数字歌曲 ID 向网易云 HTTPS 歌词接口请求，网络失败稍后重试；不使用账号 Cookie，不落盘歌词或播放历史。只读扫描网易云本机 `~/Library/Application Support/com.netease.163music/Documents/storage/CEFCache/Local Storage/leveldb/*.log` 的最新完整记录，并只读查询其辅助功能「控制」菜单，不点击播放器。权限、网络、格式变化、没有逐行歌词等问题会在浮层显示状态而非沿用旧歌词。客户端内网协议或歌词接口变更可能导致失效。

冷启动已暂停而没有新的本地播放记录时，宁可显示“等待当前歌曲”，不猜测历史歌曲；继续播放后等待新记录。首版不支持字级卡拉 OK、离线歌词、自动补第三方歌词源。验证记录和未覆盖场景见 [`docs/validation-checklist.md`](docs/validation-checklist.md)。灵感来自 [NeteaseMusicLrcHelper](https://github.com/Lensual/NeteaseMusicLrcHelper)，格式参考 [CloudLyrics-for-macOS](https://github.com/hellomyonly55/CloudLyrics-for-macOS)（MIT）；辅助功能思路参考 [CloudMusicFocus](https://github.com/eruimisshy/CloudMusicFocus)，没有复制其 GPL 源码。
