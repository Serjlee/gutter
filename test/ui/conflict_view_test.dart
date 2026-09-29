import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/ui/diff/conflict_view.dart';
import 'package:gutter/ui/repo/repo_tab_controller.dart';

import '../support/temp_repo.dart';

void main() {
  testWidgets('resolves conflicts block by block, then the file', (
    tester,
  ) async {
    late TempRepo t;
    late RepoTabController tab;
    await tester.runAsync(() async {
      t = await TempRepo.create();
      t.commit('init', {'a.txt': 'top\none\na\nb\nc\nd\ntwo\n'});
      t.git(['checkout', '-q', '-b', 'feature']);
      t.commit('theirs', {'a.txt': 'top\nONE\na\nb\nc\nd\nTWO\n'});
      t.git(['checkout', '-q', 'main']);
      t.commit('mine', {'a.txt': 'top\n1\na\nb\nc\nd\n2\n'});
      tab = RepoTabController(t.repo, AppController(null, Settings()));
      await tab.load();
      await tab.run('Merge', () => tab.repo.merge('feature'));
    });
    addTearDown(() {
      tab.dispose();
      t.dispose();
    });
    final entry = tab.status.conflicted.single;
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: tab,
            builder: (_, _) => ConflictView(tab: tab, entry: entry),
          ),
        ),
      ),
    );
    // Real file I/O happens between frames: pump until [finder] shows.
    Future<void> pumpUntil(Finder finder) async {
      for (var i = 0; i < 200 && finder.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)),
        );
        await tester.pump();
      }
    }

    await pumpUntil(find.text('Conflict 1 of 2'));
    // Both conflicts, sides named after the branches.
    expect(find.text('Conflict 1 of 2'), findsOneWidget);
    expect(find.text('Use main'), findsNWidgets(2));
    expect(find.text('Use feature'), findsNWidgets(2));
    expect(find.text('Take feature'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('conflict-0-incoming')));
    await pumpUntil(find.text('Conflict 1 of 1'));
    expect(find.text('Conflict 1 of 1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('conflict-0-both')));
    await pumpUntil(find.byKey(const ValueKey('conflict-mark-resolved')));
    expect(t.read('a.txt'), 'top\nONE\na\nb\nc\nd\n2\nTWO\n');

    // No conflicts left: the file can be marked resolved. (Run under the
    // real clock: git processes don't finish inside the test's fake one.)
    expect(
      find.byKey(const ValueKey('conflict-mark-resolved')),
      findsOneWidget,
    );
    final context = tester.element(find.byType(ConflictView));
    await tester.runAsync(() => markConflictResolved(context, tab, 'a.txt'));
    expect(tab.status.conflicted, isEmpty);
    expect(tab.status.staged.single.path, 'a.txt');
  });
}
