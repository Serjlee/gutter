import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/git/rebase_plan.dart';
import 'package:gutter/ui/dialogs/interactive_rebase_dialog.dart';
import 'package:gutter/ui/shell/app_shell.dart';
import 'package:gutter/ui/widgets/common.dart';

import '../support/temp_repo.dart';

void main() {
  testWidgets('the rebase editor is docked under a read-only tab until '
      'started or cancelled', (tester) async {
    late TempRepo t;
    late String base;
    final app = AppController(null, Settings());
    await tester.runAsync(() async {
      t = await TempRepo.create();
      base = t.commit('one', {'a.txt': '1\n'});
      t.commit('two', {'a.txt': '2\n'});
      t.commit('three', {'a.txt': '3\n'});
      await app.openRepo(t.path);
      final tab = app.activeTab!;
      for (var i = 0; i < 200 && tab.loading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    addTearDown(() {
      app.closeTabs(List.of(app.tabs));
      t.dispose();
    });
    final tab = app.activeTab!;
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: AppShell(app: app),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    /// Lets git answer, then shows what it said.
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> open() async {
      final context = tester.element(find.byType(AppShell));
      await tester.runAsync(
        () => showInteractiveRebase(context, tab, base, baseLabel: 'one'),
      );
      await tester.pump();
      await tester.pump();
    }

    final panel = find.byKey(const ValueKey('rebase-dock'));
    final summary = find.byKey(const ValueKey('rebase-summary'));
    final banner = find.byKey(const ValueKey('rebase-editor-banner'));
    VoidCallback? pull() => tester
        .widget<ToolbarButton>(find.widgetWithText(ToolbarButton, 'Pull'))
        .onPressed;
    expect(pull(), isNotNull);

    await open();
    expect(panel, findsOneWidget);
    expect(banner, findsOneWidget);
    // Its actions sit at the right edge, as on the folded bar.
    expect(
      tester.getRect(find.byKey(const ValueKey('rebase-collapse'))).right,
      closeTo(tester.getRect(panel).right - 12, 1),
    );
    expect(tab.locked, isTrue);
    // The graph behind it still shows (and can be browsed); changes can't
    // be made.
    expect(find.text('two'), findsWidgets);
    expect(pull(), isNull);
    var ran = false;
    expect(await tab.run('Test', () async => ran = true), isFalse);
    expect(ran, isFalse);

    // The editor has the keys: D drops the newest commit.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.pump();
    final three = tab.rebaseSession.value!.steps.last;
    expect(three.subject, 'three');
    expect(three.action, RebaseAction.drop);

    // The graph shows the plan: what happens to each commit, and the base.
    await tester.pump();
    expect(find.text('drop'), findsOneWidget);
    expect(find.text('onto'), findsOneWidget);

    // Folded into a summary, and back.
    await tester.tap(find.byKey(const ValueKey('rebase-collapse')));
    await tester.pump();
    expect(panel, findsNothing);
    expect(summary, findsOneWidget);
    expect(find.textContaining('2 commits: 1 dropped'), findsOneWidget);
    expect(find.text('drop'), findsOneWidget); // still in the graph
    await tester.tap(find.byKey(const ValueKey('rebase-expand')));
    await tester.pump();
    expect(panel, findsOneWidget);
    expect(find.text('Drop'), findsWidgets); // as it was

    // Another tab (home) hides it; coming back, it's as it was.
    app.activate(-1);
    await tester.pump();
    expect(panel, findsNothing);
    app.activate(0);
    await tester.pump();
    expect(panel, findsOneWidget);
    expect(find.text('Drop'), findsWidgets);

    // Cancelled from the banner: the tab can be changed again.
    await tester.tap(find.byKey(const ValueKey('banner-cancel-rebase')));
    await tester.pump();
    expect(panel, findsNothing);
    expect(banner, findsNothing);
    expect(tab.locked, isFalse);
    expect(pull(), isNotNull);

    // Started: the rebase runs and the editor goes.
    await open();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.pump();
    await tester.tap(find.text('Start rebase'));
    await settle();
    expect(panel, findsNothing);
    expect(tab.rebaseSession.value, isNull);
    expect(t.subjects(), ['two', 'one']);

    // Stops the tab's timers (switching tabs started them in fake time), and
    // lets the views' ones (tooltips, scrollbars) run out.
    app.closeTabs(List.of(app.tabs));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
