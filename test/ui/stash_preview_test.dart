import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/git/models.dart';
import 'package:gutter/ui/repo/repo_tab_controller.dart';
import 'package:gutter/ui/sidebar/sidebar.dart';

import '../support/temp_repo.dart';

void main() {
  late TempRepo t;
  setUp(() async {
    t = await TempRepo.create();
    t.commit('one', {'a.txt': 'a\n', 'b.txt': 'b\n'});
    t.write('a.txt', 'a changed\n');
    t.write('new.txt', 'brand new\n');
    await t.repo.stashPush(message: 'wip'); // with the untracked file
  });
  tearDown(() => t.dispose());

  test('a stash lists its changes and its untracked files', () async {
    final stash = (await t.repo.stashes()).single;
    final files = await t.repo.stashFiles(stash);
    expect(files.map((f) => (f.path, f.kind, f.source != null)), [
      ('a.txt', ChangeKind.modified, false),
      ('new.txt', ChangeKind.added, true),
    ]);
    // The untracked file diffs against nothing, from the stash's third
    // parent.
    final commit = Commit(
      sha: stash.sha,
      parents: [stash.parents.first],
      authorName: '',
      authorEmail: '',
      authorTime: 0,
      subject: stash.message,
    );
    final diff = await t.repo.commitFileDiff(commit, files[1]);
    expect(diff!.hunks.single.lines.single.text, 'brand new');
    expect(
      utf8.decode((await t.repo.fileContent(files[1].source, 'new.txt'))!),
      'brand new\n',
    );
  });

  testWidgets('clicking a stash in the sidebar shows it', (tester) async {
    late RepoTabController tab;
    await tester.runAsync(() async {
      tab = RepoTabController(t.repo, AppController(null, Settings()));
      await tab.load();
    });
    addTearDown(tab.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: ListenableBuilder(
              listenable: tab,
              builder: (_, _) => Sidebar(tab: tab),
            ),
          ),
        ),
      ),
    );
    final stash = tab.stashes.single;
    await tester.tap(find.text(stash.message));
    // A double click applies it: a single one waits out that timeout.
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 100 && tab.commitFiles.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(tab.selectedSha, stash.sha);
    expect(tab.details!.sha, stash.sha);
    expect(tab.commitFiles.map((f) => f.path), ['a.txt', 'new.txt']);

    // Its untracked file opens like any other.
    await tester.runAsync(() async {
      tab.openCommitFile(tab.detailsCommit!, tab.commitFiles[1]);
      for (var i = 0; i < 100 && tab.diff == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 15));
      }
    });
    expect(tab.diff!.hunks.single.lines.single.text, 'brand new');
  });
}
