# 网易云 macOS 播放数据源验证 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 在本机网易云音乐 3.1.12 上，用只读 Rust CLI 验证歌曲 ID、准确播放进度、暂停状态是否可以可靠获取，并输出是否能进入歌词阶段的结论。

**Architecture:** 从该版本实际活跃的 CEF LevelDB `.log` 读 `lastPlaying`，独立解码；用 CoreAudio 查询网易云主进程和 Helper 的输出活动；用纯函数式时间模型校验暂停与跳转。不修改客户端文件，不取 Windows 内存偏移，不做歌词请求或窗口。

**Tech Stack:** Rust 2021 / cargo 1.95、`aes` + `ecb` + `base64` + `serde_json`、macOS CoreAudio C ABI、`ps`、`tempfile`（仅测试）。目标 macOS 26.6.2 / arm64，网易云 `com.netease.163music` 3.1.12。

---

## 执行状态（2026-09-29）

Task 1–5、Task 6 的 CLI 与自动检查已完成，代码在 `feat/playback-source-validation`，未合入 `main`。2026-09-29 用户现场验证发现：暂停时 `playing=true`，估算进度持续前进，约 6 秒后 `NoSong`；当前方案暂停验收未通过，不进入歌词同步阶段。切歌、拖动、退出等仍待测；详见 `docs/validation-checklist.md`。下列步骤保留原实施顺序，**审查后的实际源码和 `README.md` 优先于早期代码示例**：

- `e147cda`：CoreAudio 部分进程状态未知时不误判暂停。
- `c3f1e34`、`2ebfbc2`、`53bc00a`：LevelDB 按物理记录边界和 CRC32C 校验，只接受最新完整记录的可解码 `lastPlaying`；半写记录最多沿用 6 秒内的本进程已验证缓存，旧磁盘记录不会被反复刷新。
- 最终 `cargo test` 41 项通过；`cargo fmt --all --check`、`cargo clippy --all-targets -- -D warnings` 通过。当前只读实机采样为 `NoSong`（播放器进程在运行，但最新日志记录并非 `lastPlaying`），未证明最新版正在播放时可完整同步。

## 范围、实际探测及停机条件

项目根目录：`~/netease-lyrics-rs`。设计文档：`docs/superpowers/specs/2026-09-29-netease-macos-lyrics-design.md`。本阶段仅实现本机已实测存在的主路径：`~/Library/Application Support/com.netease.163music/Documents/storage/CEFCache/Local Storage/leveldb/*.log`；2026-09-29 探测到滚动日志持续更新，包含 `lastPlaying` 标记。另有 `playingList` 可在后续阶段补充标题，但本阶段唯一标识以解密后的 `resourceId` / `trackId` 为准；原来的 `~/Library/Containers/...` 目录在本机为旧数据，不可当成当前源。不能把 LevelDB `.ldb` 中的历史快照当成当前歌曲。`lastPlaying` 可能在未播放时仍保留上次歌曲；本阶段不能由文件存在推断正在播放，须人工验证启动后空闲状态。

该格式未公开；`lastPlaying` 的 AES-128-ECB / PKCS#7 / Base64 格式及密钥来自 [CloudLyrics-for-macOS 的 MIT 实现](https://github.com/hellomyonly55/CloudLyrics-for-macOS/blob/main/Sources/CloudLyrics/NetEaseLocalPlaybackBridge.swift)。引用其机制而不是复制源码。实施时记录来源和 MIT 致谢。CoreAudio 属性 `kAudioHardwarePropertyTranslatePIDToProcessObject` 与 `kAudioProcessPropertyIsRunningOutput` 已在本机 macOS SDK 的 `AudioHardware.h` 验证；输出活动并非必然等同真实播放，要通过暂停/恢复现场验收。

如果当前网易云版本未能解出身份、进度，或者 CoreAudio 始终无法分辨播放/暂停，**不得**把估算值伪装成实测值、不得进入歌词阶段。报告缺项；经用户确认后另设计 Accessibility 备选。读权限缺失时明确分类，绝不请求全盘访问或更改系统权限以绕过。

### 文件边界

- `Cargo.toml`、`Cargo.lock`、`.gitignore`：包和可重复依赖。
- `src/lib.rs`：公开的原始观测、就绪快照及诊断类型。
- `src/decoder.rs`：与磁盘无关的 `lastPlaying` 扫描和解码。
- `src/reader.rs`：有边界的只读 `.log` 扫描；本进程内缓存，不跨 App 重启。
- `src/process.rs`：网易云主进程和 Helper 的 PID 发现。
- `src/audio.rs`：CoreAudio 输出活动检查，不判断歌曲身份。
- `src/timeline.rs`：从原始进度估算显示进度；与磁盘和系统 API 隔离。
- `src/main.rs`：参数、轮询、诊断打印，不持久化用户数据。
- `README.md`、`docs/validation-checklist.md`：运行方法、人工验收、结论规则与来源致谢。

每项完成后只提交该项的文件；失败测试先跑红，再做最小实现、跑绿并提交。用户已明确取消原全局 `AGENTS.md` 中的额外编码技能前置要求。实施前按 `using-git-worktrees` 检查隔离，禁止在 `main` 上直接实施。

### Task 1: Rust 包与公开观测模型

**Files:** Create `Cargo.toml`, `src/lib.rs`, `src/main.rs`; modify existing `.gitignore`; generated `Cargo.lock`.

- [x] **Step 1: 建立 `Cargo.toml`，再增加失败测试。** `Cargo.toml`：

```toml
[package]
name = "netease-lyrics-rs"
version = "0.1.0"
edition = "2021"

[dependencies]
aes = "0.8.4"
ecb = { version = "0.1.2", features = ["alloc"] }
base64 = "0.22.1"
serde = { version = "1.0.228", features = ["derive"] }
serde_json = "1.0.151"

[dev-dependencies]
tempfile = "3"
```

`src/lib.rs` 先放：

```rust
#[cfg(test)]
mod tests {
    use super::{Diagnostic, RawPlayback};

    #[test]
    fn raw_progress_is_not_inferred_from_a_diagnostic() {
        let observed = RawPlayback {
            track_id: "123".into(),
            position_ms: 1_250,
            duration_ms: Some(10_000),
        };
        assert_eq!(observed.position_ms, 1_250);
        assert_ne!(Diagnostic::MissingField("is_playing"), Diagnostic::NoSong);
    }
}
```

- [x] **Step 2: 验证红。** `cargo test --lib` 预期 `unresolved imports Diagnostic, RawPlayback`。

- [x] **Step 3: 用以下定义补在测试之前；创建最小入口与 ignore。** `Snapshot::estimated_position_ms` **始终独立于实测** `raw.position_ms`。

```rust
use std::time::Instant;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RawPlayback {
    pub track_id: String,
    pub position_ms: u64,
    pub duration_ms: Option<u64>,
}

#[derive(Clone, Debug)]
pub struct Snapshot {
    pub raw: RawPlayback,
    pub estimated_position_ms: u64,
    pub is_playing: bool,
    pub observed_at: Instant,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Diagnostic {
    NotRunning,
    NoSong,
    MissingDirectory,
    MissingField(&'static str),
    PermissionDenied,
    FormatChanged,
}
```

`src/main.rs`：

```rust
fn main() { println!("Playback probe: run cargo test first"); }
```

`.gitignore` 已在建立隔离 worktree 时加入 `/.worktrees/`；本步仅补充 `/target/` 与 `/.DS_Store`，保留既有忽略项。

应用进程和数据目录不属于仓库。

- [x] **Step 4: 验证绿及提交。** `cargo fmt --all && cargo test --lib && cargo fmt --all --check && git diff --check`；预期 1 test PASS。`git add Cargo.toml Cargo.lock .gitignore src/lib.rs src/main.rs && git commit -m "chore: bootstrap Rust playback probe"`。

### Task 2: 独立解码 `lastPlaying`

**Files:** Create `src/decoder.rs`; modify `src/lib.rs`（仅新增 `pub mod decoder;`）。

- [x] **Step 1: 写失败测试。** 在 `src/decoder.rs` 增加下面这组 fixture（以测试加密，绝不提交本机真实播放记录），先跑 `cargo test --lib decoder`，预期 `inspect` 未定义。

```rust
// Fixture 使用测试本地生成的密文，禁止读取真实用户播放记录。
#[cfg(test)]
pub(crate) fn fixture_json(json: serde_json::Value) -> Vec<u8> {
    use aes::cipher::{block_padding::Pkcs7, BlockEncryptMut, KeyInit};
    use base64::{engine::general_purpose::STANDARD, Engine};
    let ct = ecb::Encryptor::<aes::Aes128>::new(&KEY.into())
        .encrypt_padded_vec_mut::<Pkcs7>(json.to_string().as_bytes());
    let mut record = b"lastPlaying\x00\x01\x00".to_vec();
    record.extend_from_slice(STANDARD.encode(ct).as_bytes());
    record.push(0);
    record
}

#[cfg(test)]
pub(crate) fn fixture(id: &str, current: f64) -> Vec<u8> {
    fixture_json(serde_json::json!({"resourceId":id,"current":current,"resourceDuration":180.0}))
}

#[cfg(test)]
mod tests {
    use super::{fixture, fixture_json, inspect};
    #[test]
    fn latest_valid_record_wins() {
        let mut log = fixture("11", 1.25);
        log.extend(fixture("22", 2.5));
        let result = inspect(&log);
        assert!(result.marker_found);
        let raw = result.latest.unwrap();
        assert_eq!((raw.track_id.as_str(), raw.position_ms), ("22", 2_500));
        assert_eq!(raw.duration_ms, Some(180_000));
    }
    #[test]
    fn missing_required_fields_are_explicit() {
        assert_eq!(inspect(&fixture_json(serde_json::json!({"resourceId":"12"}))).missing_field, Some("position_ms"));
        assert_eq!(inspect(&fixture_json(serde_json::json!({"current":3.0}))).missing_field, Some("track_id"));
    }
    #[test]
    fn invalid_progress_is_not_a_snapshot() {
        let negative = inspect(&fixture_json(serde_json::json!({"resourceId":"12", "current":-1})));
        assert!(negative.latest.is_none());
        assert!(negative.invalid_value);
        assert!(inspect(&fixture_json(serde_json::json!({"resourceId":"12", "current":"NaN"}))).latest.is_none());
    }
    #[test]
    fn invalid_record_is_distinct_from_missing_marker() {
        assert!(!inspect(b"nothing").marker_found);
        let bad = inspect(b"lastPlaying\x00not-base64\x00");
        assert!(bad.marker_found);
        assert!(bad.latest.is_none());
    }
    #[test]
    fn incomplete_tail_keeps_last_verified_record() {
        let mut log = fixture("11", 1.0);
        log.extend_from_slice(b"lastPlaying\x00not-base64\x00");
        assert_eq!(inspect(&log).latest.unwrap().track_id, "11");
    }
    #[test]
    fn missing_required_field_in_latest_record_blocks_old_song() {
        let mut log = fixture("11", 1.0);
        log.extend(fixture_json(serde_json::json!({"resourceId":"new"})));
        let result = inspect(&log);
        assert!(result.latest.is_none());
        assert_eq!(result.missing_field, Some("position_ms"));
    }
    #[test]
    fn invalid_complete_record_blocks_old_song() {
        let mut log = fixture("11", 1.0);
        log.extend(fixture_json(serde_json::json!({"resourceId":"new","current":-1})));
        let result = inspect(&log);
        assert!(result.latest.is_none());
        assert!(result.invalid_value);
    }
}
```

- [x] **Step 2: 用以下完整解码单元实现 `src/decoder.rs` 的测试之前部分。** 限定 Base64 候选长度，拒绝空 ID、负值、非有限数值、解密失败。格式有变化时不返回伪记录。

```rust
use crate::RawPlayback;
use aes::cipher::{block_padding::Pkcs7, BlockDecryptMut, KeyInit};
use base64::{engine::general_purpose::STANDARD, Engine};
use serde::Deserialize;

const MARKER: &[u8] = b"lastPlaying";
const KEY: [u8; 16] = *b")(13daqP@ssw0rd~";

#[derive(Debug)]
pub struct Inspection {
    pub marker_found: bool,
    pub latest: Option<RawPlayback>,
    pub missing_field: Option<&'static str>,
    pub invalid_value: bool,
}

enum Payload { Valid(RawPlayback), Missing(&'static str), Invalid }

#[derive(Deserialize)]
struct State {
    #[serde(rename = "resourceId", default)]
    resource_id: String,
    #[serde(rename = "trackId")]
    track_id: Option<String>,
    current: Option<f64>,
    #[serde(rename = "resourceDuration")]
    duration: Option<f64>,
}

fn decode(encoded: &[u8]) -> Option<Payload> {
    let mut encrypted = STANDARD.decode(encoded).ok()?;
    if encrypted.is_empty() || encrypted.len() % 16 != 0 { return None; }
    let plaintext = ecb::Decryptor::<aes::Aes128>::new(&KEY.into())
        .decrypt_padded_mut::<Pkcs7>(&mut encrypted).ok()?;
    let state: State = serde_json::from_slice(plaintext).ok()?;
    let id = if state.resource_id.is_empty() {
        match state.track_id.filter(|value| !value.is_empty()) {
            Some(id) => id,
            None => return Some(Payload::Missing("track_id")),
        }
    } else { state.resource_id };
    let current = match state.current {
        Some(value) => value,
        None => return Some(Payload::Missing("position_ms")),
    };
    if !current.is_finite() || current < 0.0 || current > (u64::MAX as f64 / 1_000.0) {
        return Some(Payload::Invalid);
    }
    let duration_ms = state.duration.filter(|n| n.is_finite() && *n > 0.0 && *n <= (u64::MAX as f64 / 1_000.0))
        .map(|n| (n * 1_000.0).round() as u64);
    Some(Payload::Valid(RawPlayback { track_id: id, position_ms: (current * 1_000.0).round() as u64, duration_ms }))
}

fn base64_byte(b: u8) -> bool { b.is_ascii_alphanumeric() || matches!(b, b'+' | b'/' | b'=') }

pub fn inspect(data: &[u8]) -> Inspection {
    let mut out = Inspection { marker_found: false, latest: None, missing_field: None, invalid_value: false };
    for (at, bytes) in data.windows(MARKER.len()).enumerate() {
        if bytes != MARKER { continue; }
        out.marker_found = true;
        let start = at + MARKER.len();
        let end = data.len().min(start + 1_024);
        let mut cursor = start;
        while cursor < end {
            while cursor < end && !base64_byte(data[cursor]) { cursor += 1; }
            let run_start = cursor;
            while cursor < end && base64_byte(data[cursor]) { cursor += 1; }
            let run_end = cursor;
            if run_end.saturating_sub(run_start) < 24 { continue; }
            let max_prefix = 16.min(run_end - run_start - 24);
            let max_suffix = 16.min(run_end - run_start - 24);
            'candidates: for prefix in 0..=max_prefix {
                for suffix in 0..=max_suffix {
                    let part = &data[run_start + prefix..run_end - suffix];
                    if part.len() >= 24 && part.len().is_multiple_of(4) {
                        match decode(part) {
                            Some(Payload::Valid(state)) => { out.latest = Some(state); out.missing_field = None; out.invalid_value = false; break 'candidates; }
                            Some(Payload::Missing(field)) => { out.latest = None; out.missing_field = Some(field); out.invalid_value = false; break 'candidates; }
                            Some(Payload::Invalid) => { out.latest = None; out.missing_field = None; out.invalid_value = true; break 'candidates; }
                            None => {}
                        }
                    }
                }
            }
        }
    }
    out
}
```

- [x] **Step 3: 验证绿、边界及提交。** 上述测试覆盖无效进度、缺字段、时长和最新记录损坏。运行 `cargo test --lib decoder && cargo fmt --all && cargo clippy --all-targets -- -D warnings`，期望全绿。`git add src/decoder.rs src/lib.rs && git commit -m "feat: decode Netease lastPlaying records"`。

### Task 3: 只读滚动日志读取器

**Files:** Create `src/reader.rs`; modify `src/lib.rs`（新增 `pub mod reader;`）。

- [x] **Step 1: 先加失败测试**，在 `src/reader.rs` 用 `tempfile::tempdir()` 建临时 LevelDB 目录。三个断言：① `Reader::new(missing).read()` 是 `MissingDirectory`；② 写 `000001.log` 中两份 Task 2 的 fixture，取最后的 ID 和进度；③ 改名日志后，**同一进程实例**在 6 秒内沿用缓存，过期或调用 `reset()` 后只给无歌曲（`None`）。

```rust
#[cfg(test)]
mod tests {
    use super::{Reader, ReadError};
    use crate::decoder::fixture;
    use std::fs;
    #[test]
    fn missing_directory_is_explicit() {
        let dir = tempfile::tempdir().unwrap();
        let mut reader = Reader::new(dir.path().join("missing"));
        assert!(matches!(reader.read(), Err(ReadError::MissingDirectory)));
    }
    #[test]
    fn last_log_record_wins_and_reset_drops_stale_track() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("000001.log");
        let mut log = fixture("10", 3.0);
        log.extend(fixture("11", 4.0));
        fs::write(&file, log).unwrap();
        let mut reader = Reader::new(dir.path().to_path_buf());
        assert_eq!(reader.read().unwrap().unwrap().track_id, "11");
        fs::rename(file, dir.path().join("old.bak")).unwrap();
        assert_eq!(reader.read().unwrap().unwrap().track_id, "11");
        reader.cached_at = Some(std::time::Instant::now() - std::time::Duration::from_secs(10));
        assert!(reader.read().unwrap().is_none());
        reader.reset();
        assert!(reader.read().unwrap().is_none());
    }
    #[test]
    fn undecodable_marker_is_format_change_not_no_song() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("1.log"), b"lastPlaying\x00bad\x00").unwrap();
        assert!(matches!(Reader::new(dir.path().to_path_buf()).read(), Err(ReadError::FormatChanged)));
    }
    #[test]
    fn missing_position_is_explicit() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("1.log"), crate::decoder::fixture_json(
            serde_json::json!({"resourceId":"11"}))).unwrap();
        assert!(matches!(Reader::new(dir.path().to_path_buf()).read(), Err(ReadError::MissingField("position_ms"))));
    }
    #[test]
    fn newer_invalid_log_must_not_use_older_song() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("1.log"), fixture("11", 1.0)).unwrap();
        fs::write(dir.path().join("2.log"), crate::decoder::fixture_json(
            serde_json::json!({"resourceId":"new","current":-1}))).unwrap();
        assert!(matches!(Reader::new(dir.path().to_path_buf()).read(), Err(ReadError::FormatChanged)));
    }
    #[test]
    fn fresh_newer_log_without_marker_may_use_older_log_with_valid_record() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("1.log"), fixture("11", 1.0)).unwrap();
        fs::write(dir.path().join("2.log"), b"still rotating").unwrap();
        assert_eq!(Reader::new(dir.path().to_path_buf()).read().unwrap().unwrap().track_id, "11");
    }
}
```

- [x] **Step 2: 跑红** `cargo test --lib reader`；应为 `Reader` / `ReadError` 缺失。

- [x] **Step 3: 最小实现**（把下面代码写在测试之前）。只读单文件尾部最多 128 KiB；轮转中的 NotFound 可跳过；缓存跨日志轮转最多 6 秒；完整但缺字段的新记录禁止回退旧歌；尾部半写记录保留该日志中最后一条完整记录；绝不持久化或读取旧 Container 的 `.ldb`。

```rust
use crate::{decoder, RawPlayback};
use std::{fs::{self, File}, io::{self, Read, Seek, SeekFrom}, path::{Path, PathBuf}, time::{Duration, Instant, SystemTime}};

#[derive(Debug)]
pub enum ReadError { MissingDirectory, MissingField(&'static str), PermissionDenied, FormatChanged, Io(io::Error) }

pub struct Reader { dir: PathBuf, cached: Option<RawPlayback>, cached_at: Option<Instant> }
impl Reader {
    pub fn new(dir: PathBuf) -> Self { Self { dir, cached: None, cached_at: None } }
    pub fn reset(&mut self) { self.cached = None; self.cached_at = None; }

    pub fn read(&mut self) -> Result<Option<RawPlayback>, ReadError> {
        let entries = fs::read_dir(&self.dir).map_err(|error| classify(error, true))?;
        let mut logs = Vec::new();
        for entry in entries {
            let entry = entry.map_err(|error| classify(error, false))?;
            let path = entry.path();
            if path.extension().is_none_or(|ext| ext != "log") { continue; }
            let metadata = match entry.metadata() {
                Ok(metadata) => metadata,
                Err(error) if error.kind() == io::ErrorKind::NotFound => continue,
                Err(error) => return Err(classify(error, false)),
            };
            if metadata.is_file() {
                logs.push((metadata.modified().unwrap_or(SystemTime::UNIX_EPOCH), path));
            }
        }
        logs.sort_by(|a, b| b.cmp(a));
        for (_, path) in logs {
            let bytes = match read_tail(&path) {
                Ok(bytes) => bytes,
                Err(error) if error.kind() == io::ErrorKind::NotFound => continue,
                Err(error) => return Err(classify(error, false)),
            };
            let result = decoder::inspect(&bytes);
            if let Some(field) = result.missing_field { return Err(ReadError::MissingField(field)); }
            if result.invalid_value { return Err(ReadError::FormatChanged); }
            if let Some(raw) = result.latest {
                self.cached = Some(raw.clone());
                self.cached_at = Some(Instant::now());
                return Ok(Some(raw));
            }
            if result.marker_found {
                if self.cached_at.is_some_and(|t| t.elapsed() <= Duration::from_secs(6)) {
                    return Ok(self.cached.clone()); // 可能是轮转文件中的半写记录
                }
                return Err(ReadError::FormatChanged);
            }
        }
        if self.cached_at.is_some_and(|t| t.elapsed() <= Duration::from_secs(6)) {
            return Ok(self.cached.clone());
        }
        self.reset();
        Ok(None)
    }
}

fn read_tail(path: &Path) -> io::Result<Vec<u8>> {
    let mut file = File::open(path)?;
    let len = file.metadata()?.len();
    file.seek(SeekFrom::Start(len.saturating_sub(128 * 1_024)))?;
    let mut bytes = Vec::new();
    file.take(128 * 1_024).read_to_end(&mut bytes)?;
    Ok(bytes)
}

fn classify(error: io::Error, directory: bool) -> ReadError {
    match error.kind() {
        io::ErrorKind::NotFound if directory => ReadError::MissingDirectory,
        io::ErrorKind::PermissionDenied => ReadError::PermissionDenied,
        _ => ReadError::Io(error),
    }
}
```

- [x] **Step 4: 测绿、提交。** `cargo test --lib reader && cargo fmt --all && cargo clippy --all-targets -- -D warnings`。实机读取验证集中在 Task 6 CLI；不得将真实 ID 写入测试夹具和 Git。`git add src/reader.rs src/lib.rs && git commit -m "feat: read current Netease LevelDB log safely"`。

### Task 4: 进程发现与 CoreAudio 播放状态

**Files:** Create `src/process.rs`, `src/audio.rs`; modify `src/lib.rs`（新增 `pub mod process; pub mod audio;`）。

- [x] **Step 1: 进程解析先写失败测试**（`src/process.rs`）：模拟 `ps` 输出，主进程 + GPU Helper 应纳入，其他 App 排除。

```rust
#[cfg(test)]
mod tests {
    use super::parse_ps;
    #[test]
    fn select_only_netease_bundle() {
        let text = "8 /Applications/Other.app/Contents/MacOS/Other\n10 /Applications/NeteaseMusic.app/Contents/MacOS/NeteaseMusic\n11 /Applications/NeteaseMusic.app/Contents/Frameworks/NeteaseMusic Helper (GPU).app/Contents/MacOS/NeteaseMusic Helper (GPU)\n";
        assert_eq!(parse_ps(text), vec![10, 11]);
        assert!(parse_ps("9 /Applications/Other.app/Contents/MacOS/Other\n").is_empty());
    }
}
```

- [x] **Step 2: 跑红** `cargo test --lib process`；应为 `parse_ps` 缺失。随后写实现：

```rust
use std::{io, process::Command};

pub fn discover() -> io::Result<Vec<i32>> {
    let output = Command::new("/bin/ps").args(["-axo", "pid=,comm="]).output()?;
    if !output.status.success() { return Err(io::Error::other("ps failed")); }
    Ok(parse_ps(&String::from_utf8_lossy(&output.stdout)))
}

pub fn parse_ps(text: &str) -> Vec<i32> {
    let mut main = None;
    let mut helpers = Vec::new();
    for line in text.lines() {
        let mut parts = line.split_whitespace();
        let Some(pid) = parts.next().and_then(|p| p.parse::<i32>().ok()) else { continue; };
        let path = line.trim_start().trim_start_matches(|c: char| c.is_ascii_digit()).trim();
        if path.ends_with("/NeteaseMusic.app/Contents/MacOS/NeteaseMusic") { main = Some(pid); }
        else if path.contains("/NeteaseMusic.app/Contents/Frameworks/") { helpers.push(pid); }
    }
    match main {
        Some(pid) => { let mut out = vec![pid]; out.extend(helpers); out }
        None => vec![],
    }
}
```

- [x] **Step 3: CoreAudio 小单元测试先红。** 测纯合并规则：`[None,None] → None`、`[Some(false), None] → Some(false)`、`[Some(false),Some(true)] → Some(true)`。`cargo test --lib audio` 应缺少 `merge`。

```rust
#[cfg(test)]
mod tests {
    use super::merge;
    #[test]
    fn any_output_wins_unknown_is_not_false() {
        assert_eq!(merge([None, None]), None);
        assert_eq!(merge([Some(false), None]), Some(false));
        assert_eq!(merge([Some(false), Some(true)]), Some(true));
    }
}
```

- [x] **Step 4: CoreAudio 实现。** 仅 macOS 编译，原生 ABI 属性来自当前 SDK，返回 `None` 时不能推断暂停。适配本机 macOS 26.6.2；不在其他平台构建此包。`src/audio.rs` 的测试之前部分：

```rust
use std::{ffi::c_void, mem::size_of};

#[repr(C)]
struct Address { selector: u32, scope: u32, element: u32 }

#[link(name = "CoreAudio", kind = "framework")]
unsafe extern "C" {
    fn AudioObjectGetPropertyData(id: u32, address: *const Address, qualifier_size: u32,
        qualifier: *const c_void, data_size: *mut u32, data: *mut c_void) -> i32;
}

const fn fourcc(bytes: [u8; 4]) -> u32 { u32::from_be_bytes(bytes) }
const GLOBAL: u32 = fourcc(*b"glob");
const TRANSLATE_PID: u32 = fourcc(*b"id2p");
const IS_RUNNING_OUTPUT: u32 = fourcc(*b"piro");

fn state(pid: i32) -> Option<bool> {
    let address = Address { selector: TRANSLATE_PID, scope: GLOBAL, element: 0 };
    let mut object_id = 0_u32;
    let mut size = size_of::<u32>() as u32;
    // SAFETY: 参数长度与类型匹配 SDK 的 AudioObjectGetPropertyData 声明；指针只在调用期间有效。
    let result = unsafe { AudioObjectGetPropertyData(1, &address, size_of::<i32>() as u32,
        (&pid as *const i32).cast(), &mut size, (&mut object_id as *mut u32).cast()) };
    if result != 0 || object_id == 0 || size != size_of::<u32>() as u32 { return None; }
    let address = Address { selector: IS_RUNNING_OUTPUT, scope: GLOBAL, element: 0 };
    let mut running = 0_u32;
    size = size_of::<u32>() as u32;
    // SAFETY: CoreAudio 给出的有效 object_id 与 UInt32 输出缓冲区；空 qualifier 用 null。
    let result = unsafe { AudioObjectGetPropertyData(object_id, &address, 0,
        std::ptr::null(), &mut size, (&mut running as *mut u32).cast()) };
    if result == 0 && size == size_of::<u32>() as u32 { Some(running != 0) } else { None }
}

pub fn merge(values: impl IntoIterator<Item = Option<bool>>) -> Option<bool> {
    let mut known = false;
    for value in values {
        if value == Some(true) { return Some(true); }
        if value == Some(false) { known = true; }
    }
    if known { Some(false) } else { None }
}

pub fn is_running_output(pids: &[i32]) -> Option<bool> {
    merge(pids.iter().copied().map(state))
}
```

- [x] **Step 5: 测绿与提交。** `cargo test --lib process && cargo test --lib audio`；接着 `cargo fmt --all && cargo clippy --all-targets -- -D warnings`。`git add src/process.rs src/audio.rs src/lib.rs && git commit -m "feat: inspect Netease audio output activity"`。现场值与真实播放对照放在 Task 6，不假设 `running output` 恒可靠。

### Task 5: 独立时间模型

**Files:** Create `src/timeline.rs`; modify `src/lib.rs`（新增 `pub mod timeline;`）。

- [x] **Step 1: 写失败测试**；时间直接注入毫秒，保证不需要睡眠，分别覆盖继续播放、暂停冻结、换歌、后退拖动的二次确认。

```rust
#[cfg(test)]
mod tests {
    use super::Timeline;
    #[test]
    fn advances_only_when_playing() {
        let mut t = Timeline::default();
        assert_eq!(t.update("a", 1_000, true, 0), 1_000);
        assert_eq!(t.update("a", 1_000, true, 500), 1_500);
        assert_eq!(t.update("a", 1_000, false, 500), 1_500);
        assert_eq!(t.update("a", 1_000, false, 5_000), 1_500);
    }
    #[test]
    fn a_second_advancing_lower_sample_confirms_seek() {
        let mut t = Timeline::default();
        t.update("a", 60_000, true, 0);
        assert_eq!(t.update("a", 10_000, true, 500), 60_500);
        assert_eq!(t.update("a", 11_000, true, 1_000), 11_000);
        assert_eq!(t.update("b", 0, false, 1_000), 0);
    }
}
```

- [x] **Step 2: `cargo test --lib timeline` 红**；实现该文件测试之前部分：

```rust
#[derive(Default)]
pub struct Timeline { current: Option<State> }
struct State {
    id: String, exact: u64, shown: u64, observed_at: u64,
    playing: bool, pending_backward: Option<u64>,
}
impl Timeline {
    pub fn reset(&mut self) { self.current = None; }
    pub fn update(&mut self, id: &str, exact: u64, playing: bool, now_ms: u64) -> u64 {
        if self.current.as_ref().is_none_or(|old| old.id != id) {
            self.current = Some(State { id: id.to_owned(), exact, shown: exact,
                observed_at: now_ms, playing, pending_backward: None });
            return exact;
        }
        let state = self.current.as_mut().expect("track exists");
        let advancing = if state.playing && playing {
            now_ms.saturating_sub(state.observed_at)
        } else { 0 };
        let mut shown = state.shown.saturating_add(advancing);
        if exact < state.exact {
            if !playing || state.pending_backward.is_some_and(|pending| exact > pending) {
                shown = exact;
                state.exact = exact;
                state.pending_backward = None;
            } else if state.pending_backward.is_none() {
                state.pending_backward = Some(exact);
            }
        } else {
            state.exact = exact;
            shown = shown.max(exact);
            state.pending_backward = None;
        }
        state.shown = shown;
        state.playing = playing;
        state.observed_at = now_ms;
        shown
    }
}
```

- [x] **Step 3: 追加边界测试，验证绿与提交。** 在 `src/timeline.rs` 的 `mod tests` 中追加：

```rust
#[test]
fn paused_backward_seek_is_immediate() {
    let mut t = Timeline::default();
    t.update("a", 60_000, false, 0);
    assert_eq!(t.update("a", 10_000, false, 500), 10_000);
}
#[test]
fn one_stale_backward_sample_does_not_seek() {
    let mut t = Timeline::default();
    t.update("a", 60_000, true, 0);
    assert_eq!(t.update("a", 10_000, true, 500), 60_500);
    assert_eq!(t.update("a", 60_000, true, 1_000), 61_000);
}
```

`cargo test --lib timeline && cargo fmt --all && cargo clippy --all-targets -- -D warnings`。`git add src/timeline.rs src/lib.rs && git commit -m "feat: estimate playback timeline without faking observations"`。

### Task 6: CLI 连线与人工验收

**Files:** Replace `src/main.rs`; create `README.md`, `docs/validation-checklist.md`.

- [x] **Step 1: 先写 CLI 参数失败测试**，在 `src/main.rs` 末尾加 `#[cfg(test)]`：`parse(&["--once"]) == (1,500)`、`--samples 4 --interval-ms 200 == (4,200)`、`--interval-ms 0` 报错；`cargo test --bin netease-lyrics-rs` 红。

```rust
#[cfg(test)]
mod tests {
    use super::parse;
    #[test]
    fn arguments_are_bounded() {
        assert_eq!(parse(&["--once".into()]).unwrap(), (1, 500));
        assert_eq!(parse(&["--samples".into(), "4".into(), "--interval-ms".into(), "200".into()]).unwrap(), (4, 200));
        assert!(parse(&["--interval-ms".into(), "0".into()]).is_err());
    }
}
```

- [x] **Step 2: 实现 CLI 参数及一次采样**，把 `src/main.rs` 测试之前内容替换为：

```rust
use netease_lyrics_rs::{audio, process, reader::{ReadError, Reader}, timeline::Timeline,
    Diagnostic, Snapshot};
use std::{env, path::PathBuf, thread, time::{Duration, Instant}};

fn parse(args: &[String]) -> Result<(u64, u64), String> {
    let (mut samples, mut interval) = (u64::MAX, 500);
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--once" => samples = 1,
            "--samples" | "--interval-ms" => {
                let flag = &args[i];
                i += 1;
                let value = args.get(i).ok_or_else(|| format!("missing value for {flag}"))?
                    .parse::<u64>().map_err(|_| format!("invalid value for {flag}"))?;
                if value == 0 { return Err(format!("{flag} must be positive")); }
                if flag == "--samples" { samples = value; } else { interval = value; }
            }
            flag => return Err(format!("unknown option: {flag}")),
        }
        i += 1;
    }
    Ok((samples, interval))
}

fn sample(reader: &mut Reader, timeline: &mut Timeline, origin: Instant,
    active_pid: &mut Option<i32>) -> Result<Snapshot, Diagnostic> {
    let pids = process::discover().map_err(|_| Diagnostic::MissingField("process_list"))?;
    let Some(&pid) = pids.first() else {
        *active_pid = None;
        reader.reset();
        timeline.reset();
        return Err(Diagnostic::NotRunning);
    };
    if *active_pid != Some(pid) {
        *active_pid = Some(pid);
        reader.reset();
        timeline.reset();
    }
    let raw = match reader.read() {
        Ok(Some(raw)) => raw,
        Ok(None) => { timeline.reset(); return Err(Diagnostic::NoSong); }
        Err(error) => {
            timeline.reset();
            return Err(match error {
                ReadError::MissingDirectory => Diagnostic::MissingDirectory,
                ReadError::MissingField(field) => Diagnostic::MissingField(field),
                ReadError::PermissionDenied => Diagnostic::PermissionDenied,
                ReadError::FormatChanged => Diagnostic::FormatChanged,
                ReadError::Io(_) => Diagnostic::MissingField("local_log_io"),
            });
        }
    };
    let Some(is_playing) = audio::is_running_output(&pids) else {
        timeline.reset();
        return Err(Diagnostic::MissingField("is_playing"));
    };
    let observed_at = Instant::now();
    let estimated_position_ms = timeline.update(&raw.track_id, raw.position_ms,
        is_playing, observed_at.duration_since(origin).as_millis() as u64);
    Ok(Snapshot { raw, estimated_position_ms, is_playing, observed_at })
}

fn main() {
    let (samples, interval) = match parse(&env::args().skip(1).collect::<Vec<_>>()) {
        Ok(values) => values,
        Err(error) => { eprintln!("{error}\nusage: netease-lyrics-rs [--once | --samples N] [--interval-ms N]"); std::process::exit(2); }
    };
    let Some(home) = env::var_os("HOME") else { eprintln!("HOME is not set"); std::process::exit(2); };
    let path = PathBuf::from(home).join("Library/Application Support/com.netease.163music/Documents/storage/CEFCache/Local Storage/leveldb");
    let mut reader = Reader::new(path);
    let mut timeline = Timeline::default();
    let mut active_pid = None;
    let origin = Instant::now();
    for index in 0..samples {
        match sample(&mut reader, &mut timeline, origin, &mut active_pid) {
            Ok(snapshot) => println!("track={} raw_ms={} estimated_ms={} playing={} observed_t+{}ms",
                snapshot.raw.track_id, snapshot.raw.position_ms, snapshot.estimated_position_ms,
                snapshot.is_playing, snapshot.observed_at.duration_since(origin).as_millis()),
            Err(diagnostic) => println!("unavailable: {diagnostic:?}"),
        }
        if index + 1 < samples { thread::sleep(Duration::from_millis(interval)); }
    }
}
```

`--samples` 使用 `u64::MAX` 作为默认长期观察上限；用户按 Ctrl-C 退出。源读取或状态未知时重置时间模型，不跨诊断间隔假推进。实际交付前检查 `Snapshot` 原始与估算的列名不能混淆，格式错误和权限失败必须直接可见。若发现 App 3.1.12 返回不同 JSON 字段，不改 fixture 硬凑；先收集**字段名而非值**再修正。

- [x] **Step 3: 自动验证。** `cargo fmt --all && cargo test && cargo fmt --all --check && cargo clippy --all-targets -- -D warnings && cargo run -- --once`；预期自动测试通过。`--once` 实机可能是 `Ready` 或诊断，**不能**把测试环境没在播放误判为代码失败；记录诊断，不贴真实歌曲数据到仓库。

- [ ] **Step 4: 写 `README.md`**，包含运行 `cargo run -- --samples 120 --interval-ms 500`、只读文件路径、本机支持版本、原始/估算进度定义、CoreAudio 可能误判、不得上传本机存储数据，以及 CloudLyrics-for-macOS 的 MIT 来源致谢。写 `docs/validation-checklist.md`，按下表测试并填写现场值；不得通过脚本自动控制播放器。

| 操作 | 观察目标 | 合格标准 |
| --- | --- | --- |
| 网易云未启动 → 启动且不播放 | PID / ID / position | `NotRunning` 后不得把上次歌曲误报为当前播放；若仅有历史快照，标记本方案受限 |
| 开始播放 / 切歌 / 上一首 / 下一首 | ID 变化与延迟 | ID 与实际歌曲匹配；记录秒级实测延迟 |
| 播放 → 暂停 → 恢复 | CoreAudio / raw / estimated | `is_playing` 正确切换；暂停时估算不推进 |
| 播放中前后拖动进度 | raw / estimated | raw 可观测；后退需第二个递进样本确认 |
| 暂停时拖动 / 退出客户端 | 状态清理 | 暂停下即时校正；退出显示 `NotRunning` |
| 权限不足 / 空目录 / 坏记录 fixture | 分类诊断 | `PermissionDenied` / `NoSong` / `FormatChanged` |

结论只能填：**可继续**（ID、进度、状态均现场合格）；**受限继续**（列出不影响核心目标的明确限制）；**不可继续**（任何必要字段缺失或 CoreAudio 不可靠）。未完成真实播放器交互时填“待人工验证”，不能声称成功。

- [ ] **Step 5: 提交与报告。** `git add src/main.rs README.md docs/validation-checklist.md && git commit -m "feat: expose read-only Netease playback diagnostics"`；最后跑 `cargo test && cargo fmt --all --check && cargo clippy --all-targets -- -D warnings && git status --short --branch && git log --oneline -6`。报告：实际读取源、测试数、现场 ID／进度／状态是否吻合、缺陷、结论；不要展示私人播放内容或未授权系统配置。

## 对应设计文档与后续

本计划覆盖第一阶段：歌曲 ID 与真实播放进度、本机只读访问、CoreAudio 状态、异常分类、可重复的解码/读取/时间模型测试、人工验收；尚**不包含**歌词接口、翻译 LRC、AppKit UI。后续只有在本阶段「可继续」时分别写第二、第三阶段的实施计划，并再次确认方案。若该版本只有标题、没有稳定 ID / 位置 / 播放状态，不进入下阶段。整个项目只在指定目录内提交，任何对网易云原始数据的更改都属于越界。
