#!/bin/zsh
set -euo pipefail

# Packages the built app, mirrors it into site/downloads, updates site/config.json,
# signs it for Sparkle, and rewrites appcast.xml.
# Usage: ./scripts/prepare-release.sh [path/to/zip]
# Set SITE_BASE_URL to the deployed site origin so the appcast points at the mirror;
# without it the appcast falls back to the GitHub release asset.

root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
cd "$root"

version="$(plutil -extract CFBundleShortVersionString raw app/Info.plist)"
build="$(plutil -extract CFBundleVersion raw app/Info.plist)"
app="$root/dist/网易云桌面歌词.app"
zip_path="${1:-}"

if [[ -z "$zip_path" ]]; then
  if [[ ! -d "$app" ]]; then
    print -u2 "Missing $app; run ./scripts/build-app.sh first."
    exit 1
  fi
  zip_path="$root/dist/NeteaseDesktopLyrics-v$version-macos-arm64.zip"
  rm -f "$zip_path"
  ditto -c -k --keepParent "$app" "$zip_path"
fi
if [[ ! -f "$zip_path" ]]; then
  print -u2 "Zip not found: $zip_path"
  exit 1
fi

mkdir -p site/downloads
find site/downloads -maxdepth 1 -name '*.zip' -delete
zip_name="$(basename "$zip_path")"
target="site/downloads/$zip_name"
cp "$zip_path" "$target"

size="$(stat -f%z "$target")"
sha="$(shasum -a 256 "$target" | awk '{print $1}')"
relative="downloads/$zip_name"

python3 - "$version" "$build" "$size" "$sha" "$relative" > site/config.json <<'PY'
import json, sys
version, build, size, sha, relative = sys.argv[1:6]
print(json.dumps({
    "version": version,
    "build": build,
    "download": relative,
    "size": int(size),
    "sha256": sha,
    "minimumSystemVersion": "13.0",
    "architecture": "arm64",
}, ensure_ascii=False, indent=2))
PY

signature_line="$(vendor/sparkle/bin/sign_update "$target")"
signature="$(print -r -- "$signature_line" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
signed_length="$(print -r -- "$signature_line" | sed -n 's/.*length="\([0-9]*\)".*/\1/p')"
if [[ -z "$signature" || "$signed_length" != "$size" ]]; then
  print -u2 "Sparkle signing failed or length mismatch: $signature_line"
  exit 1
fi

if [[ -n "${SITE_BASE_URL:-}" ]]; then
  enclosure="${SITE_BASE_URL%/}/$relative"
else
  enclosure="https://github.com/lidegejingHk/netease-desktop-lyrics/releases/download/v$version/$zip_name"
  print -u2 "warning: SITE_BASE_URL not set; appcast points at the GitHub asset."
fi

pubdate="$(date -R)"
python3 - "$version" "$build" "$enclosure" "$size" "$signature" "$pubdate" > appcast.xml <<'PY'
import sys
from html import escape
version, build, enclosure, size, signature, pubdate = sys.argv[1:7]
esc = lambda value: escape(value, quote=True)
print(f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>网易云桌面歌词</title>
    <link>https://cdn.jsdelivr.net/gh/lidegejingHk/netease-desktop-lyrics@main/appcast.xml</link>
    <description>网易云桌面歌词更新源</description>
    <language>zh-CN</language>
    <item>
      <title>{esc(version)}</title>
      <pubDate>{esc(pubdate)}</pubDate>
      <sparkle:version>{esc(build)}</sparkle:version>
      <sparkle:shortVersionString>{esc(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/lidegejingHk/netease-desktop-lyrics/releases/tag/v{esc(version)}</sparkle:releaseNotesLink>
      <enclosure url="{esc(enclosure)}" length="{esc(size)}" type="application/octet-stream" sparkle:edSignature="{esc(signature)}" />
    </item>
  </channel>
</rss>''')
PY

printf 'version:  %s (%s)\n' "$version" "$build"
printf 'zip:      %s (%s bytes)\n' "$target" "$size"
printf 'sha256:   %s\n' "$sha"
printf 'appcast:  %s\n' "$enclosure"
print "\nNext:"
print "  gh release create v$version --title \"网易云桌面歌词 v$version\" --notes-file notes.md \"$zip_path\""
print "  upload site/ (including site/downloads) to EdgeOne Pages"
print "  git add appcast.xml site/config.json && git commit && git push"
print "  curl -s https://purge.jsdelivr.net/gh/lidegejingHk/netease-desktop-lyrics@main/appcast.xml"
