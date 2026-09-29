#!/bin/zsh
set -euo pipefail
root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
xcrun swiftc -warnings-as-errors -framework AppKit -framework Foundation \
  "$root/Sources/DesktopLyrics/OverlayStyle.swift" \
  "$root/Sources/DesktopLyrics/ToolbarPlacement.swift" \
  "$root/tests/OverlayAppearanceTests/main.swift" \
  -o "$temporary/overlay-appearance-tests"
"$temporary/overlay-appearance-tests"
