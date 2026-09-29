# 网易云音乐 macOS 播放状态探针

Rust 只读 CLI。先验证网易云 Mac 客户端的歌曲标识、播放进度、播放/暂停状态；**本阶段不显示歌词、不控制播放器、不提供悬浮窗**。

## 运行

环境：macOS / Apple Silicon；当前只在网易云音乐 `com.netease.163music` **3.1.12**、macOS **26.6.2** 上做过只读采样。其他版本需重新验证。

```bash
cargo test
cargo run -- --once
cargo run -- --samples 120 --interval-ms 500
```

不传参数则持续每 500 ms 采样；按 `Ctrl-C` 结束。输出示例（标识为示意值）：

```text
track=example-id raw_ms=148000 estimated_ms=148561 playing=true observed_t+720ms
```

- `track`：本地记录中的 `resourceId`，缺失时使用 `trackId`；不以歌名猜测歌曲。
- `raw_ms`：当前读取到的网易云客户端本地**原始**播放位置，单位毫秒；可能滞后数秒。
- `estimated_ms`：依据最近有效位置和进程输出活动估算的显示位置，**不是播放器实测值**；切歌、跳转、暂停时按采样结果校准。
- `playing`：CoreAudio 对网易云主进程及 Helper 进程的输出活动判断；不是网易云公开的播放状态 API，也可能在设备/版本变化时与实际播放不符。
- `observed_t+…ms`：距离本次 CLI 启动的单调时间，不是墙上时钟。

异常以 `unavailable: …` 明确输出：`NotRunning`（未检测到主进程）、`NoSong`（当前日志没有可用记录）、`MissingDirectory`、`MissingField(…)`、`PermissionDenied`、`FormatChanged` 等。没有可靠播放状态时不返回貌似完整的快照。

## 数据来源与边界

只读扫描当前客户端使用的目录：

```text
~/Library/Application Support/com.netease.163music/Documents/storage/CEFCache/Local Storage/leveldb/*.log
```

每个日志只读最多末尾 128 KiB。`lastPlaying` 来自客户端内部存储，并非公开稳定接口；目录、编码、字段或刷新节奏可能随网易云升级改变。检测到数据失效时应重新验证，**不要将 `.ldb` 旧记录当成实时数据**。日志轮转时仅在同一探针进程里短暂保留最近快照，网易云主进程重启或退出会清除缓存。

不写网易云数据、不登录、不请求网络、不持久化用户播放记录。运行命令和调试时**不要上传本机 `.log` / `playingList` / 数据库**；提交测试只使用合成记录。源代码使用 [CloudLyrics-for-macOS](https://github.com/hellomyonly55/CloudLyrics-for-macOS)（MIT License）描述的本地 `lastPlaying` 格式与 CoreAudio 思路；未复制其源码。历史产品灵感来自 [NeteaseMusicLrcHelper](https://github.com/Lensual/NeteaseMusicLrcHelper)，不移植 Windows 内存偏移。

## 第一阶段验收

自动测试验证本地记录解码、日志轮转、异常分类、进程选择和时间模型；它们不代替真实播放器操作。请按 [`docs/validation-checklist.md`](docs/validation-checklist.md) 手动完成启动、切歌、暂停/恢复、前后拖动、退出检查。只有 ID、真实进度、播放状态均与客户端一致，才进入歌词获取与桌面窗口阶段。
