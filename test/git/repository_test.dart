import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/git/git_runner.dart';
import 'package:gutter/git/models.dart';
import 'package:gutter/git/parsers/diff_parser.dart';
import 'package:gutter/git/patch_builder.dart';
import 'package:gutter/git/rebase_plan.dart';
import 'package:gutter/git/repository.dart';
import 'package:path/path.dart' as p;

import '../support/temp_repo.dart';

void main() {
  late TempRepo t;
  late Repository repo;

  setUp(() async {
    t = await TempRepo.create();
    repo = t.repo;
  });
  tearDown(() => t.dispose());

  test('empty repository has no log', () async {
    expect(await repo.log(), isEmpty);
    expect(await repo.headSha(), isNull);
    final s = await repo.status();
    expect(s.branch.head, 'main');
  });

  test('log, refs, status, details, files', () async {
    t.commit('first', {'a.txt': 'a\n'});
    t.git(['checkout', '-q', '-b', 'feature']);
    t.commit('on feature', {'b.txt': 'b\n'});
    t.git(['checkout', '-q', 'main']);
    t.commit('on main', {'a.txt': 'a2\n'});
    t.git(['merge', '-q', '--no-ff', '-m', 'merge feature', 'feature']);
    t.git(['tag', '-a', 'v1', '-m', 'release']);
    t.write('a.txt', 'dirty\n');
    t.write('new file.txt', 'x');

    final log = await repo.log();
    expect(log.map((c) => c.subject), [
      'merge feature',
      'on main',
      'on feature',
      'first',
    ]);
    expect(log.first.isMerge, isTrue);

    final refs = await repo.refs();
    final tag = refs.firstWhere((r) => r.fullName == 'refs/tags/v1');
    expect(tag.sha, log.first.sha);
    expect(refs.firstWhere((r) => r.name == 'main').isHead, isTrue);

    final status = await repo.status();
    expect(status.unstaged.map((e) => e.path).toSet(), {
      'a.txt',
      'new file.txt',
    });

    final details = await repo.commitDetails(log[1].sha);
    expect(details.subject, 'on main');
    final files = await repo.commitFiles(log[2]);
    expect(files.single.path, 'b.txt');
    expect(files.single.kind, ChangeKind.added);
    final root = await repo.commitFiles(log.last);
    expect(root.single.path, 'a.txt');
    final diff = await repo.commitFileDiff(
      log[1],
      FileChange(path: 'a.txt', kind: ChangeKind.modified),
    );
    expect(diff!.additions, 1);
    expect(diff.deletions, 1);
    final content = await repo.fileContent(log.last.sha, 'a.txt');
    expect(String.fromCharCodes(content!), 'a\n');
    expect(await repo.operation(), RepoOperation.none);
  });

  group('partial staging', () {
    const original = 'l1\nl2\nl3\nl4\nl5\nl6\nl7\nl8\nl9\nl10\nl11\nl12\n';
    const modified = 'l1\nL2\nl3\nl4\nl5\nl6\nl7\nl8\nl9\nl10\nNEW\nl11\nl12\n';

    Future<FileDiff> unstagedDiff(String path) async {
      final s = await repo.status();
      return (await repo.workingDiff(
        s.entries.firstWhere((e) => e.path == path),
        staged: false,
      ))!;
    }

    Future<FileDiff> stagedDiff(String path) async {
      final s = await repo.status();
      return (await repo.workingDiff(
        s.entries.firstWhere((e) => e.path == path),
        staged: true,
      ))!;
    }

    test('stage a single hunk', () async {
      t.commit('init', {'f.txt': original});
      t.write('f.txt', modified);
      final d = await unstagedDiff('f.txt');
      expect(d.hunks, hasLength(2));
      await repo.applyPatch(PatchBuilder.hunk(d, 1)!);
      final cached = t.git(['diff', '--cached']);
      expect(cached, contains('+NEW'));
      expect(cached, isNot(contains('+L2')));
      expect(t.git(['diff']), contains('+L2'));
    });

    test('stage selected lines then unstage one line', () async {
      t.commit('init', {'f.txt': original});
      t.write('f.txt', modified);
      final d = await unstagedDiff('f.txt');
      final hunk = d.hunks[0];
      // Select only the "+L2" line (not the "-l2").
      final addIdx = hunk.lines.indexWhere((l) => l.text == 'L2');
      await repo.applyPatch(
        PatchBuilder.build(
          d,
          selection: {
            0: {addIdx},
          },
        )!,
      );
      final cachedContent = t.git(['show', ':f.txt']);
      expect(cachedContent, startsWith('l1\nl2\nL2\nl3\n'));

      // Stage everything else, then unstage just the NEW line.
      t.git(['add', 'f.txt']);
      final sd = await stagedDiff('f.txt');
      final h = sd.hunks.indexWhere((h) => h.lines.any((l) => l.text == 'NEW'));
      final li = sd.hunks[h].lines.indexWhere((l) => l.text == 'NEW');
      final patch = PatchBuilder.build(
        sd,
        selection: {
          h: {li},
        },
        reverse: true,
      )!;
      await repo.applyPatch(patch, reverse: true);
      final idx = t.git(['show', ':f.txt']);
      expect(idx, isNot(contains('NEW')));
      expect(idx, contains('L2'));
      expect(t.read('f.txt'), modified, reason: 'worktree untouched');
    });

    test('discard a hunk from the worktree', () async {
      t.commit('init', {'f.txt': original});
      t.write('f.txt', modified);
      final d = await unstagedDiff('f.txt');
      await repo.applyPatch(
        PatchBuilder.hunk(d, 0, reverse: true)!,
        cached: false,
        reverse: true,
      );
      expect(t.read('f.txt'), original.replaceFirst('l11', 'NEW\nl11'));
    });

    test('stage part of an untracked file via intent-to-add', () async {
      t.commit('init', {'other.txt': 'x\n'});
      t.write('n.txt', 'keep\ndrop\n');
      await repo.intentToAdd('n.txt');
      final d = await unstagedDiff('n.txt');
      final li = d.hunks[0].lines.indexWhere((l) => l.text == 'keep');
      await repo.applyPatch(
        PatchBuilder.build(
          d,
          selection: {
            0: {li},
          },
        )!,
      );
      expect(t.git(['show', ':n.txt']), 'keep\n');
    });

    test('file stage / unstage / discard', () async {
      t.commit('init', {'a.txt': 'a\n'});
      t.write('a.txt', 'b\n');
      t.write('u.txt', 'u\n');
      await repo.stage(['a.txt', 'u.txt']);
      expect((await repo.status()).staged, hasLength(2));
      await repo.unstage(['a.txt']);
      var s = await repo.status();
      expect(s.staged.single.path, 'u.txt');
      await repo.unstageAll();
      s = await repo.status();
      await repo.discard(s.entries);
      expect((await repo.status()).isClean, isTrue);
      expect(t.read('a.txt'), 'a\n');
    });
  });

  test('writes a commit-graph once', () async {
    t.commit('one', {'a.txt': 'a\n'});
    expect(await repo.ensureCommitGraph(), isTrue);
    expect(await repo.ensureCommitGraph(), isFalse);
    expect(await repo.log(), hasLength(1));
  });

  test('commit and amend', () async {
    t.commit('init', {'a.txt': 'a\n'});
    t.write('a.txt', 'b\n');
    await repo.stageAll();
    await repo.commit('second\n\nbody text');
    expect(t.subjects().first, 'second');
    expect(await repo.lastCommitMessage(), 'second\n\nbody text');
    await repo.commit('second amended', amend: true);
    expect(t.subjects(), ['second amended', 'init']);
  });

  group('interactive rebase', () {
    late List<RebaseStep> steps;
    late String base;

    setUp(() async {
      base = t.commit('base', {'base.txt': '0\n'});
      t.commit('one', {'1.txt': '1\n'});
      t.commit('two', {'2.txt': '2\n'});
      t.commit('three', {'3.txt': '3\n'});
      t.commit('four', {'4.txt': '4\n'});
      steps = await repo.rebaseCandidates(base);
      expect(steps.map((s) => s.subject), ['one', 'two', 'three', 'four']);
    });

    test('reorder, drop, reword', () async {
      final one = steps[0], two = steps[1], three = steps[2], four = steps[3];
      two.action = RebaseAction.drop;
      four.action = RebaseAction.reword;
      four.newMessage = 'four reworded\n\nwith body';
      await repo.rebaseInteractive(base, RebasePlan([three, one, two, four]));
      expect(t.subjects(), ['four reworded', 'one', 'three', 'base']);
      expect(File(p.join(t.path, '2.txt')).existsSync(), isFalse);
      expect(await repo.operation(), RepoOperation.none);
      await repo.cleanupRebaseFiles();
    });

    test('squash and fixup', () async {
      steps[1].action = RebaseAction.squash;
      steps[2].action = RebaseAction.fixup;
      final plan = RebasePlan(steps);
      final group = plan.groups().first;
      steps[0].newMessage = group.defaultMessage();
      expect(steps[0].newMessage, 'one\n\ntwo');
      await repo.rebaseInteractive(base, plan);
      expect(t.subjects(), ['four', 'one', 'base']);
      final msg = t.git(['log', '-1', '--format=%B', 'HEAD~1']).trim();
      expect(msg, 'one\n\ntwo');
      final files = t.git(['show', '--name-only', '--format=', 'HEAD~1']);
      expect(files.trim().split('\n').toSet(), {'1.txt', '2.txt', '3.txt'});
    });

    test('edit stops, continue finishes', () async {
      steps[1].action = RebaseAction.edit;
      await repo.rebaseInteractive(base, RebasePlan(steps));
      expect(await repo.operation(), RepoOperation.rebase);
      expect(await repo.rebaseProgress(), isNotNull);
      await repo.continueOperation(RepoOperation.rebase);
      expect(await repo.operation(), RepoOperation.none);
      expect(t.subjects(), ['four', 'three', 'two', 'one', 'base']);
    });

    test('first commit cannot be squashed', () {
      steps[0].action = RebaseAction.squash;
      expect(
        () => RebasePlan(steps).validate(),
        throwsA(isA<RebasePlanError>()),
      );
    });

    test('rebase from root', () async {
      final all = await repo.rebaseCandidates(null);
      expect(all, hasLength(5));
      all[1].action = RebaseAction.fixup;
      await repo.rebaseInteractive(null, RebasePlan(all));
      expect(t.subjects(), ['four', 'three', 'two', 'base']);
    });
  });

  test('merge conflict then abort / resolve and continue', () async {
    t.commit('init', {'c.txt': 'base\n'});
    t.git(['checkout', '-q', '-b', 'other']);
    t.commit('other change', {'c.txt': 'theirs\n'});
    t.git(['checkout', '-q', 'main']);
    t.commit('main change', {'c.txt': 'ours\n'});

    await expectLater(repo.merge('other'), throwsA(isA<GitException>()));
    expect(await repo.operation(), RepoOperation.merge);
    expect((await repo.status()).conflicted.single.path, 'c.txt');
    await repo.abortOperation(RepoOperation.merge);
    expect(await repo.operation(), RepoOperation.none);

    await expectLater(repo.merge('other'), throwsA(isA<GitException>()));
    await repo.resolveWith('c.txt', ours: false);
    await repo.continueOperation(RepoOperation.merge);
    expect(await repo.operation(), RepoOperation.none);
    expect(t.read('c.txt'), 'theirs\n');
    expect(t.subjects().first, startsWith('Merge branch'));
  });

  test('rebase conflict: skip and continue', () async {
    t.commit('init', {'c.txt': 'base\n'});
    t.git(['checkout', '-q', '-b', 'topic']);
    t.commit('topic conflicting', {'c.txt': 'topic\n'});
    t.commit('topic clean', {'d.txt': 'd\n'});
    t.git(['checkout', '-q', 'main']);
    t.commit('main change', {'c.txt': 'main\n'});
    t.git(['checkout', '-q', 'topic']);

    await expectLater(repo.rebase('main'), throwsA(isA<GitException>()));
    expect(await repo.operation(), RepoOperation.rebase);
    await repo.skipOperation(RepoOperation.rebase);
    expect(await repo.operation(), RepoOperation.none);
    expect(t.subjects(), ['topic clean', 'main change', 'init']);
  });

  test('cherry-pick, revert, reset', () async {
    t.commit('init', {'a.txt': 'a\n'});
    t.git(['checkout', '-q', '-b', 'side']);
    t.commit('side', {'s.txt': 's\n'});
    t.git(['checkout', '-q', 'main']);
    final log = await repo.log();
    await repo.cherryPick(log.firstWhere((c) => c.subject == 'side'));
    expect(t.subjects().first, 'side');
    final head = (await repo.log()).first;
    await repo.revert(head);
    expect(t.subjects().first, startsWith('Revert'));
    await repo.reset(
      log.firstWhere((c) => c.subject == 'init').sha,
      ResetMode.hard,
    );
    expect(t.subjects(), ['init']);
  });

  test('branches and tags', () async {
    final sha = t.commit('init', {'a.txt': 'a\n'});
    await repo.createBranch('feat', checkout: false);
    await repo.createBranch('feat2', startPoint: sha);
    expect((await repo.status()).branch.head, 'feat2');
    await repo.renameBranch('feat', 'feature');
    await repo.checkout('main');
    await repo.deleteBranch('feat2');
    await repo.createTag('v1', sha, message: 'annotated');
    await repo.createTag('light', sha);
    var refs = await repo.refs();
    expect(refs.map((r) => r.name).toSet(), {'main', 'feature', 'v1', 'light'});
    await repo.deleteTag('light');
    refs = await repo.refs();
    expect(refs.any((r) => r.name == 'light'), isFalse);
  });

  test('stash round trip', () async {
    t.commit('init', {'a.txt': 'a\n'});
    t.write('a.txt', 'changed\n');
    t.write('u.txt', 'untracked\n');
    await repo.stashPush(message: 'wip stuff');
    expect((await repo.status()).isClean, isTrue);
    final stashes = await repo.stashes();
    expect(stashes.single.message, contains('wip stuff'));
    await repo.stashApply(0);
    expect(t.read('u.txt'), 'untracked\n');
    await repo.discard((await repo.status()).entries);
    await repo.stashPop(0);
    expect(t.read('a.txt'), 'changed\n');
    expect(await repo.stashes(), isEmpty);
  });

  test('checking out a remote branch fast-forwards the local one', () async {
    final a = t.commit('a', {'a.txt': 'a\n'});
    final b = t.commit('b', {'a.txt': 'b\n'});
    t.git(['checkout', '-q', '-b', 'side', a]);
    final c = t.commit('c', {'c.txt': 'c\n'});
    t.git(['checkout', '-q', 'main']);
    // Local branches: behind (at a), ahead (at b), diverged (side, at c),
    // up to date (at b). Remote-tracking refs as a fetch would leave them.
    t.git(['branch', 'behind', a]);
    t.git(['branch', 'ahead', b]);
    t.git(['branch', 'same', b]);
    t.git(['remote', 'add', 'origin', '/nonexistent/origin.git']);
    t.git(['update-ref', 'refs/remotes/origin/behind', b]);
    t.git(['update-ref', 'refs/remotes/origin/ahead', a]);
    t.git(['update-ref', 'refs/remotes/origin/side', b]);
    t.git(['update-ref', 'refs/remotes/origin/same', b]);
    t.git(['update-ref', 'refs/remotes/origin/fresh', a]);

    Future<RemoteCheckout> go(String name) async {
      final refs = await repo.refs();
      final remote = refs.firstWhere((r) => r.name == 'origin/$name');
      return repo.checkoutRemote(remote, refs);
    }

    String head() => t.git(['rev-parse', 'HEAD']).trim();
    String branch() => t.git(['branch', '--show-current']).trim();

    expect(await go('behind'), RemoteCheckout.fastForwarded);
    expect((branch(), head()), ('behind', b));

    expect(await go('ahead'), RemoteCheckout.ahead);
    expect((branch(), head()), ('ahead', b));

    expect(await go('side'), RemoteCheckout.diverged);
    expect((branch(), head()), ('side', c)); // local commits kept

    expect(await go('same'), RemoteCheckout.upToDate);
    expect((branch(), head()), ('same', b));

    expect(await go('fresh'), RemoteCheckout.created);
    expect((branch(), head()), ('fresh', a));
  });

  test('remotes: fetch, checkout remote branch, push, pull', () async {
    t.commit('init', {'a.txt': 'a\n'});
    final remoteDir = await Directory.systemTemp.createTemp('gutter_remote_');
    addTearDown(() => remoteDir.deleteSync(recursive: true));
    Process.runSync('git', ['init', '-q', '--bare', remoteDir.path]);
    t.git(['remote', 'add', 'origin', remoteDir.path]);
    await repo.push(branch: 'main', setUpstream: true);

    // Second clone pushes a new branch.
    final other = await Directory.systemTemp.createTemp('gutter_clone_');
    addTearDown(() => other.deleteSync(recursive: true));
    final clonePath = p.join(other.path, 'c');
    await Repository.clone(remoteDir.path, clonePath);
    Process.runSync('git', [
      '-C',
      clonePath,
      'checkout',
      '-q',
      '-b',
      'remote-feature',
    ]);
    File(p.join(clonePath, 'r.txt')).writeAsStringSync('r\n');
    Process.runSync('git', ['-C', clonePath, 'add', '.']);
    Process.runSync('git', [
      '-C',
      clonePath,
      '-c',
      'user.name=x',
      '-c',
      'user.email=x@x',
      'commit',
      '-q',
      '-m',
      'remote commit',
    ]);
    Process.runSync('git', [
      '-C',
      clonePath,
      'push',
      '-q',
      'origin',
      'remote-feature',
    ]);

    await repo.fetch();
    final refs = await repo.refs();
    final remoteRef = refs.firstWhere((r) => r.name == 'origin/remote-feature');
    await repo.checkoutRemote(remoteRef, refs);
    final s = await repo.status();
    expect(s.branch.head, 'remote-feature');
    expect(s.branch.upstream, 'origin/remote-feature');

    // Upstream moves; pull fast-forwards.
    File(p.join(clonePath, 'r.txt')).writeAsStringSync('r2\n');
    Process.runSync('git', [
      '-C',
      clonePath,
      '-c',
      'user.name=x',
      '-c',
      'user.email=x@x',
      'commit',
      '-qam',
      'remote 2',
    ]);
    Process.runSync('git', [
      '-C',
      clonePath,
      'push',
      '-q',
      'origin',
      'remote-feature',
    ]);
    await repo.pull(PullMode.ffOnly);
    expect(t.subjects().first, 'remote 2');
    expect((await repo.remotes()).single.name, 'origin');
  });
}
