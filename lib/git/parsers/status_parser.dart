import '../models.dart';

/// Parses `git status --porcelain=v2 -z --branch` output.
WorkingTreeStatus parseStatus(String text) {
  String? oid, head, upstream;
  var ahead = 0, behind = 0;
  final entries = <StatusEntry>[];
  final parts = text.split('\x00');
  for (var i = 0; i < parts.length; i++) {
    final line = parts[i];
    if (line.isEmpty) continue;
    if (line.startsWith('# ')) {
      final rest = line.substring(2);
      if (rest.startsWith('branch.oid ')) {
        final v = rest.substring('branch.oid '.length);
        oid = v == '(initial)' ? null : v;
      } else if (rest.startsWith('branch.head ')) {
        final v = rest.substring('branch.head '.length);
        head = v == '(detached)' ? null : v;
      } else if (rest.startsWith('branch.upstream ')) {
        upstream = rest.substring('branch.upstream '.length);
      } else if (rest.startsWith('branch.ab ')) {
        final m = RegExp(r'\+(\d+) -(\d+)').firstMatch(rest);
        if (m != null) {
          ahead = int.parse(m.group(1)!);
          behind = int.parse(m.group(2)!);
        }
      }
      continue;
    }
    final kind = line[0];
    switch (kind) {
      case '1':
        // 1 XY sub mH mI mW hH hI path
        final f = _splitN(line, 9);
        entries.add(_ordinary(f[1], f[8]));
        break;
      case '2':
        // 2 XY sub mH mI mW hH hI Xscore path \0 origPath
        final f = _splitN(line, 10);
        final orig = i + 1 < parts.length ? parts[++i] : null;
        entries.add(_ordinary(f[1], f[9], oldPath: orig));
        break;
      case 'u':
        // u XY sub m1 m2 m3 mW h1 h2 h3 path
        final f = _splitN(line, 11);
        entries.add(StatusEntry(
          path: f[10],
          index: ChangeKind.conflicted,
          worktree: ChangeKind.conflicted,
          conflicted: true,
          conflictCode: f[1],
        ));
        break;
      case '?':
        entries.add(StatusEntry(
          path: line.substring(2),
          index: null,
          worktree: ChangeKind.untracked,
        ));
        break;
      default:
        // '!' ignored files and anything unknown are skipped.
        break;
    }
  }
  return WorkingTreeStatus(
    branch: BranchStatus(
      head: head,
      oid: oid,
      upstream: upstream,
      ahead: ahead,
      behind: behind,
    ),
    entries: entries,
  );
}

StatusEntry _ordinary(String xy, String path, {String? oldPath}) {
  ChangeKind? k(String c) => c == '.' ? null : changeKindFromLetter(c);
  return StatusEntry(
    path: path,
    oldPath: oldPath,
    index: k(xy[0]),
    worktree: k(xy[1]),
  );
}

/// Splits [line] on spaces into exactly [n] fields; the last field keeps any
/// remaining spaces (paths may contain spaces).
List<String> _splitN(String line, int n) {
  final out = <String>[];
  var start = 0;
  for (var i = 0; i < n - 1; i++) {
    final sp = line.indexOf(' ', start);
    if (sp < 0) break;
    out.add(line.substring(start, sp));
    start = sp + 1;
  }
  out.add(line.substring(start));
  while (out.length < n) {
    out.add('');
  }
  return out;
}

/// Parses `git diff-tree -r -z --name-status -M` (and `git diff --name-status -z`).
List<FileChange> parseNameStatus(String text) {
  final out = <FileChange>[];
  final parts = text.split('\x00');
  var i = 0;
  while (i < parts.length) {
    final status = parts[i];
    if (status.isEmpty) {
      i++;
      continue;
    }
    // diff-tree without --no-commit-id may print the commit sha first.
    if (RegExp(r'^[0-9a-f]{40,64}$').hasMatch(status)) {
      i++;
      continue;
    }
    final letter = status[0];
    final kind = changeKindFromLetter(letter);
    if (kind == ChangeKind.renamed || kind == ChangeKind.copied) {
      if (i + 2 >= parts.length) break;
      out.add(FileChange(path: parts[i + 2], oldPath: parts[i + 1], kind: kind));
      i += 3;
    } else {
      if (i + 1 >= parts.length) break;
      out.add(FileChange(path: parts[i + 1], kind: kind));
      i += 2;
    }
  }
  return out;
}
