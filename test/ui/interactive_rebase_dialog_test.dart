import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/git/rebase_plan.dart';
import 'package:gutter/ui/dialogs/interactive_rebase_dialog.dart';
import 'package:gutter/ui/widgets/resizable_box.dart';

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

  Future<void> pumpDialog(
    WidgetTester tester, {
    Set<String> initialSelection = const {},
  }) async {
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
            initialSelection: initialSelection,
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

  testWidgets('opens with a preset squash selected, oldest highlighted', (
    tester,
  ) async {
    // What "Squash 3 commits" in the graph does before opening the dialog.
    expect(presetSquash(steps, {'bbbbbbb0', 'ccccccc0', 'ddddddd0'}), isTrue);
    await pumpDialog(
      tester,
      initialSelection: {'bbbbbbb0', 'ccccccc0', 'ddddddd0'},
    );
    expect(find.text('3 selected'), findsOneWidget);
    // The highlighted row is b, the head of the squash group, so the
    // message box shows the combined message.
    expect(find.text('New message'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'b\n\nc\n\nd',
    );
  });

  testWidgets('the edges resize it, the gap between the panes moves', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Size? resized;
    double? split;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: InteractiveRebaseDialog(
            steps: steps,
            branch: 'main',
            baseLabel: 'base',
            hasMerges: false,
            onResized: (s) => resized = s,
            onSplit: (s) => split = s,
          ),
        ),
      ),
    );
    await tester.pump();
    final box = find.byType(ResizableBox);
    expect(tester.getSize(box), const Size(960, 620));

    // Centered: the dragged edge follows the pointer, the other one mirrors.
    final right = tester.getRect(box).right;
    await tester.drag(
      find.byKey(const ValueKey('resize-right')),
      const Offset(50, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(tester.getSize(box).width, closeTo(1060, 1));
    expect(tester.getRect(box).right, closeTo(right + 50, 1));
    expect(resized!.width, closeTo(1060, 1));

    // A corner moves both; never past the window, nor below the minimum.
    await tester.drag(
      find.byKey(const ValueKey('resize-corner')),
      const Offset(-400, -400),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(tester.getSize(box), const Size(600, 420));
    await tester.drag(
      find.byKey(const ValueKey('resize-bottom')),
      const Offset(0, 800),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(tester.getSize(box).height, 900 - 48); // the dialog's insets
    expect(resized, tester.getSize(box));
    await tester.drag(
      find.byKey(const ValueKey('resize-right')),
      const Offset(400, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(tester.getSize(box).width, 1200 - 80);

    // The gap between the commits and the message.
    double listWidth() =>
        tester.getSize(find.byKey(const ValueKey('rebase-list-pane'))).width;
    final before = listWidth();
    await tester.drag(
      find.byKey(const ValueKey('rebase-split')),
      const Offset(-60, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(listWidth(), closeTo(before - 60, 1));
    expect(split, lessThan(0.6));
    // Each pane keeps room for its controls.
    await tester.drag(
      find.byKey(const ValueKey('rebase-split')),
      const Offset(-800, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(listWidth(), 300);
    await tester.drag(
      find.byKey(const ValueKey('rebase-split')),
      const Offset(1600, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    final pane = tester.getSize(find.byKey(const ValueKey('rebase-split')));
    expect(pane.width, 14);
    expect(
      tester.getRect(find.byType(ResizableBox)).right -
          tester.getRect(find.byKey(const ValueKey('rebase-split'))).right,
      closeTo(220 + 20, 1), // the side pane and the dialog's padding
    );
  });

  test('the size and split are saved', () {
    final s = Settings()
      ..rebaseWidth = 1100
      ..rebaseHeight = 700
      ..rebaseSplit = 0.45
      ..rebaseMessageSplit = 0.5;
    (double, double, double, double) saved(Settings s) =>
        (s.rebaseWidth, s.rebaseHeight, s.rebaseSplit, s.rebaseMessageSplit);
    expect(saved(Settings.fromJson(s.toJson())), (1100, 700, 0.45, 0.5));
    expect(saved(Settings.fromJson({})), (960, 620, 0.6, 1 / 3));
  });
}
