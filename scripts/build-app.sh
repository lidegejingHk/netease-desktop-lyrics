#!/bin/zsh
set -euo pipefail
root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
cd "$root"
export MACOSX_DEPLOYMENT_TARGET=13.0
output="dist/网易云桌面歌词.app"
bundle_id="com.local.netease-desktop-lyrics"
while (( $# > 0 )); do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    --bundle-id) bundle_id="$2"; shift 2 ;;
    *) print -u2 "Unknown argument: $1"; exit 2 ;;
  esac
done
if [[ ! "$bundle_id" =~ '^[A-Za-z0-9.-]+$' ]]; then
  print -u2 'Invalid bundle identifier'
  exit 2
fi
cargo build --release
if [[ "$output" = /* ]]; then app="$output"; else app="$root/$output"; fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp app/Info.plist "$app/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$bundle_id" "$app/Contents/Info.plist"
engine="$app/Contents/Resources/netease-lyrics-rs"
executable="$app/Contents/MacOS/NeteaseDesktopLyrics"
cp target/release/netease-lyrics-rs "$engine"
xcrun swiftc -O -warnings-as-errors -target arm64-apple-macos13.0 \
  -framework AppKit -framework Foundation Sources/DesktopLyrics/*.swift \
  -o "$executable"
chmod +x "$executable" "$engine"
plutil -lint "$app/Contents/Info.plist"
# The locally built app must have a stable bundle identity and sealed resources.
# Ad-hoc signing is not a substitute for granting Accessibility to the app itself.
codesign --force --sign - --identifier "$bundle_id.engine" "$engine"
codesign --force --sign - --identifier "$bundle_id" "$app"
codesign --verify --deep --strict "$app"
printf 'Built %s\n' "$app"
