import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/git/models.dart';
import 'package:gutter/graph/graph_layout.dart';
import 'package:gutter/ui/repo/auto_fetch.dart';
import 'package:gutter/ui/repo/repo_tab_controller.dart';

import '../support/temp_repo.dart';

void main() {
  group('auto-fetch policy', () {
    final now = DateTime(2026, 1, 1, 12);
    bool due({
      DateTime? last,
      int interval = 5,
      bool active = true,
      bool focused = true,
      bool remotes = true,
      bool fetching = false,
    }) => isAutoFetchDue(
      now: now,
      lastFetch: last,
      intervalMinutes: interval,
      active: active,
      focused: focused,
      hasRemotes: remotes,
      fetching: fetching,
    );

    test('fetches when never fetched or the interval elapsed', () {
      expect(due(), isTrue);
      expect(due(last: now.subtract(const Duration(minutes: 5))), isTrue);
      expect(due(last: now.subtract(const Duration(minutes: 4))), isFalse);
    });

    test('only the active tab fetches; others catch up on activation', () {
      final stale = now.subtract(const Duration(minutes: 30));
      expect(due(last: stale, active: false), isFalse);
      expect(due(last: stale, active: true), isTrue);
    });

    test('never while unfocused, disabled, without remotes or busy', () {
      expect(due(focused: false), isFalse);
      expect(due(interval: 0), isFalse);
      expect(due(remotes: false), isFalse);
      expect(due(fetching: true), isFalse);
    });
  });

  group('RepoTabController', () {
    late TempRepo t;
    late AppController app;
    late RepoTabController tab;

    setUp(() async {
      t = await TempRepo.create();
      t.commit('one', {'a.txt': 'a\n'});
      t.git(['checkout', '-q', '-b', 'side']);
      t.commit('side work', {'s.txt': 's\n'});
      t.git(['checkout', '-q', 'main']);
      t.commit('two', {'a.txt': 'a\nb\n'});
      app = AppController(null, Settings());
      tab = RepoTabController(t.repo, app);
    });

    tearDown(() {
      tab.dispose();
      t.dispose();
    });

    test('loads graph, refs and a WIP row when dirty', () async {
      await tab.load();
      expect(tab.loadError, isNull);
      expect(tab.graph.hasWip, isFalse);
      expect(tab.graph.commits.map((c) => c.subject), [
        'two',
        'side work',
        'one',
      ]);
      expect(tab.graph.layout.maxLanes, 2);
      expect(tab.currentBranch, 'main');
      expect(tab.refsBySha[tab.headSha]!.map((r) => r.name), contains('main'));

      t.write('a.txt', 'a\nB\nc\n');
      await tab.refresh();
      expect(tab.graph.hasWip, isTrue);
      expect(tab.graph.commitAt(0), isNull);
      expect(tab.graph.rowOf(tab.headSha!), 1);
      expect(tab.status.unstaged.single.path, 'a.txt');
    });

    test('stashes appear in the graph and go away when dropped', () async {
      await tab.load();
      t.write('a.txt', 'a\nb\nstashed\n');
      await tab.repo.stashPush(message: 'try this');
      await tab.refresh();
      expect(tab.graph.hasWip, isFalse);
      expect(tab.graph.commits.first.subject, contains('try this'));
      final stash = tab.graph.stashAt(0)!;
      expect(stash.ref, 'stash@{0}');
      // Linked to HEAD with a dashed line.
      expect(tab.graph.commits.first.parents, [tab.headSha]);
      final dashed = tab.graph.layout
          .edgesAt(0)
          .where((e) => e[2] & GraphLayout.dashedBit != 0);
      expect(dashed, isNotEmpty);
      // Selecting it shows the stashed change.
      await tab.select(stash.sha);
      expect(tab.commitFiles.single.path, 'a.txt');

      await tab.repo.stashDrop(0);
      await tab.refresh();
      expect(tab.graph.stashes, isEmpty);
      expect(tab.graph.rowCount, 3);
    });

    test('selects commits and stages selected lines from the diff', () async {
      await tab.load();
      final side = tab.graph.commits.firstWhere(
        (c) => c.subject == 'side work',
      );
      await tab.select(side.sha);
      expect(tab.details!.subject, 'side work');
      expect(tab.commitFiles.single.path, 's.txt');

      t.write('a.txt', 'a\nB\nc\n');
      await tab.refresh();
      final entry = tab.status.unstaged.single;
      tab.openWorkingFile(entry, staged: false);
      while (tab.diffLoading || tab.diff == null) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final hunk = tab.diff!.hunks.single;
      final addC = hunk.lines.indexWhere((l) => l.text == 'c');
      await tab.applySelection({
        0: {addC},
      });
      expect(t.git(['show', ':a.txt']), 'a\nb\nc\n');

      // Commit what is staged.
      tab.commitMessage.text = 'add c';
      expect(await tab.commit(), isTrue);
      expect(t.subjects().first, 'add c');
      expect(tab.commitMessage.text, isEmpty);
    });

    test('search finds rows by message, author and sha prefix', () async {
      await tab.load();
      tab.setSearch('side');
      expect(tab.searchHits, [1]);
      tab.setSearch(tab.graph.commits.last.sha.substring(0, 8));
      expect(tab.searchHits, [2]);
      tab.setSearch('Test User');
      expect(tab.searchHits, hasLength(3));
    });

    test('background tabs do not fetch until activated', () async {
      final remote = await Directory.systemTemp.createTemp('gutter_remote_');
      addTearDown(() => remote.deleteSync(recursive: true));
      Process.runSync('git', ['init', '-q', '--bare', remote.path]);
      t.git(['remote', 'add', 'origin', remote.path]);
      t.git(['push', '-q', 'origin', 'main']);

      await tab.load(); // never activated: a background tab
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(tab.remotes, isNotEmpty);
      expect(tab.lastFetch, isNull);

      tab.setActive(true);
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (tab.lastFetch == null && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(tab.lastFetch, isNotNull);
      expect(tab.fetchError, isNull);
    });

    test('errors are reported, not thrown', () async {
      await tab.load();
      final messages = <AppMessage>[];
      final sub = app.messages.listen(messages.add);
      final ok = await tab.run('Checkout', () => tab.repo.checkout('nope'));
      await Future<void>.delayed(Duration.zero);
      expect(ok, isFalse);
      expect(messages.single.error, isTrue);
      await sub.cancel();
      expect(tab.busy, isNull);
      expect(tab.operation, RepoOperation.none);
    });
  });

  group('stashes in the graph', () {
    Commit c(String sha, int time, [List<String> parents = const []]) => Commit(
      sha: sha,
      parents: parents,
      authorName: 'a',
      authorEmail: 'a@a',
      authorTime: time,
      subject: sha,
    );
    StashEntry s(int index, String sha, int time, String base) => StashEntry(
      index: index,
      sha: sha,
      message: 'On main: $sha',
      time: time,
      parents: [base, 'index-$sha'],
    );

    final history = [
      c('d', 400, ['c']),
      c('c', 300, ['b']),
      c('b', 200, ['a']),
      c('a', 100),
    ];

    test('placed by date, linked only to the base commit', () {
      final rows = mergeStashes(history, [s(0, 's0', 250, 'b')]);
      expect(rows.map((r) => r.sha), ['d', 'c', 's0', 'b', 'a']);
      expect(rows[2].parents, ['b']);
      expect(rows[2].subject, 'On main: s0');
    });

    test('never below its base, even when older', () {
      // Clock skew: the stash claims to be older than its base.
      final rows = mergeStashes(history, [s(0, 's0', 50, 'c')]);
      expect(rows.map((r) => r.sha), ['d', 's0', 'c', 'b', 'a']);
    });

    test('newer stashes first at the same spot; unloaded bases at the end', () {
      final rows = mergeStashes(history, [
        s(0, 's0', 500, 'd'),
        s(1, 's1', 500, 'd'),
        s(2, 's2', 10, 'zzz'),
      ]);
      expect(rows.map((r) => r.sha), ['s0', 's1', 'd', 'c', 'b', 'a', 's2']);
    });

    test('graph data maps rows to stashes and keeps the history', () {
      final g = layoutGraph(
        history,
        wipParent: 'd',
        stashes: [s(0, 's0', 250, 'b')],
      );
      expect(g.rowCount, 6);
      expect(g.history, history);
      expect(g.commitAt(0), isNull); // WIP
      expect(g.rowOf('s0'), 3);
      expect(g.stashAt(3)?.ref, 'stash@{0}');
      expect(g.stashAt(2), isNull);
      expect(g.rowOf('b'), 4);
    });
  });
}
