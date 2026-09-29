# 网易云音乐 macOS 桌面歌词

本地可运行的桌面歌词 MVP：**Rust** 只读识别网易云音乐的当前歌曲、播放位置和播放/暂停状态，获取并同步逐行歌词；**Swift/AppKit** 仅负责菜单栏与桌面浮层。不会注入或控制网易云音乐。

在 Apple Silicon、macOS **26.6.2**、网易云音乐 `com.netease.163music` **3.1.12** 上验证。网易云内部格式、菜单及歌词接口均非公开稳定 API，其他客户端版本须重新验收。

## 直接运行（推荐）

需要本机安装 Rust/Cargo、Apple Command Line Tools（`xcrun swiftc`）、网易云音乐，并联网。先在「系统设置 → 隐私与安全性 → 辅助功能」中允许**用于运行命令的终端**；本程序不会代替你开启权限。

```bash
./scripts/run-desktop.sh
```

首次运行会在 `dist/` 中构建应用；后续直接从该目录启动，直到你手动重新构建。浮层默认出现在屏幕下方。菜单栏的音符图标提供显示/隐藏、位置锁定/解锁、打开辅助功能设置和退出；未锁定时可拖动浮层，锁定后点击穿透。显示、锁定和位置偏好保存在本机 App 的用户设置，不保存播放记录。退出菜单或在命令所在终端按 `Ctrl-C` 结束。代码改动后请先运行 `./scripts/build-app.sh`，**不要在应用运行时重新构建**。

## 独立 App

```bash
./scripts/build-app.sh
open "dist/网易云桌面歌词.app"
```

也可以在 Finder 双击 `dist/网易云桌面歌词.app`。此模式由 App 启动自带的 Rust 引擎，**不会借用终端的辅助功能授权**；首次启动若显示“需要辅助功能权限”，在系统设置中允许此 App（以系统实际列出的项目为准），退出并重新打开。当前机器尚未为独立 App 授权，因此只实测了其权限提示和子进程启动；可立即使用的已验证路径是上面的终端脚本。构建脚本使用本机 ad-hoc 签名，非公证/商店分发；保持 App 路径固定，重建或移动后如权限失效需重新核查系统设置。

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
