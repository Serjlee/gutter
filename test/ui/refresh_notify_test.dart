import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/ui/repo/repo_tab_controller.dart';

import '../support/temp_repo.dart';

void main() {
  late TempRepo t;
  late RepoTabController tab;
  var notified = 0;

  setUp(() async {
    t = await TempRepo.create();
    t.commit('one', {'a.txt': 'one\n', 'b.txt': 'b\n'});
    t.commit('two', {'a.txt': 'one\ntwo\n'});
    tab = RepoTabController(t.repo, AppController(null, Settings()));
    await tab.load();
    notified = 0;
    tab.addListener(() => notified++);
  });
  tearDown(() {
    tab.dispose();
    t.dispose();
  });

  /// Whether a refresh now has something to show.
  Future<bool> refreshNotifies() async {
    final before = notified;
    await tab.refresh();
    // Anything a refresh starts in the background (a diff, a selection).
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return notified > before;
  }

  test('a refresh with nothing new notifies nobody', () async {
    // The first refresh may settle the selection of the checked-out commit.
    await refreshNotifies();
    for (var i = 0; i < 3; i++) {
      expect(await refreshNotifies(), isFalse);
    }
  });

  test('changes to the repository are shown', () async {
    await refreshNotifies();

    t.write('a.txt', 'one\ntwo\nthree\n'); // a modified file
    expect(await refreshNotifies(), isTrue);
    expect(tab.status.unstaged.map((e) => e.path), ['a.txt']);
    expect(await refreshNotifies(), isFalse);

    t.git(['add', 'a.txt']); // staged
    expect(await refreshNotifies(), isTrue);
    expect(tab.status.staged.map((e) => e.path), ['a.txt']);

    t.write('new.txt', 'x\n'); // untracked
    expect(await refreshNotifies(), isTrue);

    t.git(['stash', 'push', '-q', '-u']); // a stash
    expect(await refreshNotifies(), isTrue);
    expect(tab.stashes, hasLength(1));
    expect(await refreshNotifies(), isFalse);

    t.git(['branch', 'topic']); // a branch
    expect(await refreshNotifies(), isTrue);
    expect(tab.refs.any((r) => r.fullName == 'refs/heads/topic'), isTrue);

    t.git(['tag', 'v1']); // a tag
    expect(await refreshNotifies(), isTrue);

    t.commit('three', {'c.txt': 'c\n'}); // a commit
    expect(await refreshNotifies(), isTrue);
    expect(tab.graph.commits.first.subject, 'three');
    expect(await refreshNotifies(), isFalse);
  });

  test('the "last fetch" tooltip is kept current', () async {
    await refreshNotifies();
    tab.lastFetch = DateTime.now();
    expect(await refreshNotifies(), isTrue); // from none to "just now"
    expect(await refreshNotifies(), isFalse);

    tab.lastFetch = DateTime.now().subtract(const Duration(minutes: 5));
    expect(await refreshNotifies(), isTrue); // "5 min ago"
    expect(await refreshNotifies(), isFalse);
  });

  test('an open diff updates only when its content does', () async {
    t.write('a.txt', 'one\ntwo\nthree\n');
    await tab.refresh();
    tab.openWorkingFile(tab.status.unstaged.single, staged: false);
    for (var i = 0; i < 100 && tab.diff == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(tab.diff, isNotNull);
    await refreshNotifies();

    final diff = tab.diff;
    expect(await refreshNotifies(), isFalse);
    expect(identical(tab.diff, diff), isTrue);

    // Same status (still modified), different lines.
    t.write('a.txt', 'one\ntwo\nthree\nfour\n');
    expect(await refreshNotifies(), isTrue);
    expect(identical(tab.diff, diff), isFalse);
    expect(
      tab.diff!.hunks.single.lines.where((l) => l.text == 'four'),
      hasLength(1),
    );
    expect(await refreshNotifies(), isFalse);

    // The file goes back to how it was: the diff closes.
    t.git(['checkout', '--', 'a.txt']);
    expect(await refreshNotifies(), isTrue);
    expect(tab.diffTarget, isNull);
  });
}
