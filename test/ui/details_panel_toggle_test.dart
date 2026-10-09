import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/ui/details/details_panel.dart';
import 'package:gutter/ui/repo/repo_tab_controller.dart';
import 'package:gutter/ui/repo/repo_view.dart';

import '../support/temp_repo.dart';

void main() {
  testWidgets('the details panel closes, and opens again on a click', (
    tester,
  ) async {
    late TempRepo t;
    late RepoTabController tab;
    await tester.runAsync(() async {
      t = await TempRepo.create();
      t.commit('one', {'a.txt': '1\n'});
      t.commit('two', {'a.txt': '2\n'});
      t.write('a.txt', 'stashed\n');
      await t.repo.stashPush(message: 'later');
      t.write('a.txt', 'dirty\n');
      tab = RepoTabController(t.repo, AppController(null, Settings()));
      await tab.load();
    });
    addTearDown(() {
      tab.dispose();
      t.dispose();
    });
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: RepoView(tab: tab)),
      ),
    );
    await tester.pump();

    // Waits for git (the selected commit's details) to finish.
    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    final panel = find.byType(DetailsPanel);
    // A commit's row in the graph.
    Finder row(String message) => find.text(message).hitTestable().first;
    expect(panel, findsOneWidget);

    // The status bar's button, then a click on a commit.
    await tester.tap(find.byKey(const ValueKey('toggle-details')));
    await tester.pump();
    expect(panel, findsNothing);
    await tester.tap(row('one'));
    await settle();
    expect(panel, findsOneWidget);
    expect(tab.details?.subject, 'one');

    // Esc, then clicking a commit again.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(panel, findsNothing);

    // Arrow keys move through the graph without opening it.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await settle();
    expect(tab.details?.subject, 'two');
    expect(panel, findsNothing);
    await tester.tap(row('one'));
    await settle();
    expect(panel, findsOneWidget);

    // With a file open, Esc closes the file first, then the panel.
    tab.openCommitFile(tab.detailsCommit!, tab.commitFiles.single);
    await settle();
    expect(tab.diffTarget, isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(tab.diffTarget, isNull);
    expect(panel, findsOneWidget);
    // The graph has the keys again.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await settle();
    expect(tab.details?.subject, 'two');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(panel, findsNothing);

    // A stash in the sidebar opens it.
    await tester.tap(find.text('On main: later').first);
    await tester.pump(const Duration(milliseconds: 400)); // not a double click
    await settle();
    expect(panel, findsOneWidget);

    // The mouse's back button closes it too.
    final back = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kBackMouseButton,
    );
    await back.down(tester.getCenter(row('two')));
    await back.up();
    await tester.pump();
    expect(panel, findsNothing);

    // Esc while typing the commit message leaves it open.
    await tester.tap(find.textContaining('WIP').hitTestable().first);
    await settle();
    expect(panel, findsOneWidget);
    await tester.tap(find.byType(TextField).last);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(panel, findsOneWidget);

    // The toolbar toggle and its shortcut.
    await tester.tap(find.byKey(const ValueKey('toggle-details')));
    await tester.pump();
    expect(panel, findsNothing);
    await tester.tap(find.byKey(const ValueKey('toggle-details')));
    await tester.pump();
    expect(panel, findsOneWidget);
    tab.toggleDetails();
    await tester.pump();
    expect(panel, findsNothing);

    // Let the views' timers (tooltips, scrollbars) run out.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
