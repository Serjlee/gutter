#!/usr/bin/env bash
# Regenerates the app icons and the in-app logo from assets/icon/source.png
# (transparent background). Needs ImageMagick.
set -euo pipefail
cd "$(dirname "$0")/.."

src=assets/icon/source.png
mac=macos/Runner/Assets.xcassets/AppIcon.appiconset
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# In-app logo (home tab title), trimmed.
convert "$src" -trim +repage -filter Lanczos -resize x256 -strip assets/icon/logo.png
# Square master: the logo fills ~80% of the canvas, like the macOS icon grid.
convert "$src" -trim +repage -filter Lanczos -resize 824x824 \
  -background none -gravity center -extent 1024x1024 "$work/icon.png"
for s in 16 32 64 128 256 512 1024; do
  convert "$work/icon.png" -filter Lanczos -resize "${s}x$s" -strip "$mac/app_icon_$s.png"
done
# Linux window icon.
convert "$work/icon.png" -filter Lanczos -resize 256x256 -strip assets/icon/icon_256.png
echo "Icons updated."
