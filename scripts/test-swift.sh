#!/bin/zsh
set -euo pipefail
root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
xcrun swiftc -target arm64-apple-macos13.0 -warnings-as-errors \
  -framework AppKit -framework Foundation -framework ApplicationServices \
  "$root/Sources/DesktopLyrics/LaunchMode.swift" \
  "$root/Sources/DesktopLyrics/OverlayStyle.swift" \
  "$root/Sources/DesktopLyrics/ToolbarPlacement.swift" \
  "$root/Sources/DesktopLyrics/OverlayLayout.swift" \
  "$root/Sources/DesktopLyrics/OverlayFrameView.swift" \
  "$root/Sources/DesktopLyrics/MarqueeTitleView.swift" \
  "$root/Sources/DesktopLyrics/OverlayVisibility.swift" \
  "$root/Sources/DesktopLyrics/OverlayHover.swift" \
  "$root/Sources/DesktopLyrics/LyricsView.swift" \
  "$root/Sources/DesktopLyrics/WaveformView.swift" \
  "$root/Sources/DesktopLyrics/WaveformRailView.swift" \
  "$root/Sources/DesktopLyrics/OverlayControls.swift" \
  "$root/Sources/DesktopLyrics/PlaybackTransport.swift" \
  "$root/Sources/DesktopLyrics/StyleSettingsPanel.swift" \
  "$root/tests/OverlayAppearanceTests/main.swift" \
  -o "$temporary/overlay-appearance-tests"
"$temporary/overlay-appearance-tests"
