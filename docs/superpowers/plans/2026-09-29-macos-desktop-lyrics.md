# macOS Desktop Lyrics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a locally usable macOS desktop lyrics app with Rust playback/lyrics engine and a thin native AppKit overlay.

**Architecture:** Keep existing read-only AX/LevelDB probe. Add bounded lyric HTTP provider, pure LRC synchronization, JSON-lines streaming bridge; Swift/AppKit consumes stream and owns only window/menus. Rust CLI remains diagnostic. Only local Git commits; no remote.

**Tech Stack:** Rust 2021, `/usr/bin/curl` HTTPS with timeout and bounded output, `serde_json`, macOS AppKit via Swift 6, `cargo test/fmt/clippy`, `swiftc`. Spec: `docs/superpowers/specs/2026-09-29-macos-desktop-lyrics-design.md`.

---

## File boundaries

- `src/lrc.rs`: parse and look up timestamped original/translation; no I/O.
- `src/lyrics.rs`: validate ID, fetch with bounded curl subprocess, decode JSON, memory cache; no playback or UI.
- `src/lyrics_stream.rs`: derive JSON line events from snapshots and provider; no AppKit.
- `src/main.rs`: existing CLI + `--lyrics-json`, writes flushed events and invokes provider only on current track.
- `Sources/DesktopLyrics/main.swift`: AppKit overlay and menu bar; parses JSON lines and never knows NetEase storage format.
- `scripts/build-app.sh`, `scripts/run-desktop.sh`, `app/Info.plist`: local app bundle and launch modes.
- `README.md`, `docs/validation-checklist.md`: run/permission and verified limitations.

### Task 1: Pure LRC synchronization

- [ ] Write failing unit tests for multiple tags, offset, metadata/no timestamps, unordered/deduplicated lines, 1–3 digit fractional seconds, original/translation pairing, before-first/after-last/seek. Run `cargo test --lib lrc` to confirm red.
- [ ] Implement bounded `parse_lrc(text)` returning timed lines and `TimedLyrics::new(original, translated)`, `at(ms)` current/next; avoid copying original source in tests. Add `pub mod lrc` in `lib.rs`.
- [ ] Run `cargo test --lib lrc && cargo fmt --all --check && cargo clippy --all-targets -- -D warnings`; commit `feat: parse and synchronize timestamped lyrics`.

### Task 2: Lyrics provider

- [ ] Write failing tests for decimal-only ID, synthetic JSON code 200 original/translation, missing lyric/instrumental, bad code/JSON, too-large response and cache behavior. Run red `cargo test --lib lyrics`.
- [ ] Implement `/usr/bin/curl --fail --silent --show-error --proto =https --proto-redir =https --connect-timeout 3 --max-time 8` with numeric ID as one argument; capture stdout via bounded 256 KiB read with child kill on overflow; parse to `TimedLyrics` and classify `Network`, `NoLyrics`, `InvalidResponse`, `InvalidTrackId`. Cache only successful track in memory. Unit tests never hit network; optional live API verification prints only status/length, never lyric content.
- [ ] Run tests/fmt/clippy; commit `feat: fetch current-track lyrics without credentials`.

### Task 3: JSON line bridge

- [ ] Write tests for loading → line, pause retained, seek changes active line, track change clears previous line, stale/unavailable clears, retry delay. Run red `cargo test --lib lyrics_stream`.
- [ ] `LyricsSession` keeps current track/lyrics/retry timestamp, transforms `Snapshot` and provider results into `serde` JSON `loading|line|unavailable`. No song ID in JSON; output bounds. `--lyrics-json` in `main.rs` leaves legacy mode intact, prints/flushes each event; `--once` allowed to test single shot. `Reader`/AX errors converted to localized short diagnostic keys, not raw user data.
- [ ] Run tests/fmt/clippy; commit `feat: stream synchronized lyrics to local desktop UI`.

### Task 4: Native window and local app

- [ ] Implement Swift AppKit app: menu-bar menu and always-on-top translucent NSPanel; title/translation or next sentence; loading/empty/error; toggle show/hide, click-through, draggable default, quit. Read JSONL asynchronously from Rust child or stdin; stop child at exit. No private audio API or player controls.
- [ ] Implement `scripts/build-app.sh` builds release Rust, compiles Swift via swiftc, creates `.app` with Info.plist and resource binary; `scripts/run-desktop.sh` launches bridge from authorized terminal into overlay stdin to avoid new app TCC setup for this machine. Do not force-change OS settings. Run build, script smoke, cargo tests/clippy; visual inspection via screenshot and UI click tests.
- [ ] Document simple one-command launch and privacy/permissions, add validation evidence without track IDs/lyric content; commit `feat: ship native macOS desktop lyrics overlay`.

### Task 5: End-to-end verification and review

- [ ] Live play/pause/resume/next/seek using native UI. Sample JSON anonymized (no track ID in protocol). Correct issues with failing tests first and commit fixes.
- [ ] Final `cargo test && cargo fmt --all --check && cargo clippy --all-targets -- -D warnings && ./scripts/build-app.sh && git status --short --branch`; verify normal CLI and `--lyrics-json` and app actually display changing line. Local commits only; report exact command, remaining limits and validation results.
