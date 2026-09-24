import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/git/models.dart';
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
}
