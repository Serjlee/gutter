import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/git/git_runner.dart';

import '../support/temp_repo.dart';

void main() {
  late TempRepo t;
  setUp(() async => t = await TempRepo.create());
  tearDown(() => t.dispose());

  String fmt(String format, String rev) =>
      t.git(['log', '-1', '--format=$format', rev]).trim();

  test('rewords an older commit; the rest keep trees and authors', () async {
    t.commit('one', {'a.txt': '1\n'});
    final two = t.commit('two', {'a.txt': '2\n'});
    t.commit('three', {'b.txt': '3\n'});
    final before = {
      for (final rev in ['HEAD', 'HEAD~1', 'HEAD~2'])
        rev: (fmt('%T', rev), fmt('%an <%ae> %ad', rev)),
    };
    // Uncommitted work stays as it is.
    t.write('a.txt', 'staged\n');
    t.git(['add', 'a.txt']);
    t.write('b.txt', 'unstaged\n');

    final reworded = await t.repo.reword(two, 'Two, reworded\n\nWith a body.');
    expect(reworded, fmt('%H', 'HEAD~1'));
    expect(t.subjects(), ['three', 'Two, reworded', 'one']);
    expect(fmt('%B', 'HEAD~1'), 'Two, reworded\n\nWith a body.');
    for (final rev in before.keys) {
      expect((fmt('%T', rev), fmt('%an <%ae> %ad', rev)), before[rev]);
    }
    expect(fmt('%H', 'HEAD~1'), isNot(two));
    expect(t.git(['symbolic-ref', 'HEAD']).trim(), 'refs/heads/main');
    expect(t.git(['diff', '--cached', '--name-only']).trim(), 'a.txt');
    expect(t.read('b.txt'), 'unstaged\n');
  });

  test('rewords HEAD, and a detached HEAD', () async {
    t.commit('one', {'a.txt': '1\n'});
    t.commit('two', {'a.txt': '2\n'});
    await t.repo.reword('HEAD', 'Second');
    expect(t.subjects(), ['Second', 'one']);

    t.git(['checkout', '-q', '--detach']);
    await t.repo.reword('HEAD~1', 'First');
    expect(t.subjects(), ['Second', 'First']);
    expect(t.subjects('main'), ['Second', 'one']);
  });

  test('keeps merges after the commit', () async {
    t.commit('base', {'a.txt': '1\n'});
    final target = t.commit('target', {'a.txt': '2\n'});
    t.git(['checkout', '-q', '-b', 'side']);
    t.commit('side', {'s.txt': 's\n'});
    t.git(['checkout', '-q', 'main']);
    t.commit('main', {'m.txt': 'm\n'});
    t.git(['merge', '-q', '--no-ff', '-m', 'merge side', 'side']);
    final tree = fmt('%T', 'HEAD');

    await t.repo.reword(target, 'Target');
    expect(fmt('%s', 'HEAD'), 'merge side');
    expect(fmt('%P', 'HEAD').split(' '), hasLength(2));
    expect(fmt('%T', 'HEAD'), tree);
    // Both sides of the merge now descend from the reworded commit.
    expect(t.subjects('HEAD^2'), ['side', 'Target', 'base']);
    expect(t.subjects('HEAD^1'), ['main', 'Target', 'base']);
  });

  test('refuses commits outside HEAD\'s history', () async {
    t.commit('one', {'a.txt': '1\n'});
    t.git(['checkout', '-q', '-b', 'other']);
    final other = t.commit('other', {'a.txt': '2\n'});
    t.git(['checkout', '-q', 'main']);
    expect(await t.repo.inHeadHistory(other), isFalse);
    expect(await t.repo.inHeadHistory('HEAD'), isTrue);
    await expectLater(t.repo.reword(other, 'x'), throwsA(isA<GitException>()));
    expect(t.subjects('other'), ['other', 'one']);
  });

  test('knows whether the commit is pushed', () async {
    final upstream = await TempRepo.create();
    addTearDown(upstream.dispose);
    upstream.git(['config', 'receive.denyCurrentBranch', 'ignore']);
    final one = t.commit('one', {'a.txt': '1\n'});
    expect(await t.repo.inUpstream(one), isFalse); // no upstream
    t.git(['remote', 'add', 'origin', upstream.path]);
    t.git(['push', '-q', '-u', 'origin', 'main']);
    final two = t.commit('two', {'a.txt': '2\n'});
    expect(await t.repo.inUpstream(one), isTrue);
    expect(await t.repo.inUpstream(two), isFalse);
  });
}
