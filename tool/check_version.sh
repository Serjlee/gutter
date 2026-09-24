#!/usr/bin/env bash
# Fails unless the compiled Dart code at $1 embeds the version $2 and the
# commit $3 (the --dart-define values the home tab shows). Guards releases
# against builds that would show "unknown version".
#
# Usage: tool/check_version.sh <libapp.so | App.framework/App> <version> <commit>
set -euo pipefail

binary="$1" version="$2" commit="$3"
found=$(mktemp)
trap 'rm -f "$found"' EXIT
strings -a "$binary" > "$found"
status=0
for value in "$version" "$commit"; do
  [[ -z "$value" ]] && continue
  if grep -qxF "$value" "$found"; then
    echo "found $value in $binary"
  else
    echo "error: $value is not embedded in $binary" >&2
    status=1
  fi
done
exit $status
