# 网易云音乐 macOS 播放状态探针

Rust 只读 CLI。当前阶段验证网易云 Mac 客户端的歌曲标识、播放位置与播放/暂停状态；**还没有歌词展示、悬浮窗，也不控制播放器**。

## 运行与权限

已在 Apple Silicon / macOS **26.6.2**、网易云音乐 `com.netease.163music` **3.1.12** 上实测。其他版本须重新验证。

macOS「系统设置 → 隐私与安全性 → 辅助功能」需允许运行本程序的终端（或正式 App）。CLI 不会主动弹授权框、点击菜单或修改系统设置。未授权时输出 `AccessibilityPermissionDenied`；菜单不可读取时输出 `MissingField("is_playing")`，不回退到 CoreAudio 猜测。

```bash
cargo test
cargo run -- --once
cargo run -- --samples 120 --interval-ms 500
```

不传参数则持续每 500 ms 采样；按 `Ctrl-C` 结束。输出示例（标识为示意值）：

```text
track=example-id raw_ms=148000 estimated_ms=148561 playing=true held_paused=false observed_t+720ms
```

- `track`：新 `lastPlaying` 记录的 `resourceId`，缺失时使用 `trackId`；不以歌名猜测歌曲。
- `raw_ms`：最近一次客户端本地**原始**位置（毫秒），刷新通常有滞后；`held_paused=true` 时是保留的**旧观测**，不是这次刚读出的值。
- `estimated_ms`：以原始位置和单调时钟估算的显示位置，**不是播放器实测值**；只有辅助功能明确识别“正在播放”才推进，暂停期间冻结。
- `playing`：通过 macOS Accessibility **只读**读取网易云「控制」菜单的“暂停”（播放中）/“播放”（暂停或空闲）动作标题。它不是网易云公开的播放 API；菜单改版或权限变化时会失效。
- `held_paused`：在同一个 CLI 和同一个网易云主进程内，此曲目此前已被验证；暂停时没有新原始记录，沿用最后一首与冻结位置。若暂停后曲目暗中变化且没有新记录，此值可能暂时过期。
- `observed_t+…ms`：距离 CLI 启动的单调时间，不是墙上时钟。

异常以 `unavailable: …` 明确输出：`NotRunning`、`NoSong`、`MissingDirectory`、`MissingField(…)`、`AccessibilityPermissionDenied`、`PermissionDenied`、`FormatChanged`、`ProcessQueryFailed`、`ReadFailed` 等。冷启动时若已暂停且没有**新**本地记录，宁可 `NoSong`，不读 `.ldb` 历史伪造当前歌曲；恢复播放后等待新记录再展示。遇到状态、权限或记录格式错误清除旧快照。

## 数据来源与边界

只读扫描本机目录：

```text
~/Library/Application Support/com.netease.163music/Documents/storage/CEFCache/Local Storage/leveldb/*.log
```

每个日志只读最多末尾 128 KiB，按 LevelDB 记录边界和 CRC32C 校验；只把**最新一条完整记录**的 `lastPlaying` 当作新观测。半写记录、日志轮转或最新记录是其他键时，短时缓存最多 6 秒，不用文件修改时间刷新旧歌。暂停时继续显示的旧观测由明确的 `held_paused=true` 标识，且只在同一 CLI / 网易云主进程生命周期内有效。客户端内部目录、编码和菜单项均未公开保证，升级后可能失效。

不写网易云数据、不登录、不请求网络、不持久化用户播放记录。调试时**不要上传本机 `.log` / `playingList` / 数据库**；提交测试只使用合成记录。编码格式参考 [CloudLyrics-for-macOS](https://github.com/hellomyonly55/CloudLyrics-for-macOS)（MIT License）；菜单读取思路参考 [CloudMusicFocus](https://github.com/eruimisshy/CloudMusicFocus)，未复制其 GPL 源码。历史产品灵感来自 [NeteaseMusicLrcHelper](https://github.com/Lensual/NeteaseMusicLrcHelper)，不移植 Windows 内存偏移。

实机动作记录见 [`docs/validation-checklist.md`](docs/validation-checklist.md)；自动测试不能代替客户端切歌、拖动、退出和重启验收。
