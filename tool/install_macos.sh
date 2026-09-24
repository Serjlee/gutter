#!/usr/bin/env bash
# Installs Gutter on macOS from a release zip and clears the quarantine flag
# (the build is not notarized, so Gatekeeper would otherwise block it).
#
# Usage:
#   tool/install_macos.sh                   # download the latest release (needs gh)
#   tool/install_macos.sh Gutter-macos.zip  # install a zip you already downloaded
set -euo pipefail

repo="serjlee/gutter"
dest="/Applications"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "This script is for macOS." >&2
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

if [[ $# -ge 1 ]]; then
  zip="$1"
else
  if ! command -v gh >/dev/null; then
    echo "Install the GitHub CLI (brew install gh) or pass a downloaded zip." >&2
    exit 1
  fi
  echo "Downloading the latest release of $repo…"
  gh release download --repo "$repo" --pattern 'Gutter-macos-*.zip' --dir "$work"
  zip=$(ls "$work"/Gutter-macos-*.zip)
fi

ditto -x -k "$zip" "$work/app"
if [[ ! -d "$work/app/Gutter.app" ]]; then
  echo "Gutter.app not found in $zip" >&2
  exit 1
fi

if pgrep -x Gutter >/dev/null; then
  echo "Quit Gutter before updating." >&2
  exit 1
fi

rm -rf "$dest/Gutter.app"
ditto "$work/app/Gutter.app" "$dest/Gutter.app"
xattr -dr com.apple.quarantine "$dest/Gutter.app" 2>/dev/null || true

if ! command -v git >/dev/null; then
  echo "Note: git was not found. Install it with: xcode-select --install" >&2
fi
echo "Installed $dest/Gutter.app"
