#!/bin/zsh
set -euo pipefail
root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
cd "$root"
cargo build --release
app="$root/dist/网易云桌面歌词.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp app/Info.plist "$app/Contents/Info.plist"
engine="$app/Contents/Resources/netease-lyrics-rs"
executable="$app/Contents/MacOS/NeteaseDesktopLyrics"
cp target/release/netease-lyrics-rs "$engine"
xcrun swiftc -O -framework AppKit -framework Foundation Sources/DesktopLyrics/main.swift \
  -o "$executable"
chmod +x "$executable" "$engine"
plutil -lint "$app/Contents/Info.plist"
# The locally built app must have a stable bundle identity and sealed resources.
# Ad-hoc signing is not a substitute for granting Accessibility to the app itself.
codesign --force --sign - --identifier com.local.netease-desktop-lyrics.engine "$engine"
codesign --force --sign - --identifier com.local.netease-desktop-lyrics "$app"
codesign --verify --deep --strict "$app"
printf 'Built %s\n' "$app"
