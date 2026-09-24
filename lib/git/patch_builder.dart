import 'parsers/diff_parser.dart';

/// Builds partial patches for staging / unstaging / discarding selected
/// lines of a diff, following git-gui's approach.
///
/// For a forward patch (e.g. staging from the worktree diff):
///   - unselected `+` lines are dropped,
///   - unselected `-` lines become context.
/// For a reverse patch (applied with `git apply --reverse`, e.g. unstaging
/// from the cached diff or discarding from the worktree diff):
///   - unselected `+` lines become context,
///   - unselected `-` lines are dropped.
class PatchBuilder {
  /// Returns a patch for [file] restricted to [selection], which maps hunk
  /// indexes to the selected line indexes (into `hunk.lines`); a null set
  /// selects the whole hunk. With [reverse] the patch is meant to be applied
  /// with `git apply --reverse`.
  /// Returns null if the selection contains no changes.
  static String? build(
    FileDiff file, {
    required Map<int, Set<int>?> selection,
    bool reverse = false,
  }) {
    final out = StringBuffer();
    final partial = !_selectsEverything(file, selection);
    if (partial && (file.isNew || file.isDeleted)) {
      // A partial new/deleted-file patch is really a modification of the
      // (possibly empty) file; rewrite the header accordingly.
      final p = file.path;
      out.writeln('diff --git a/$p b/$p');
      out.writeln('--- a/$p');
      out.writeln('+++ b/$p');
    } else {
      for (final h in file.headerLines) {
        out.writeln(h);
      }
    }
    var any = false;
    final hunkIdx = selection.keys.toList()..sort();
    // Delta applied to subsequent hunk starts because earlier hunks in this
    // patch may have fewer changes than the original.
    var shift = 0;
    for (final hi in hunkIdx) {
      final hunk = file.hunks[hi];
      final sel = selection[hi];
      final body = <String>[];
      var oldCount = 0, newCount = 0;
      var hasChange = false;
      var lastKept = true;
      for (var li = 0; li < hunk.lines.length; li++) {
        final l = hunk.lines[li];
        final isSel = sel == null || sel.contains(li);
        switch (l.type) {
          case DiffLineType.context:
            body.add(' ${l.text}');
            oldCount++;
            newCount++;
            lastKept = true;
            break;
          case DiffLineType.add:
            if (isSel) {
              body.add('+${l.text}');
              newCount++;
              hasChange = true;
              lastKept = true;
            } else if (reverse) {
              body.add(' ${l.text}');
              oldCount++;
              newCount++;
              lastKept = true;
            } else {
              lastKept = false;
            }
            break;
          case DiffLineType.remove:
            if (isSel) {
              body.add('-${l.text}');
              oldCount++;
              hasChange = true;
              lastKept = true;
            } else if (!reverse) {
              body.add(' ${l.text}');
              oldCount++;
              newCount++;
              lastKept = true;
            } else {
              lastKept = false;
            }
            break;
          case DiffLineType.noNewline:
            if (lastKept) body.add('\\ No newline at end of file');
            break;
        }
      }
      if (!hasChange) continue;
      any = true;
      int oldStart, newStart;
      if (reverse) {
        newStart = hunk.newStart;
        oldStart = hunk.newStart + shift;
      } else {
        oldStart = hunk.oldStart;
        newStart = hunk.oldStart + shift;
      }
      shift += reverse ? oldCount - newCount : newCount - oldCount;
      out.writeln('@@ -$oldStart,$oldCount +$newStart,$newCount @@');
      for (final b in body) {
        out.writeln(b);
      }
    }
    return any ? out.toString() : null;
  }

  static bool _selectsEverything(FileDiff file, Map<int, Set<int>?> sel) {
    for (var hi = 0; hi < file.hunks.length; hi++) {
      if (!sel.containsKey(hi)) return false;
      final s = sel[hi];
      if (s == null) continue;
      final lines = file.hunks[hi].lines;
      for (var li = 0; li < lines.length; li++) {
        if (lines[li].isChange && !s.contains(li)) return false;
      }
    }
    return true;
  }

  /// Convenience: patch for a whole hunk.
  static String? hunk(FileDiff file, int hunkIndex, {bool reverse = false}) =>
      build(file, selection: {hunkIndex: null}, reverse: reverse);
}
