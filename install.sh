#!/usr/bin/env bash
set -euo pipefail

url="https://github.com/pulkitxm/botch/releases/latest/download/Botch.zip"
target="/Applications/Botch.app"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading the latest Botch release"
curl -fsSL "$url" -o "$tmp/Botch.zip"
ditto -x -k "$tmp/Botch.zip" "$tmp"
test -d "$tmp/Botch.app"

pkill -x Botch 2>/dev/null || true
rm -rf "$target"
ditto "$tmp/Botch.app" "$target"
xattr -dr com.apple.quarantine "$target" 2>/dev/null || true
open -a "$target"
echo "Installed $target"
