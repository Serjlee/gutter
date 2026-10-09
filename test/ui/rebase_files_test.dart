import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/git/rebase_plan.dart';
import 'package:gutter/ui/dialogs/interactive_rebase_dialog.dart';
import 'package:gutter/ui/repo/repo_tab_controller.dart';

import '../support/temp_repo.dart';

void main() {
  testWidgets('the rebase editor lists the highlighted commit\'s files and '
      'previews one on click', (tester) async {
    late TempRepo t;
    late RepoTabController tab;
    late List<RebaseStep> steps;
    await tester.runAsync(() async {
      t = await TempRepo.create();
      t.commit('base', {'a.txt': 'one\n'});
      t.commit('second', {'a.txt': 'one\ntwo\n', 'b.txt': 'b\n'});
      t.commit('third', {'c.txt': 'c\n'});
      tab = RepoTabController(t.repo, AppController(null, Settings()));
      steps = await t.repo.rebaseCandidates('HEAD~2');
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
          body: InteractiveRebaseDialog(
            tab: tab,
            steps: steps,
            branch: 'main',
            baseLabel: 'base',
            hasMerges: false,
          ),
        ),
      ),
    );

    /// Lets git answer, then shows what it said.
    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Finder file(String path) => find.byKey(ValueKey('rebase-file-$path'));

    // The newest commit is highlighted.
    await settle();
    expect(file('c.txt'), findsOneWidget);
    expect(file('a.txt'), findsNothing);

    // Down to the older one: its files.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await settle();
    expect(file('a.txt'), findsOneWidget);
    expect(file('b.txt'), findsOneWidget);
    expect(file('c.txt'), findsNothing);

    // A click shows what the commit changed in the file.
    await tester.tap(file('a.txt'));
    await settle();
    final preview = find.byKey(const ValueKey('commit-file-preview'));
    expect(preview, findsOneWidget);
    expect(
      find.descendant(
        of: preview,
        matching: find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText() == 'two',
        ),
      ),
      findsOneWidget,
    );
    // …without touching the tab's own diff.
    expect(tab.diffTarget, isNull);

    // Esc closes the preview, and the editor's keys work again.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(preview, findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.pump();
    expect(steps.first.action, RebaseAction.drop);

    // Let the views' timers (tooltips, scrollbars) run out.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
