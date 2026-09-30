import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/temp_repo.dart';

void main() {
  late TempRepo up;
  late TempRepo t;
  late Directory worktree;

  setUp(() async {
    up = await TempRepo.create();
    up.git(['config', 'receive.denyCurrentBranch', 'ignore']);
    up.commit('one', {'a.txt': '1\n'});
    t = await TempRepo.create();
    worktree = Directory('${t.path}-wt');
    t.git(['remote', 'add', 'origin', up.path]);
    t.git(['fetch', '-q', 'origin']);
    t.git(['remote', 'set-head', 'origin', 'main']);
    t.git(['reset', '-q', '--hard', 'origin/main']);
    t.git(['branch', '-q', '--set-upstream-to=origin/main']);

    // Merged into origin/main: by fast-forward, and by a merge commit.
    t.git(['branch', 'done-ff']);
    t.git(['checkout', '-q', '-b', 'done-merge']);
    t.commit('side work', {'b.txt': 'b\n'});
    t.git(['checkout', '-q', 'main']);
    t.commit('main work', {'a.txt': '2\n'});
    t.git(['merge', '-q', '--no-ff', '-m', 'merge', 'done-merge']);
    t.git(['push', '-q', 'origin', 'main']);
    // Not merged.
    t.git(['checkout', '-q', '-b', 'wip']);
    t.commit('wip', {'c.txt': 'c\n'});
    // Pushed, then deleted on the remote (a squash-merged PR, say).
    t.git(['checkout', '-q', '-b', 'squashed', 'main']);
    t.commit('squashed', {'d.txt': 'd\n'});
    t.git(['push', '-q', '-u', 'origin', 'squashed']);
    up.git(['branch', '-q', '-D', 'squashed']);
    t.git(['fetch', '-q', '--prune', 'origin']);
    // Merged, but checked out elsewhere.
    t.git(['worktree', 'add', '-q', '-b', 'in-worktree', worktree.path]);
    // Merged, but checked out here.
    t.git(['checkout', '-q', '-b', 'current', 'main']);
    // Local main, behind origin/main: merged, and kept.
    t.git(['branch', '-f', 'main', 'HEAD~1']);
  });

  tearDown(() {
    t.dispose();
    up.dispose();
    if (worktree.existsSync()) worktree.deleteSync(recursive: true);
  });

  test('finds merged branches, and those gone from the remote', () async {
    expect(await t.repo.mainBranch(), 'origin/main');
    final c = await t.repo.cleanupCandidates();
    expect(c.base, 'origin/main');
    expect(c.merged.map((b) => b.name), ['done-ff', 'done-merge']);
    expect(c.gone.map((b) => b.name), ['squashed']);
    expect(c.merged.first.date.year, greaterThan(2000));
  });

  test('deletes the chosen ones', () async {
    await t.repo.deleteBranches(['done-ff', 'squashed']);
    final left = t
        .git(['for-each-ref', '--format=%(refname:short)', 'refs/heads/'])
        .trim()
        .split('\n');
    expect(left, isNot(contains('done-ff')));
    expect(left, isNot(contains('squashed')));
    expect(left, containsAll(['done-merge', 'wip', 'current', 'main']));
  });

  test('without a remote, the local main is the base', () async {
    final local = await TempRepo.create();
    addTearDown(local.dispose);
    local.commit('one');
    local.git(['branch', 'old']);
    local.commit('two');
    local.git(['checkout', '-q', '-b', 'feature']);
    final c = await local.repo.cleanupCandidates();
    expect(c.base, 'main');
    expect(c.merged.map((b) => b.name), ['old']);
    expect(c.gone, isEmpty);
  });
}
