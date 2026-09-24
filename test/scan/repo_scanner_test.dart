import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/scan/repo_scanner.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('gutter_scan_');
    void repo(String rel, {bool gitFile = false}) {
      final d = Directory(p.join(root.path, rel))..createSync(recursive: true);
      if (gitFile) {
        File(p.join(d.path, '.git')).writeAsStringSync('gitdir: /elsewhere');
      } else {
        Directory(p.join(d.path, '.git', 'objects'))
            .createSync(recursive: true);
      }
    }

    repo('a');
    repo('a/nested/inner');
    repo('group/b');
    repo('group/worktree', gitFile: true);
    repo('node_modules/pkg'); // skipped
    repo('.hidden/c'); // skipped
    repo('deep/1/2/3/4/5'); // beyond depth 3
  });

  tearDown(() => root.deleteSync(recursive: true));

  List<String> rel(List<String> paths) =>
      paths.map((x) => p.relative(x, from: root.path)).toList()..sort();

  test('finds repositories, nested ones and worktrees; honours skips', () {
    final found = <String>[];
    RepoScan.scanSync(root.path, 8, found.add);
    expect(rel(found), [
      'a',
      'a/nested/inner',
      'deep/1/2/3/4/5',
      'group/b',
      'group/worktree',
    ]);
  });

  test('depth limit', () {
    final found = <String>[];
    RepoScan.scanSync(root.path, 3, found.add);
    expect(rel(found), ['a', 'a/nested/inner', 'group/b', 'group/worktree']);
  });

  test('isolate scan streams results', () async {
    final scan = await RepoScan.start(root.path);
    final found = await scan.results.toList();
    expect(rel(found), hasLength(5));
  });
}
