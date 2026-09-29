# Desktop Lyrics Nearby Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an always-reachable nearby toolbar and live, locally persisted lyric appearance controls without changing the Rust playback probe.

**Architecture:** Keep the lyric and toolbar in two separate `NSPanel`s so `ignoresMouseEvents` can apply only to lyrics. A small `OverlayStyle` model owns validated local preferences; a pure geometry function positions the toolbar. `AppController` connects UI changes to `LyricsView` and preserves the existing engine protocol.

**Tech Stack:** Swift/AppKit 6.3; existing Rust engine unchanged; macOS local ad-hoc `.app` bundle.

---

## File map

- `Sources/DesktopLyrics/OverlayStyle.swift`: bounded color/opacity settings, load/save.
- `Sources/DesktopLyrics/ToolbarPlacement.swift`: pure visible-screen geometry.
- `Sources/DesktopLyrics/LyricsView.swift`: existing lyric rendering, configurable colors and text-sized backgrounds (move from `main.swift`).
- `Sources/DesktopLyrics/OverlayControls.swift`: separate floating panel, drag handle, lock/settings/collapse buttons.
- `Sources/DesktopLyrics/StyleSettingsPanel.swift`: native colors, background and text-chip opacity sliders, reset.
- `Sources/DesktopLyrics/main.swift`: existing engine/JSON/menu lifecycle, coordinates other UI pieces.
- `tests/OverlayAppearanceTests/main.swift`, `scripts/test-swift.sh`: Swift model/geometry assertions.
- `scripts/build-app.sh`, `README.md`: compile all Swift sources and document controls/signature consequence.

### Task 1: Style state and placement

- [ ] Write failing Swift tests in `tests/OverlayAppearanceTests/main.swift` for default `#131313/0.91`, `#FFFFFF`, transparent black text chip, save/reload, malformed hex and non-finite/out-of-range opacity fallback, toolbar top-right position and below/far-screen fallback. Invoke with `scripts/test-swift.sh` to see missing-symbol failure.
- [ ] Implement `OverlayStyle.swift` with `struct OverlayStyle { var backgroundRGB, textRGB, chipRGB: String; var backgroundOpacity, chipOpacity: Double; static let defaultValue … }`, `OverlayStyleStore(defaults:)`, `load`, `save`, and `rgbHex(_:)` / `nsColor(_:)` conversion using device RGB and strict `#RRGGBB` validation. Implement `ToolbarPlacement.origin(overlay:size:visibleFrames:)` as a pure function, choosing greatest intersection screen, 8 pt separation, and clamping inside the screen visible frame.
- [ ] Run `scripts/test-swift.sh`, `cargo test`; commit style/geometry/tests.

### Task 2: Render adjustable text backgrounds

- [ ] Move `LyricsView` out of `main.swift` into `LyricsView.swift`, preserving the existing `show(primary:secondary:fraction:active:)` layout and progress behavior. Add `applyStyle(_:)`: background and text color, subtitle with 0.70 text alpha, and a pair of rounded chips behind the labels. The chips hug actual rendered/truncated text width plus horizontal/vertical padding; empty secondary hides its chip; 0 opacity hides both chips. Re-layout on new lyric text or style changes.
- [ ] Compile with `xcrun swiftc -framework AppKit -framework Foundation Sources/DesktopLyrics/*.swift -o /tmp/lyrics-overlay-check`; run Swift tests; commit rendering changes.

### Task 3: Independent toolbar and settings

- [ ] Add `OverlayControls.swift`: `NSPanel` (floating, borderless, nonactivating, transparent) 166×38 pt expanded or 38×38 pt collapsed. Buttons for drag handle, lock, palette, collapse/expand have Chinese tooltips/accessibility labels; a custom handle view supplies screen-coordinate drag deltas while unlocked. Expose `onDrag`, `onToggleLock`, `onToggleSettings`, `onToggleCollapsed`, `setLocked`, `setCollapsed`, and `follow(overlay:visibleFrames:)`. Its panel is never assigned `ignoresMouseEvents`.
- [ ] Add `StyleSettingsPanel.swift`: titled closable panel with three `NSColorWell`s, two `NSSlider`s (0–100 and % value labels), and “恢复默认”. `NSColorPanel.shared.showsAlpha = false`; opacity lives in the sliders. Send each change to `onStyleChange` immediately, updating swatches/sliders on reset. Add keyboard-accessible control labels.
- [ ] Compile and run Swift tests; commit toolbar/settings.

### Task 4: Integrate, preview, and document

- [ ] `AppController` loads `OverlayStyleStore` and collapsed setting; configures lyric panel, toolbar and menu entries, then applies saved style. On lyric move/screen changes reposition toolbar; lock affects only lyric panel; hide/show affects both panels; settings change saves and re-renders immediately; collapse persists. Status text no longer instructs menu-only usage. Restore menu fallback for show, lock, settings, accessibility, quit.
- [ ] `scripts/build-app.sh` compiles all `Sources/DesktopLyrics/*.swift`, continues to ad-hoc sign engine and app. `README.md` explains toolbar, click-through, transparent colors/sliders, and potential TCC reset on rebuild; correct stale independent-App verification note. Run `scripts/test-swift.sh`, `cargo test`, `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`, and Swift compile. Commit integration/docs.
- [ ] Build a disposable preview under `dist-preview/` with separate bundle ID/preferences and synthetic `--stdin` lyric events. Verify AX/screenshot: tool buttons, live color/opacity, lock stays clickable while lyric is click-through, drag follows, collapse/reopen and persisted defaults. Do not modify the working `dist/` app during preview. Remove preview artifacts when no longer needed.
- [ ] After review, stop only the running old App, back up the previously signed bundle locally, build `dist/网易云桌面歌词.app` once, open and verify UI plus actual lyric/permission state. If TCC rejects changed ad-hoc signature, explain the exact manual re-authorization step rather than editing macOS security settings. No push.

## Acceptance

Two independent panels stay visible together in all Spaces; lyric click-through still works when locked while toolbar remains operable. Appearance updates immediately and persists across launches. No Rust behavior change; the `.app` remains double-clickable and only local files/preferences change.
