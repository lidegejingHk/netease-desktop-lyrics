#!/bin/zsh
set -euo pipefail

# Pinned Sparkle release used for in-app updates. The framework is not committed;
# run this once per checkout (build-app.sh calls it automatically when missing).
version="2.10.1"
sha256="1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"
url="${SPARKLE_URL:-https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz}"

root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
dest="$root/vendor/sparkle"
archive="$root/vendor/Sparkle-$version.tar.xz"

if [[ -d "$dest/Sparkle.framework" ]]; then
  exit 0
fi

mkdir -p "$root/vendor"
if [[ ! -f "$archive" ]]; then
  curl -fL --retry 3 --retry-delay 2 -o "$archive" "$url"
fi
actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
if [[ "$actual" != "$sha256" ]]; then
  print -u2 "Sparkle checksum mismatch: expected $sha256, got $actual"
  rm -f "$archive"
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tar -xJf "$archive" -C "$tmp"
framework="$(find "$tmp" -maxdepth 3 -name Sparkle.framework -type d | head -1)"
if [[ -z "$framework" ]]; then
  print -u2 "Sparkle.framework not found in $archive"
  exit 1
fi
rm -rf "$dest"
mkdir -p "$dest"
cp -R "$(dirname "$framework")"/. "$dest"/
print "Sparkle $version ready at $dest"
