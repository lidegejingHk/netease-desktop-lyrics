# 诊断与隐私

## 诊断命令

```bash
cargo test
cargo run -- --once
cargo run -- --samples 120 --interval-ms 500
cargo run -- --lyrics-json --once
```

不传参数则每 500 ms 持续采样。普通 CLI 输出歌曲 ID、原始位置 `raw_ms`、估算位置 `estimated_ms`、`playing`、`held_paused`；**普通 CLI 可能显示真实歌曲 ID，不要上传输出**。JSON 行流只包含当前歌词、播放标记、估算位置 `position_ms`、歌曲时长 `duration_ms`（未解出时为 `null`）与短状态码，不含歌曲 ID 或原始日志；它本身仍会显示歌词，亦请勿分享真实输出。`raw_ms` 是最近一次本地记录，不一定实时；`estimated_ms` 用单调时钟估算，暂停时冻结；`held_paused=true` 表示沿用同一进程内此前核验过的观测，不是新采样。

## 隐私

歌词由数字歌曲 ID 向网易云 HTTPS 歌词接口请求，网络失败稍后重试；不使用账号 Cookie，不落盘歌词或播放历史。歌曲名是对**同一个已验证数字歌曲 ID**的同域歌曲详情接口单独请求：严格限制体积与超时，只在返回单曲、ID 完全一致且标题非空时显示；该请求在歌词请求返回后才发出，不拖慢歌词，失败、离线或切歌后的迟到结果都会隐藏，缓存只存在于当前进程内存，退出即清。只读扫描网易云本机 `~/Library/Application Support/com.netease.163music/Documents/storage/CEFCache/Local Storage/leveldb/*.log` 的最新完整记录；播放控制通过辅助功能读取网易云的「控制」菜单，仅在操作唯一、启用且支持 AXPress 时重新校验并执行，不点击播放器窗口。权限、网络、格式变化、没有逐行歌词等问题会在浮层显示状态而非沿用旧歌词。客户端内网协议或歌词接口变更可能导致失效。

冷启动已暂停而没有新的本地播放记录时，宁可显示“等待当前歌曲”，不猜测历史歌曲；继续播放后等待新记录。首版不支持字级卡拉 OK、离线歌词、自动补第三方歌词源。验证记录和未覆盖场景见 [`validation-checklist.md`](validation-checklist.md)。
