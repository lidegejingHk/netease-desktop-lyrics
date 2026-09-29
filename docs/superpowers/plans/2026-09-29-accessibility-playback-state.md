# Accessibility Playback State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让当前 Rust CLI 在本机网易云 3.1.12 上准确报告播放/暂停，暂停后仍能冻结最后一首的时间，不将 CoreAudio 音频进程活动当作播放状态。

**Architecture:** AX FFI 只读「控制」菜单的播放/暂停动作标题；LevelDB 读取返回新记录/短时缓存来源标记；纯状态机组合 PID、AX、原始观测和时间模型。任何权限/菜单/格式失败都返回诊断，绝不推断为播放。继续只交付 CLI，歌词和窗口后续独立规划。

**Tech Stack:** Rust 2021, macOS ApplicationServices/CoreFoundation FFI, existing LevelDB parser, `cargo test/fmt/clippy`。当前已隔离在 `feat/playback-source-validation` worktree，基线 41 tests pass。环境 macOS 26.6.2、网易云 3.1.12，终端 `AXIsProcessTrusted=true`。设计见 `docs/superpowers/specs/2026-09-29-accessibility-playback-state-design.md`。

---

## 文件与职责

- `src/accessibility.rs`（新）：拥有 CF 对象并释放，限定访问 AXMenuBar →「控制」→ AXMenu → AXMenuItem；无任何 UI Action；识别精确标题，拒绝多解、菜单缺失与禁用项。
- `src/reader.rs`：新增 `ReadObservation { raw: RawPlayback, fresh: bool }` 与 `read_observation()`；旧 `read()` 适配现有测试。`fresh=false` 只能来自同进程 6 秒缓存，不重新读取旧记录作为新快照。
- `src/playback.rs`（新）：纯 `PlaybackTracker`，接受 AX 状态及 Reader 观测，输出 `PlaybackUpdate {raw, estimated_position_ms, is_playing, held_paused}`；暂停保持只限相同 PID 和同一个运行中的 CLI；恢复后等待新原始记录。
- `src/lib.rs`：导出新模块及 `Snapshot::held_paused`。
- `src/main.rs`：先发现 PID、检测 AX 状态，再取原始观测并交给状态机；明确权限诊断，移除 CoreAudio 在生产路径上的使用，打印 `held_paused`。
- `README.md`、`docs/validation-checklist.md`：运行、授权、冷启动/历史值约束、真实动作验收。

### Task 1: 只读 AX 状态源

- [ ] Step 1: 在 `src/accessibility.rs` 添加纯函数测试：`"暂停"/"Pause"→Playing`，`"播放"/"Play"→Paused`，非精确标题、disabled、重复或冲突动作→Unavailable；加入菜单角色/标题范围的合成选择测试。运行 `cargo test --lib accessibility`，预期红。
- [ ] Step 2: 实现 ApplicationServices 的 `AXIsProcessTrusted`、`AXUIElementCreateApplication`、`AXUIElementCopyAttributeValue`、`AXUIElementSetMessagingTimeout` 和 CoreFoundation `CFRelease`/类型检查/字符串转换/数组读取。`OwnedCF` 在 Drop 里 release；CFArray 中借出元素前 retain。只读 `AXMenuBar` / `AXChildren` / `AXRole` / `AXTitle` / `AXEnabled`，最多 16 个菜单栏项、2 个目标菜单、32 个菜单项，每项超时 300ms；角色与标题必须精确匹配。暴露 `playback_state(pid) -> Result<PlaybackState, AxError>`，错误分 `PermissionDenied` / `Unavailable`；不读取歌词、帐号、窗口内容，不调用 `AXPress`。
- [ ] Step 3: `src/lib.rs` 导出模块；运行 `cargo test --lib accessibility && cargo clippy --all-targets -- -D warnings`，再运行真实只读状态探针（匿名输出）。`git add src/accessibility.rs src/lib.rs && git commit -m "feat: read Netease playback state from accessibility menu"`。

### Task 2: 标注 LevelDB 原始观测新鲜度

- [ ] Step 1: 在 `src/reader.rs` 增加失败测试：新日志首读 `fresh=true`，同一日志再读 `fresh=false`，无新记录超过 6 秒返回 None。只用已有合成 LevelDB fixtures；运行 `cargo test --lib reader`，预期红。
- [ ] Step 2: 引入 `ReadObservation`，`read_observation()` 复用当前 `read()` 主体；验证新 record 时设 true，`recent_cache()` 时设 false，旧 `read()` 调用新方法并只返回 `.raw`。日志轮转与坏记录行为保持不变。
- [ ] Step 3: 运行 `cargo test --lib reader && cargo fmt --all --check && cargo clippy --all-targets -- -D warnings`；`git add src/reader.rs && git commit -m "feat: distinguish fresh playback records from short cache"`。

### Task 3: 暂停保持与恢复门禁

- [ ] Step 1: 在新建 `src/playback.rs` 写失败的确定性测试：播放→暂停(无 fresh)→经过 8 秒仍为同一 track、冻结 `estimated_position_ms` 且 `held_paused=true`；恢复但未见 fresh→NoSong；恢复收到 fresh→按新原始位置重新开始；冷启动 paused/无观测→NoSong；PID 切换及 AX/Reader 错误清除保持值；暂停时新 track 或位置变化更新快照。运行 `cargo test --lib playback`，预期红。
- [ ] Step 2: 新建纯状态机 `PlaybackTracker`，方法 `reset()`、`set_pid(pid)`、`update(state, Result<Option<ReadObservation>, ReadError>, now_ms) -> Result<PlaybackUpdate, Diagnostic>`。保存 `last_state`、最近成功 raw+shown 与 `Timeline`。Playing 在刚从 Paused 转来时必须有 fresh；正常 Playing 只接受 Reader 最近 6 秒观测；Paused 时 fresh 重校正，否则仅保留已有 last_good 并冻结。缺项/错误清空快照；跨 PID 绝不复用，冷启动没有旧快照。
- [ ] Step 3: 在 `src/lib.rs` 导出模块、给 `Snapshot` 增加 `held_paused`；运行 `cargo test --lib playback && cargo test && cargo clippy --all-targets -- -D warnings`；`git add src/playback.rs src/lib.rs && git commit -m "feat: freeze verified playback while paused"`。

### Task 4: CLI 连线与现场验收

- [ ] Step 1: 为 `src/main.rs` 中 AX 错误映射、PID 切换、暂停标记输出增加失败测试；运行 `cargo test --bin netease-lyrics-rs`，预期红。
- [ ] Step 2: `sample()` 中 PID 变化时 `reader.reset(); tracker.set_pid(pid)`；优先读取 AX 状态，权限缺失报 `AccessibilityPermissionDenied`，菜单缺失报 `MissingField("is_playing")`；原始数据调用 `read_observation()`；Tracker 更新，输出 raw/estimated/playing/held_paused。`NotRunning`/AX/Reader 错误清状态；CoreAudio 不再参与结果。源不可用绝不 fallback 猜值。
- [ ] Step 3: 文档改成 AX 授权和故障分类。运行 `cargo fmt --all && cargo test && cargo fmt --all --check && cargo clippy --all-targets -- -D warnings`。
- [ ] Step 4: 实机匿名输出验证：播放 >8 秒、暂停 >8 秒、恢复、切歌及拖动；记录匹配和不能自动判断的限制，不写原始歌曲 ID/歌词到仓库。如 UI 可安全操作，测试完成后恢复用户原有暂停状态；如权限或真实 UI 行为不可验证，明确说明，不谎报完成。
- [ ] Step 5: `git add src/main.rs README.md docs/validation-checklist.md && git diff --cached --check && git commit -m "feat: use accessibility state in playback probe"`。最终重新执行 `cargo test && cargo fmt --all --check && cargo clippy --all-targets -- -D warnings && git status --short --branch`。
