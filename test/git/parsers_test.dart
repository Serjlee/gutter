import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/git/models.dart';
import 'package:gutter/git/parsers/diff_parser.dart';
import 'package:gutter/git/parsers/log_parser.dart';
import 'package:gutter/git/parsers/refs_parser.dart';
import 'package:gutter/git/parsers/status_parser.dart';

void main() {
  group('log', () {
    test('parses NUL separated records', () {
      final a = 'a' * 40, b = 'b' * 40, c = 'c' * 40;
      final text = [
        '$a\x00$b $c\x00Ann Lee\x00ann@x.io\x001700000000\x00Merge x',
        '$b\x00\x00Bob\x00bob@x.io\x001600000000\x00Initial: with\ttab ünïcode',
      ].join('\x00');
      final commits = parseLogString(text);
      expect(commits, hasLength(2));
      expect(commits[0].parents, [b, c]);
      expect(commits[0].isMerge, isTrue);
      expect(commits[0].initials, 'AL');
      expect(commits[1].parents, isEmpty);
      expect(commits[1].subject, 'Initial: with\ttab ünïcode');
    });

    test('empty output', () {
      expect(parseLogString(''), isEmpty);
    });
  });

  test('refs', () {
    final text = [
      'refs/heads/main\x00${'1' * 40}\x00\x00refs/remotes/origin/main\x00ahead 2, behind 3\x00*\x00subject',
      'refs/heads/gone\x00${'2' * 40}\x00\x00refs/remotes/origin/gone\x00gone\x00 \x00s',
      'refs/tags/v1\x00${'3' * 40}\x00${'4' * 40}\x00\x00\x00 \x00tag msg',
      'refs/remotes/origin/HEAD\x00${'1' * 40}\x00\x00\x00\x00 \x00s',
    ].join('\n');
    final refs = parseRefs(text);
    expect(refs[0].isHead, isTrue);
    expect(refs[0].ahead, 2);
    expect(refs[0].behind, 3);
    expect(refs[0].type, RefType.localBranch);
    expect(refs[1].upstreamGone, isTrue);
    expect(refs[2].sha, '4' * 40, reason: 'annotated tags are peeled');
    expect(refs[2].name, 'v1');
    expect(refs[3].isRemoteHead, isTrue);
    expect(refs[3].remote, 'origin');
  });

  group('status v2', () {
    test('branch headers and entries', () {
      final text = [
        '# branch.oid ${'a' * 40}',
        '# branch.head feature/x',
        '# branch.upstream origin/feature/x',
        '# branch.ab +1 -2',
        '1 M. N... 100644 100644 100644 ${'1' * 40} ${'2' * 40} staged file.txt',
        '1 .M N... 100644 100644 100644 ${'1' * 40} ${'2' * 40} dir/with space.txt',
        '2 R. N... 100644 100644 100644 ${'1' * 40} ${'2' * 40} R100 new name.txt',
        'old name.txt',
        'u UU N... 100644 100644 100644 100644 ${'1' * 40} ${'2' * 40} ${'3' * 40} conflict.txt',
        '? untracked.txt',
        '',
      ].join('\x00');
      final s = parseStatus(text);
      expect(s.branch.head, 'feature/x');
      expect(s.branch.upstream, 'origin/feature/x');
      expect(s.branch.ahead, 1);
      expect(s.branch.behind, 2);
      expect(s.entries, hasLength(5));
      expect(s.entries[0].path, 'staged file.txt');
      expect(s.entries[0].index, ChangeKind.modified);
      expect(s.entries[0].worktree, isNull);
      expect(s.entries[1].path, 'dir/with space.txt');
      expect(s.entries[1].hasUnstaged, isTrue);
      expect(s.entries[2].oldPath, 'old name.txt');
      expect(s.entries[2].index, ChangeKind.renamed);
      expect(s.entries[3].conflicted, isTrue);
      expect(s.entries[4].isUntracked, isTrue);
      expect(s.staged.map((e) => e.path), ['staged file.txt', 'new name.txt']);
    });

    test('detached and initial', () {
      final s = parseStatus(
        '# branch.oid (initial)\x00# branch.head (detached)\x00',
      );
      expect(s.branch.detached, isTrue);
      expect(s.branch.oid, isNull);
      expect(s.isClean, isTrue);
    });
  });

  test('name-status with renames', () {
    final text = [
      'M',
      'a.txt',
      'R087',
      'old.txt',
      'new.txt',
      'A',
      'x y.txt',
      'D',
      'gone',
      '',
    ].join('\x00');
    final files = parseNameStatus(text);
    expect(files.map((f) => f.kind), [
      ChangeKind.modified,
      ChangeKind.renamed,
      ChangeKind.added,
      ChangeKind.deleted,
    ]);
    expect(files[1].oldPath, 'old.txt');
    expect(files[1].path, 'new.txt');
    expect(files[2].path, 'x y.txt');
  });

  group('diff', () {
    test('multi-hunk file with no-newline marker', () {
      const text = '''diff --git a/f.txt b/f.txt
index 111..222 100644
--- a/f.txt
+++ b/f.txt
@@ -1,3 +1,3 @@ section
 one
-two
+TWO
 three
@@ -10,2 +10,3 @@
 ten
 eleven
+twelve
\\ No newline at end of file
''';
      final files = parseDiff(text);
      expect(files, hasLength(1));
      final f = files.single;
      expect(f.path, 'f.txt');
      expect(f.hunks, hasLength(2));
      expect(f.hunks[0].section, 'section');
      expect(f.hunks[0].lines.map((l) => l.marker).join(), ' -+ ');
      expect(f.hunks[0].lines[2].newNo, 2);
      expect(f.hunks[1].lines.last.type, DiffLineType.noNewline);
      expect(f.additions, 2);
      expect(f.deletions, 1);
    });

    test('new, deleted, binary and rename', () {
      const text = '''diff --git a/n.txt b/n.txt
new file mode 100644
index 000..111
--- /dev/null
+++ b/n.txt
@@ -0,0 +1 @@
+hello
diff --git a/img.png b/img.png
index 1..2 100644
Binary files a/img.png and b/img.png differ
diff --git a/a.txt b/b.txt
similarity index 100%
rename from a.txt
rename to b.txt
diff --git a/d.txt b/d.txt
deleted file mode 100644
--- a/d.txt
+++ /dev/null
@@ -1 +0,0 @@
-bye
''';
      final files = parseDiff(text);
      expect(files, hasLength(4));
      expect(files[0].isNew, isTrue);
      expect(files[0].oldPath, isNull);
      expect(files[0].hunks.single.lines.single.text, 'hello');
      expect(files[1].isBinary, isTrue);
      expect(files[2].oldPath, 'a.txt');
      expect(files[2].newPath, 'b.txt');
      expect(files[3].isDeleted, isTrue);
      expect(files[3].path, 'd.txt');
    });
  });
}
