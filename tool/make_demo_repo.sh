#!/usr/bin/env bash
# Creates a small branchy repository (with a remote, tags, a stash and
# uncommitted changes) for manually trying out Gutter.
# Usage: tool/make_demo_repo.sh <dir>
set -euo pipefail

dir=${1:?usage: make_demo_repo.sh <dir>}
rm -rf "$dir" "$dir.remote.git"
mkdir -p "$dir"
cd "$dir"

export GIT_AUTHOR_DATE GIT_COMMITTER_DATE
t=1720000000
g() { git -c user.name="$author" -c user.email="${author// /.}@example.com" "$@"; }
commit() {
  t=$((t + 3600))
  GIT_AUTHOR_DATE="$t +0000"; GIT_COMMITTER_DATE="$t +0000"
  echo "$1 $RANDOM" >> "${2:-notes.txt}"
  g add -A
  g commit -qm "$1"
}

author="Ada Lovelace"
git init -q -b main
commit "Initial commit" README.md
commit "Add build scripts" build.sh
author="Grace Hopper"
commit "Set up CI pipeline" ci.yml
git checkout -qb feature/login
commit "Login form skeleton" login.dart
author="Alan Turing"
commit "Validate credentials" login.dart
git checkout -q main
author="Ada Lovelace"
commit "Fix typo in README" README.md
git checkout -qb feature/graph
author="Linus Torvalds"
commit "Lane layout algorithm" graph.dart
commit "Render edges with rounded corners" graph.dart
git checkout -q main
author="Grace Hopper"
t=$((t + 3600)); GIT_AUTHOR_DATE="$t +0000"; GIT_COMMITTER_DATE="$t +0000"
g merge -q --no-ff -m "Merge branch 'feature/login'" feature/login
g tag -a v0.1.0 -m "First release"
author="Margaret Hamilton"
commit "Bump dependencies" pubspec.yaml
git checkout -q feature/graph
author="Linus Torvalds"
commit "Virtualize graph rows" graph.dart
git checkout -q main
git checkout -qb hotfix/crash
author="Barbara Liskov"
commit "Guard against empty history" graph.dart
git checkout -q main
author="Grace Hopper"
t=$((t + 3600)); GIT_AUTHOR_DATE="$t +0000"; GIT_COMMITTER_DATE="$t +0000"
g merge -q --no-ff -m "Merge branch 'hotfix/crash'" hotfix/crash
commit "Document keyboard shortcuts" README.md
g tag v0.2.0
git checkout -qb experiment
author="Alan Turing"
commit "Try a different color palette" theme.dart
git checkout -q main

git init -q --bare "../$(basename "$dir").remote.git"
git remote add origin "../$(basename "$dir").remote.git"
git push -q -u origin main feature/graph 2>/dev/null
git push -q origin v0.1.0 v0.2.0 2>/dev/null
author="Ada Lovelace"
commit "Local work not pushed yet" README.md

echo "stashed change" >> theme.dart 2>/dev/null || true
g stash push -q -u -m "half-finished palette tweak"
printf 'line one\nline two changed\nline three\n' > README.md
echo "new file" > TODO.md
echo "staged" >> build.sh && git add build.sh
echo "Demo repository ready at $dir"
