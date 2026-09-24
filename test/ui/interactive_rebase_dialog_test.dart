import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/git/rebase_plan.dart';
import 'package:gutter/ui/dialogs/interactive_rebase_dialog.dart';

void main() {
  // Oldest first, as the dialog receives them; shown newest (e) on top.
  late List<RebaseStep> steps;
  RebaseStep step(String subject) =>
      steps.firstWhere((s) => s.subject == subject);
  List<RebaseAction> actions() => [
    for (final s in steps.reversed) s.action,
  ]; // newest first, like the list

  setUp(() {
    steps = [
      for (final n in ['a', 'b', 'c', 'd', 'e'])
        RebaseStep(sha: '${n * 7}0', subject: n, message: n),
    ];
  });

  Future<void> pumpDialog(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: InteractiveRebaseDialog(
            steps: steps,
            branch: 'main',
            baseLabel: 'base',
            hasMerges: false,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyEvent(k);
    await tester.pump();
  }

  testWidgets('letter keys set the action of the highlighted row', (
    tester,
  ) async {
    await pumpDialog(tester);
    // The newest commit is highlighted initially.
    await key(tester, LogicalKeyboardKey.keyR);
    expect(step('e').action, RebaseAction.reword);
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.keyD);
    expect(step('d').action, RebaseAction.drop);
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.keyE);
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.keyF);
    expect(actions(), [
      RebaseAction.reword,
      RebaseAction.drop,
      RebaseAction.edit,
      RebaseAction.fixup,
      RebaseAction.pick,
    ]);
    await key(tester, LogicalKeyboardKey.keyP);
    expect(step('b').action, RebaseAction.pick);
  });

  testWidgets('Shift+arrows select a range; S squashes it into the oldest', (
    tester,
  ) async {
    await pumpDialog(tester);
    await key(tester, LogicalKeyboardKey.arrowDown); // d
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await key(tester, LogicalKeyboardKey.arrowDown); // d..c
    await key(tester, LogicalKeyboardKey.arrowDown); // d..b
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(find.text('3 selected'), findsOneWidget);
    await key(tester, LogicalKeyboardKey.keyS);
    // b (the oldest selected) is kept; c and d fold into it.
    expect(actions(), [
      RebaseAction.pick,
      RebaseAction.squash,
      RebaseAction.squash,
      RebaseAction.pick,
      RebaseAction.pick,
    ]);
    // The squash group's message combines the three.
    expect(step('b').newMessage, 'b\n\nc\n\nd');
  });

  testWidgets('checkboxes and toolbar buttons act on the selection', (
    tester,
  ) async {
    await pumpDialog(tester);
    final boxes = find.byType(Checkbox);
    // [0] is select-all; rows follow newest first: e d c b a.
    await tester.tap(boxes.at(3)); // c (e stays selected from the start)
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('rebase-action-drop')));
    await tester.pump();
    expect(step('e').action, RebaseAction.drop);
    expect(step('c').action, RebaseAction.drop);
    expect(step('d').action, RebaseAction.pick);
    // Keys still work after clicking a toolbar button, even when the
    // message box had focus before.
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('rebase-action-drop')));
    await tester.pump();
    await key(tester, LogicalKeyboardKey.keyF);
    expect(step('e').action, RebaseAction.fixup);
    expect(step('c').action, RebaseAction.pick); // folded into: kept

    await tester.tap(find.byKey(const ValueKey('rebase-select-all')));
    await tester.pump();
    expect(find.text('5 selected'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('rebase-action-pick')));
    await tester.pump();
    expect(actions().toSet(), {RebaseAction.pick});
  });

  testWidgets('Alt+arrows move the selected rows; Ctrl+A selects all', (
    tester,
  ) async {
    await pumpDialog(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    final order = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .where((d) => ['a', 'b', 'c', 'd', 'e'].contains(d))
        .toList();
    expect(order, ['d', 'c', 'e', 'b', 'a']);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await key(tester, LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(find.text('5 selected'), findsOneWidget);
  });

  testWidgets('typing in the message box does not trigger shortcuts', (
    tester,
  ) async {
    await pumpDialog(tester);
    await key(tester, LogicalKeyboardKey.keyR);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'new message');
    await key(tester, LogicalKeyboardKey.keyD);
    expect(step('e').action, RebaseAction.reword);
    expect(step('e').newMessage, 'new message');
  });
}
