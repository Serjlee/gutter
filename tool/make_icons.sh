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
# Square master: the logo fills ~80% of the canvas, on transparency.
convert "$src" -trim +repage -filter Lanczos -resize 824x824 \
  -background none -gravity center -extent 1024x1024 "$work/icon.png"

# macOS icon: the logo on a dark bluish-gray rounded tile following Apple's
# icon grid (824 px tile on a 1024 px canvas, with a soft drop shadow).
# Without a tile of its own, macOS puts the icon on a light gray one.
tile=824 radius=185
convert -size ${tile}x$tile gradient:'#323A48'-'#171B22' "$work/fill.png"
convert -size ${tile}x$tile xc:none -fill white \
  -draw "roundrectangle 0,0 $((tile - 1)),$((tile - 1)) $radius,$radius" \
  "$work/mask.png"
convert "$work/fill.png" "$work/mask.png" -alpha off \
  -compose CopyOpacity -composite "$work/tile.png"
# A faint light edge so the tile reads against dark docks too.
convert "$work/tile.png" -fill none -stroke 'rgba(255,255,255,0.10)' \
  -strokewidth 3 \
  -draw "roundrectangle 1,1 $((tile - 2)),$((tile - 2)) $radius,$radius" \
  "$work/tile.png"
convert "$src" -trim +repage -filter Lanczos -resize 600x600 "$work/logo.png"
convert "$work/tile.png" "$work/logo.png" -gravity center -compose over \
  -composite "$work/tile.png"
convert "$work/tile.png" \( +clone -background black -shadow 45x14+0+12 \) \
  +swap -background none -layers merge +repage \
  -gravity center -extent 1024x1024 "$work/mac.png"
for s in 16 32 64 128 256 512 1024; do
  convert "$work/mac.png" -filter Lanczos -resize "${s}x$s" -strip "$mac/app_icon_$s.png"
done

# Linux window icon.
convert "$work/icon.png" -filter Lanczos -resize 256x256 -strip assets/icon/icon_256.png
# Linux app icons (Flatpak), in the usual hicolor sizes.
mkdir -p linux/flatpak/icons
for s in 48 64 128 256 512; do
  convert "$work/icon.png" -filter Lanczos -resize "${s}x$s" -strip "linux/flatpak/icons/$s.png"
done
echo "Icons updated."
