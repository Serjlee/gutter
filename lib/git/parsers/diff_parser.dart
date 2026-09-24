/// Unified diff parsing.
library;

enum DiffLineType { context, add, remove, noNewline }

class DiffLine {
  DiffLine(this.type, this.text, {this.oldNo, this.newNo});

  final DiffLineType type;

  /// Line content without the leading +/-/space marker.
  final String text;
  final int? oldNo;
  final int? newNo;

  bool get isChange =>
      type == DiffLineType.add || type == DiffLineType.remove;

  String get marker {
    switch (type) {
      case DiffLineType.context:
        return ' ';
      case DiffLineType.add:
        return '+';
      case DiffLineType.remove:
        return '-';
      case DiffLineType.noNewline:
        return '\\';
    }
  }
}

class Hunk {
  Hunk({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.section,
    required this.lines,
  });

  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;

  /// Text after the second `@@` (function context), may be empty.
  final String section;
  final List<DiffLine> lines;

  String get header =>
      '@@ -$oldStart,$oldCount +$newStart,$newCount @@${section.isEmpty ? '' : ' $section'}';

  int get additions => lines.where((l) => l.type == DiffLineType.add).length;
  int get deletions => lines.where((l) => l.type == DiffLineType.remove).length;
}

class FileDiff {
  FileDiff({
    required this.headerLines,
    required this.oldPath,
    required this.newPath,
    required this.hunks,
    this.isBinary = false,
    this.isNew = false,
    this.isDeleted = false,
  });

  /// Raw header lines (`diff --git`, `index`, mode lines, `---`, `+++`).
  final List<String> headerLines;
  final String? oldPath;
  final String? newPath;
  final List<Hunk> hunks;
  final bool isBinary;
  final bool isNew;
  final bool isDeleted;

  String get path => newPath ?? oldPath ?? '';
  int get additions => hunks.fold(0, (a, h) => a + h.additions);
  int get deletions => hunks.fold(0, (a, h) => a + h.deletions);
}

final _hunkRe = RegExp(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@ ?(.*)$');

String? _stripPrefix(String p) {
  if (p == '/dev/null') return null;
  if (p.startsWith('"') && p.endsWith('"')) {
    p = p.substring(1, p.length - 1);
  }
  if (p.startsWith('a/') || p.startsWith('b/')) return p.substring(2);
  return p;
}

/// Parses a unified diff possibly containing several files.
List<FileDiff> parseDiff(String text) {
  final files = <FileDiff>[];
  final lines = text.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();

  var i = 0;
  while (i < lines.length) {
    if (!lines[i].startsWith('diff ')) {
      i++;
      continue;
    }
    final header = <String>[lines[i]];
    String? oldPath, newPath;
    var binary = false, isNew = false, isDeleted = false;
    // Paths from "diff --git a/x b/y" as a fallback (no ---/+++ for binary
    // or mode-only changes).
    final gitLine = lines[i];
    final m = RegExp(r'^diff --git a/(.*) b/(.*)$').firstMatch(gitLine);
    if (m != null) {
      oldPath = m.group(1);
      newPath = m.group(2);
    }
    i++;
    while (i < lines.length &&
        !lines[i].startsWith('@@') &&
        !lines[i].startsWith('diff ')) {
      final l = lines[i];
      header.add(l);
      if (l.startsWith('--- ')) {
        oldPath = _stripPrefix(l.substring(4));
        if (oldPath == null) isNew = true;
      } else if (l.startsWith('+++ ')) {
        newPath = _stripPrefix(l.substring(4));
        if (newPath == null) isDeleted = true;
      } else if (l.startsWith('new file mode')) {
        isNew = true;
      } else if (l.startsWith('deleted file mode')) {
        isDeleted = true;
      } else if (l.startsWith('rename from ')) {
        oldPath = l.substring('rename from '.length);
      } else if (l.startsWith('rename to ')) {
        newPath = l.substring('rename to '.length);
      } else if (l.startsWith('Binary files ') || l == 'GIT binary patch') {
        binary = true;
      }
      i++;
    }
    if (isNew) oldPath = null;
    if (isDeleted) newPath = null;

    final hunks = <Hunk>[];
    while (i < lines.length && lines[i].startsWith('@@')) {
      final hm = _hunkRe.firstMatch(lines[i]);
      if (hm == null) {
        i++;
        continue;
      }
      final oldStart = int.parse(hm.group(1)!);
      final oldCount = hm.group(2) == null ? 1 : int.parse(hm.group(2)!);
      final newStart = int.parse(hm.group(3)!);
      final newCount = hm.group(4) == null ? 1 : int.parse(hm.group(4)!);
      i++;
      var o = oldStart, n = newStart;
      var remOld = oldCount, remNew = newCount;
      final hl = <DiffLine>[];
      while (i < lines.length) {
        final l = lines[i];
        if (l.startsWith('\\')) {
          hl.add(DiffLine(DiffLineType.noNewline, l.substring(1).trim()));
          i++;
          continue;
        }
        if (remOld <= 0 && remNew <= 0) break;
        if (l.startsWith('+')) {
          hl.add(DiffLine(DiffLineType.add, l.substring(1), newNo: n++));
          remNew--;
        } else if (l.startsWith('-')) {
          hl.add(DiffLine(DiffLineType.remove, l.substring(1), oldNo: o++));
          remOld--;
        } else if (l.startsWith(' ') || l.isEmpty) {
          hl.add(DiffLine(DiffLineType.context,
              l.isEmpty ? '' : l.substring(1),
              oldNo: o++, newNo: n++));
          remOld--;
          remNew--;
        } else {
          break;
        }
        i++;
      }
      hunks.add(Hunk(
        oldStart: oldStart,
        oldCount: oldCount,
        newStart: newStart,
        newCount: newCount,
        section: hm.group(5) ?? '',
        lines: hl,
      ));
    }
    files.add(FileDiff(
      headerLines: header,
      oldPath: oldPath,
      newPath: newPath,
      hunks: hunks,
      isBinary: binary,
      isNew: isNew,
      isDeleted: isDeleted,
    ));
  }
  return files;
}
