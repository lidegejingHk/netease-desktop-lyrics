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
sparkle_dir="$root/vendor/sparkle"
if [[ ! -d "$sparkle_dir/Sparkle.framework" ]]; then
  "$root/scripts/fetch-sparkle.sh"
fi
if [[ "$output" = /* ]]; then app="$output"; else app="$root/$output"; fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp app/Info.plist "$app/Contents/Info.plist"
cp app/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
plutil -replace CFBundleIdentifier -string "$bundle_id" "$app/Contents/Info.plist"
engine="$app/Contents/Resources/netease-lyrics-rs"
executable="$app/Contents/MacOS/NeteaseDesktopLyrics"
cp target/release/netease-lyrics-rs "$engine"
xcrun swiftc -O -warnings-as-errors -target arm64-apple-macos13.0 \
  -framework AppKit -framework Foundation -framework ApplicationServices \
  -F "$sparkle_dir" -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  Sources/DesktopLyrics/*.swift \
  -o "$executable"
rm -rf "$app/Contents/Frameworks/Sparkle.framework"
ditto "$sparkle_dir/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
chmod +x "$executable" "$engine"
plutil -lint "$app/Contents/Info.plist"
# A stable identity keeps macOS TCC grants (Accessibility) valid across updates.
# Ad-hoc signatures change identity on every build, forcing users to re-grant.
signing_identity="${SIGN_IDENTITY:-NeteaseDesktopLyrics Signing}"
if security find-identity -p codesigning | grep -Fq "\"$signing_identity\""; then
  sign_id="$signing_identity"
else
  print -u2 "warning: signing identity '$signing_identity' not found; falling back to ad-hoc."
  print -u2 "warning: ad-hoc builds reset Accessibility grants on every rebuild."
  print -u2 "warning: run ./scripts/setup-signing.sh once to create a stable identity."
  sign_id="-"
fi
codesign --force --sign "$sign_id" --identifier "$bundle_id.engine" "$engine"
codesign --force --sign "$sign_id" --identifier "$bundle_id" "$app"
codesign --verify --deep --strict "$app"
printf 'Built %s\n' "$app"
