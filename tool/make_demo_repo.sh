#!/usr/bin/env bash
# Creates a small branchy repository (with a remote, tags, stashes and
# uncommitted changes) for manually trying out Gutter and for the README
# screenshots.
# Usage: tool/make_demo_repo.sh <dir>
set -euo pipefail

dir=${1:?usage: make_demo_repo.sh <dir>}
rm -rf "$dir" "$dir.remote.git"
mkdir -p "$dir"
cd "$dir"

export GIT_AUTHOR_DATE GIT_COMMITTER_DATE
t=1720000000
g() { git -c user.name="$author" -c user.email="${author// /.}@example.com" "$@"; }
at() { GIT_AUTHOR_DATE="$1 +0000"; GIT_COMMITTER_DATE="$1 +0000"; }
# commit <message> [file]: appends a line to the file (default notes.txt),
# unless the file was already written (stdin of `code`).
commit() {
  t=$((t + 3600))
  at $t
  local f=${2:-notes.txt} prefix=''
  [[ $f == *.dart ]] && prefix='// '
  [[ -n "${wrote:-}" ]] || echo "$prefix$1 $RANDOM" >> "$f"
  wrote=
  g add -A
  g commit -qm "$1"
}
# code <file>: writes stdin to the file for the next commit.
code() { cat > "$1"; wrote=1; }
# stash_at <offset> <message>: stashes the current changes, dated <offset>
# seconds after the last commit.
stash_at() { at $((t + $1)); g stash push -q -m "$2"; }

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
echo "final rememberMe = Checkbox(value: false);" >> login.dart
stash_at 1800 "WIP remember-me checkbox"
git checkout -q main
author="Ada Lovelace"
commit "Fix typo in README" README.md
git checkout -qb feature/graph
author="Linus Torvalds"
code graph.dart <<'DART'
import 'dart:ui';

/// Assigns each commit a lane (column) in the graph.
class LaneLayout {
  LaneLayout(this.commits);

  final List<Commit> commits;
  final lanes = <String?>[];

  /// The lane of [commit]: the one waiting for it, or a new one.
  int laneFor(Commit commit) {
    final i = lanes.indexOf(commit.sha);
    if (i >= 0) return i;
    lanes.add(commit.sha);
    return lanes.length - 1;
  }
}

/// Draws the edge between a commit and its parent.
void drawEdge(Canvas canvas, Offset from, Offset to, Paint paint) {
  canvas.drawLine(from, to, paint);
}
DART
commit "Lane layout algorithm" graph.dart
code graph.dart <<'DART'
import 'dart:ui';

/// Assigns each commit a lane (column) in the graph.
class LaneLayout {
  LaneLayout(this.commits);

  final List<Commit> commits;
  final lanes = <String?>[];

  /// The lane of [commit]: the one waiting for it, or a new one.
  int laneFor(Commit commit) {
    final i = lanes.indexOf(commit.sha);
    if (i >= 0) return i;
    final free = lanes.indexOf(null); // reuse lanes of finished branches
    if (free >= 0) {
      lanes[free] = commit.sha;
      return free;
    }
    lanes.add(commit.sha);
    return lanes.length - 1;
  }
}

const cornerRadius = 8.0;

/// Draws the edge between a commit and its parent: sideways out of the
/// node, then a rounded corner down the parent's lane.
void drawEdge(Canvas canvas, Offset from, Offset to, Paint paint) {
  if (from.dx == to.dx) {
    canvas.drawLine(from, to, paint);
    return;
  }
  final sign = to.dx > from.dx ? 1.0 : -1.0;
  final path = Path()
    ..moveTo(from.dx, from.dy)
    ..lineTo(to.dx - sign * cornerRadius, from.dy)
    ..quadraticBezierTo(to.dx, from.dy, to.dx, from.dy + cornerRadius)
    ..lineTo(to.dx, to.dy);
  canvas.drawPath(path, paint);
}
DART
commit "Render edges with rounded corners" graph.dart
sed -i 's/quadraticBezierTo(/cubicTo(from.dx, from.dy, /' graph.dart
stash_at 1800 "Try cubic curves for corners"
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
