import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/ui/diff/diff_view.dart';
import 'package:gutter/ui/repo/repo_tab_controller.dart';

import '../support/temp_repo.dart';

void main() {
  late TempRepo t;
  late RepoTabController tab;

  /// The diff of a.txt, where line 2 is replaced and line 4 added.
  Future<void> pumpDiff(WidgetTester tester) async {
    await tester.runAsync(() async {
      t = await TempRepo.create();
      t.commit('one', {'a.txt': 'a\nb\nc\n'});
      t.write('a.txt', 'a\nB\nc\nd\n');
      tab = RepoTabController(t.repo, AppController(null, Settings()));
      await tab.load();
      tab.openWorkingFile(tab.status.unstaged.single, staged: false);
      for (var i = 0; i < 100 && tab.diff == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    addTearDown(() {
      tab.dispose();
      t.dispose();
    });
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: tab,
            builder: (_, _) => DiffView(tab: tab),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder selected(int n) => find.text('$n line${n == 1 ? '' : 's'} selected');

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('the +/- marker selects its line', (tester) async {
    await pumpDiff(tester);
    await tester.tap(find.text('-')); // b
    await tester.pump();
    expect(selected(1), findsOneWidget);
    await tester.tap(find.text('+').first); // B
    await tester.pump();
    expect(selected(2), findsOneWidget);
    await tester.tap(find.text('-'));
    await tester.pump();
    expect(selected(1), findsOneWidget);
    await finish(tester);
  });

  testWidgets('split: a replaced line is selected with what it replaces', (
    tester,
  ) async {
    await pumpDiff(tester);
    await tester.tap(find.text('Split'));
    await tester.pump();

    // The markers show here too, and select.
    expect(find.text('+'), findsNWidgets(2)); // B, d
    await tester.tap(find.text('-')); // b, with B
    await tester.pump();
    expect(selected(2), findsOneWidget);
    await tester.tap(find.text('-'));
    await tester.pump();
    expect(find.text('Stage lines'), findsNothing);

    /// The line number [n] on the left or the right side.
    Finder number(String n, {required bool right}) {
      final all = find.text(n).evaluate().toList()
        ..sort(
          (a, b) => tester
              .getCenter(find.byWidget(a.widget))
              .dx
              .compareTo(tester.getCenter(find.byWidget(b.widget)).dx),
        );
      return find.byWidget((right ? all.last : all.first).widget);
    }

    // B (right) takes b (left) along, and the other way round.
    await tester.tap(number('2', right: true));
    await tester.pump();
    expect(selected(2), findsOneWidget);
    await tester.tap(number('2', right: false));
    await tester.pump();
    expect(selected(2), findsNothing);
    expect(find.text('Stage lines'), findsNothing);

    // An added line alone is just itself; Shift extends by rows.
    await tester.tap(number('4', right: true));
    await tester.pump();
    expect(selected(1), findsOneWidget);
    await tester.tap(number('4', right: true));
    await tester.pump();
    await tester.tap(number('2', right: true));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(number('4', right: true), kind: PointerDeviceKind.mouse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(selected(3), findsOneWidget);

    // Staging the replaced pair stages the replacement, not an insertion.
    await tester.tap(number('4', right: true));
    await tester.pump();
    expect(selected(2), findsOneWidget);
    await tester.tap(find.text('Stage lines'));
    for (var i = 0; i < 20 && t.git(['show', ':a.txt']) != 'a\nB\nc\n'; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(t.git(['show', ':a.txt']), 'a\nB\nc\n');
    await finish(tester);
  });

  testWidgets('changed lines line up with the others', (tester) async {
    await pumpDiff(tester);
    // a (context) and B (added): their code starts at the same x.
    double x(String text) => tester.getTopLeft(find.text(text)).dx;
    expect(x('B'), x('a'));
    expect(x('d'), x('c'));
    // Selected too (the mark doesn't push it).
    await tester.tap(find.text('+').first);
    await tester.pump();
    expect(x('B'), x('a'));
    await finish(tester);
  });
}
