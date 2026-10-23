import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/ui/details/details_panel.dart';
import 'package:gutter/ui/repo/repo_tab_controller.dart';

import '../support/temp_repo.dart';

void main() {
  testWidgets('the details show how long ago, and when committed apart', (
    tester,
  ) async {
    late TempRepo t;
    late RepoTabController tab;
    final now = DateTime.now();
    await tester.runAsync(() async {
      t = await TempRepo.create();
      t.commit('one', {'a.txt': '1\n'}, now.subtract(const Duration(days: 5)));
      // Committed two hours ago, as authored three days ago (as a rebase
      // keeps it).
      t.commit('two', {'a.txt': '2\n'}, now.subtract(const Duration(hours: 2)));
      final authored = now.subtract(const Duration(days: 3));
      t.git([
        'commit',
        '--amend',
        '--no-edit',
        '--date=${authored.millisecondsSinceEpoch ~/ 1000} +0000',
      ]);
      tab = RepoTabController(t.repo, AppController(null, Settings()));
      await tab.load();
    });
    addTearDown(() {
      tab.dispose();
      t.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: tab,
            builder: (_, _) => DetailsPanel(tab: tab),
          ),
        ),
      ),
    );
    String text(String key) =>
        tester.widget<Text>(find.byKey(ValueKey(key))).data!;

    await tester.runAsync(() => tab.select(tab.headSha!));
    await tester.pump();
    expect(text('details-authored'), endsWith('(3d ago)'));
    expect(text('details-committed'), endsWith('(2h ago)'));

    final one = tab.graph.history.last.sha;
    await tester.runAsync(() => tab.select(one));
    await tester.pump();
    expect(text('details-authored'), endsWith('(5d ago)'));
    expect(find.byKey(const ValueKey('details-committed')), findsNothing);
  });
}
