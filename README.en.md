<div align="center">

# Netease Desktop Lyrics

**A standalone desktop lyric overlay for the Netease Cloud Music macOS client**: draggable, lockable, click-through — however you resize the player window or switch Spaces, the lyrics stay.

[简体中文](README.md) · English · [日本語](README.ja.md) · [한국어](README.ko.md)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/macOS%2013%2B-Apple%20Silicon-lightgrey)
[![Latest release](https://img.shields.io/github/v/release/lidegejingHk/netease-desktop-lyrics?label=release&display_name=tag)](https://github.com/lidegejingHk/netease-desktop-lyrics/releases/latest)

</div>

---

## 1. Background

The built-in desktop lyrics of the Netease Cloud Music macOS client miss the two most common ways people use them:

- **They cannot be pinned**: there is no way to lock them in place on the desktop.
- **They vanish when the window grows**: enlarge the player window to browse while listening and the built-in overlay disappears.

The client is closed source, so this project adds a read-only sidecar instead: an **independent overlay** above every ordinary window, joining every Space, draggable, and — once locked — pinned in place and click-through. Resize the window or switch Spaces and the lyrics stay.

Safety: never injects into the client, never sends blind clicks to the player window, never uses the microphone or system audio, never stores account data.

### Quick start

1. Download the latest `NeteaseDesktopLyrics-*-macos-arm64.zip` from [Releases](https://github.com/lidegejingHk/netease-desktop-lyrics/releases/latest), unzip it, and drag 网易云桌面歌词.app into Applications.
2. If macOS blocks the first launch, choose “Open Anyway” under System Settings → Privacy & Security.
3. When it asks for Accessibility permission, allow “网易云桌面歌词” under System Settings → Privacy & Security → Accessibility, then relaunch the app.

Updates: versions with in-app updates offer “Check for Updates…” in the menu bar. The signing identity is stable, so the Accessibility grant survives upgrades. Older versions need one manual reinstall and a final re-grant; the first install still needs one system approval.

Building from source: `./scripts/build-app.sh` (needs Rust/Cargo, Apple Command Line Tools and network access).

## 2. Tech stack

| Layer | Built with | Responsibility |
| --- | --- | --- |
| Lyric engine | Rust | Reads Netease's Local Storage, cross-checks the playback state, fetches and parses timed lyrics, emits a bounded JSON event stream |
| Desktop host | Swift / AppKit | Menu bar, borderless overlay and icon hit windows, the style panel, and playback control through the Accessibility menu |
| Build | Cargo + `swiftc` | `scripts/build-app.sh` assembles and signs the .app; `scripts/test-swift.sh` runs the host assertions |

- Requirements: Apple Silicon (arm64), macOS 13 or newer; verified on macOS 26.6.2 with Netease Cloud Music 3.1.12.
- Netease's internal formats, menus and lyric API are not public or stable; other client versions need re-validation.

## 3. Architecture

Two processes and five channels :

1. **Data channel**: the host spawns the engine as a child process and reads its stdout line by line; each event carries the lyric, the playback flag, an estimated position and a short status code — **no track ID** — capped at 64 KiB per line.
2. **Playback state (Rust)**: parses Netease's Local Storage LevelDB log read-only, cross-checked against the Control menu read through Accessibility; a monotonic clock estimates the position and freezes while paused.
3. **Lyrics and title (Rust)**: after verifying a numeric track ID, requests lyrics and song details through the system `curl` (HTTPS only); no account cookies, nothing written to disk, cache lives only in the process.
4. **Transport (Swift)**: matches the single enabled, AXPress-capable item in Netease's Control menu and presses it (0.35 s timeout) — never a blind click into the player window.
5. **Overlay (Swift/AppKit)**: a set of borderless `NSPanel`s: rounded background, lyric band, toolbar and transport keys, bottom waveform. When locked, the whole overlay is click-through except the lock/unlock key; the controls follow the pointer.

## 4. Contributing

- **Reporting a problem**: include your macOS version, Netease Cloud Music version and the steps to reproduce. ⚠️ Command-line output can contain real track IDs and lyrics — please **do not** paste it.
- **Sending code**: branch from `main` → make the change → run the tests locally → open a PR describing the motivation, the change and how you verified it.
- **Especially welcome**: support for new client releases, lyric API and format changes, interaction and accessibility details, docs and translations.

## 5. Development conventions

- **Branches and commits**: never push to `main`; every change goes through a branch + PR. Commit messages are short English imperatives that explain *why*, not just *what*.
- **Tests must pass**: `cargo test` (engine) and `./scripts/test-swift.sh` (host geometry and interaction assertions); `scripts/build-app.sh` compiles the host with `-warnings-as-errors`.
- **Behaviour changes ship with assertions**: add or extend assertions in `tests/OverlayAppearanceTests/` whenever an interaction changes.
- **Keep the contract**: the engine event stream is the host's only input (bounded JSON lines, no track ID, 64 KiB per line); the host never guesses playback state and only trusts verified observations.
- **Privacy rules**: never inject into the client or collect/upload data; real track IDs and lyrics must not appear in issues, logs or commits.
- **Versioning and releases**: the single source of truth is `app/Info.plist`.

## 6. Support

If this tool helps you, you are welcome to buy the author a coffee ☕️

A ⭐️, an issue or a PR is support too.

---

License: [MIT](LICENSE)
