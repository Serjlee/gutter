import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/ui/details/details_panel.dart';
import 'package:gutter/ui/repo/repo_tab_controller.dart';

import '../support/temp_repo.dart';

void main() {
  testWidgets('double-clicking a commit message rewords it', (tester) async {
    late TempRepo t;
    late RepoTabController tab;
    await tester.runAsync(() async {
      t = await TempRepo.create();
      t.commit('one', {'a.txt': '1\n'});
      t.commit('two', {'a.txt': '2\n'});
      t.write('a.txt', 'stashed\n');
      await t.repo.stashPush(message: 'later');
      tab = RepoTabController(t.repo, AppController(null, Settings()));
      await tab.load();
      await tab.select(tab.headSha!);
    });
    addTearDown(() {
      tab.dispose();
      t.dispose();
    });
    tester.view.physicalSize = const Size(800, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
    await tester.pump();

    // Waits for git (reword checks the commit first).
    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    final message = find.descendant(
      of: find.byKey(const ValueKey('commit-message')),
      matching: find.text('two'),
    );
    // One click: just selection.
    await tester.tap(message);
    await settle();
    expect(find.textContaining('Reword'), findsNothing);

    // Two: the reword dialog, with the message.
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(message);
    await tester.tap(message);
    await settle();
    expect(find.textContaining('Reword '), findsOneWidget);
    expect(find.widgetWithText(TextField, 'two'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle();

    // A stash's message isn't reworded.
    await tester.runAsync(() => tab.select(tab.stashes.single.sha));
    await tester.pump();
    final stash = find.descendant(
      of: find.byKey(const ValueKey('commit-message')),
      matching: find.textContaining('later'),
    );
    await tester.tap(stash);
    await tester.tap(stash);
    await settle();
    expect(find.textContaining('Reword '), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
