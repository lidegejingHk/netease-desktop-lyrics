#!/bin/zsh
set -euo pipefail
root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
app="$root/dist/网易云桌面歌词.app"
if [[ ! -x "$app/Contents/MacOS/NeteaseDesktopLyrics" || ! -x "$app/Contents/Resources/netease-lyrics-rs" ]]; then
  "$root/scripts/build-app.sh"
fi
"$app/Contents/Resources/netease-lyrics-rs" --lyrics-json --interval-ms 300 \
  | "$app/Contents/MacOS/NeteaseDesktopLyrics" --stdin
