import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/git/models.dart';
import 'package:gutter/ui/dialogs/cleanup_branches_dialog.dart';
import 'package:gutter/ui/repo/repo_tab_controller.dart';
import 'package:gutter/ui/sidebar/sidebar.dart';

import '../support/temp_repo.dart';

void main() {
  testWidgets('cleans up the chosen merged branches, after two confirmations', (
    tester,
  ) async {
    late TempRepo t;
    late RepoTabController tab;
    await tester.runAsync(() async {
      t = await TempRepo.create();
      t.commit('one', {'a.txt': '1\n'});
      t.git(['branch', 'old-a']);
      t.git(['branch', 'old-b']);
      t.git(['branch', 'keep-me']);
      t.commit('two', {'a.txt': '2\n'});
      t.git(['checkout', '-q', '-b', 'wip']);
      t.commit('wip', {'b.txt': 'b\n'});
      t.git(['checkout', '-q', 'main']);
      tab = RepoTabController(t.repo, AppController(null, Settings()));
      await tab.load();
    });
    addTearDown(() {
      tab.dispose();
      t.dispose();
    });
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
    // Git runs between frames: let real time pass.
    Future<void> settle(bool Function() done) async {
      for (var i = 0; i < 200 && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    bool shows(Finder f) => f.evaluate().isNotEmpty;

    await tester.tap(find.byKey(const ValueKey('cleanup-branches')));
    await settle(() => shows(find.text('Clean up branches')));
    // Merged ones, all checked; not wip (unmerged) nor main (checked out).
    expect(find.text('Merged into main'), findsOneWidget);
    for (final b in ['old-a', 'old-b', 'keep-me']) {
      expect(find.byKey(ValueKey('cleanup-$b')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('cleanup-wip')), findsNothing);
    expect(find.text('Delete 3 branches…'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cleanup-keep-me')));
    await tester.pump();
    expect(find.text('Delete 2 branches…'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cleanup-delete')));
    await tester.pump();

    // The second confirmation lists them.
    expect(find.text('Delete 2 branches?'), findsOneWidget);
    expect(find.textContaining('old-a\nold-b'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete 2 branches'));
    await settle(() => !t.git(['branch', '--list', 'old-a']).contains('old-a'));
    await settle(() => tab.busy == null);
    final left = t
        .git(['for-each-ref', '--format=%(refname:short)', 'refs/heads/'])
        .trim()
        .split('\n');
    expect(left..sort(), ['keep-me', 'main', 'wip']);
  });

  testWidgets('long lists: collapsed sections, select all, filter', (
    tester,
  ) async {
    CleanupBranch b(String n) => CleanupBranch(name: n, date: DateTime(2026));
    final cleanup = BranchCleanup(
      base: 'origin/main',
      merged: [for (var i = 1; i <= 20; i++) b('ticket-$i')],
      gone: [for (var i = 1; i <= 3; i++) b('fix/pr-$i')],
    );
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    List<String>? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  result = await showCleanupBranches(context, cleanup),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();

    // Both sections at a glance, collapsed, with counts.
    expect(find.text('20 of 20'), findsOneWidget);
    expect(find.text('0 of 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('cleanup-ticket-1')), findsNothing);
    expect(find.text('Delete 20 branches…'), findsOneWidget);

    // Select a whole section, clear another.
    await tester.tap(find.byKey(const ValueKey('cleanup-all-gone')));
    await tester.pump();
    expect(find.text('3 of 3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cleanup-all-merged')));
    await tester.pump();
    expect(find.text('0 of 20'), findsOneWidget);
    expect(find.text('Delete 3 branches…'), findsOneWidget);

    // Filtering opens the matching sections; select-all takes what shows.
    await tester.enterText(
      find.byKey(const ValueKey('cleanup-filter')),
      'ticket-1',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('cleanup-ticket-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('cleanup-ticket-19')), findsOneWidget);
    expect(find.byKey(const ValueKey('cleanup-ticket-2')), findsNothing);
    expect(find.byKey(const ValueKey('cleanup-section-gone')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('cleanup-all-merged')));
    await tester.pump();
    expect(find.text('11 of 20'), findsOneWidget); // ticket-1, -10…-19

    await tester.tap(find.byKey(const ValueKey('cleanup-delete')));
    await tester.pump();
    expect(result, [
      'ticket-1',
      for (var i = 10; i <= 19; i++) 'ticket-$i',
      'fix/pr-1',
      'fix/pr-2',
      'fix/pr-3',
    ]);
  });
}
