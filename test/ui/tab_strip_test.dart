import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/ui/shell/tab_strip.dart';
import 'package:gutter/ui/shell/tab_switcher.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late AppController app;

  setUp(() {
    root = Directory.systemTemp.createTempSync('gutter_strip_');
  });
  tearDown(() {
    app.closeTabs(List.of(app.tabs));
    root.deleteSync(recursive: true);
  });

  /// The strip over tabs for repositories [names], none loaded.
  Future<void> pumpStrip(WidgetTester tester, List<String> names) async {
    app = AppController(null, Settings());
    await tester.runAsync(() async {
      for (final n in names) {
        final dir = Directory(p.join(root.path, n))..createSync();
        Process.runSync('git', ['init', '-q', dir.path]);
        await app.openRepo(dir.path, activate: false);
      }
    });
    // As if loaded: showing a tab doesn't run git (it can't here).
    for (final t in app.tabs) {
      t
        ..started = true
        ..loading = false;
    }
    tester.view.physicalSize = const Size(1400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: app,
            builder: (_, _) => TabStrip(app: app),
          ),
        ),
      ),
    );
  }

  /// Drags [what] to [at] (a fraction across [onto]'s width).
  Future<void> drag(
    WidgetTester tester,
    Finder what,
    Finder onto,
    double at,
  ) async {
    // The whole tab or chip, not just its label.
    final rect = tester.getRect(
      find.ancestor(of: onto, matching: find.byType(GestureDetector)).first,
    );
    final from = tester.getCenter(what);
    final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    await tester.pump();
    final to = Offset(rect.left + rect.width * at, rect.center.dy);
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 10)!);
      await tester.pump();
    }
    await g.up();
    await tester.pump();
  }

  List<String> order() => [
    for (final t in app.tabs) '${t.name}${t.group == null ? '' : '*'}',
  ];

  testWidgets('drag a tab onto another to group them, beside to move', (
    tester,
  ) async {
    await pumpStrip(tester, ['alpha', 'beta', 'gamma', 'delta']);

    // Onto the middle of a tab: a new group of the two.
    await drag(tester, find.text('delta'), find.text('beta'), 0.5);
    expect(order(), ['alpha', 'beta*', 'delta*', 'gamma']);
    expect(app.groups, hasLength(1));

    // Beside a grouped tab: into its group.
    await drag(tester, find.text('alpha'), find.text('delta'), 0.95);
    expect(order(), ['beta*', 'delta*', 'alpha*', 'gamma']);

    // Beside an ungrouped tab: out of the group.
    await drag(tester, find.text('beta'), find.text('gamma'), 0.95);
    expect(order(), ['delta*', 'alpha*', 'gamma', 'beta']);

    // Dropped back on itself: stays put, in its group.
    await drag(tester, find.text('delta'), find.text('delta'), 0.9);
    expect(order(), ['delta*', 'alpha*', 'gamma', 'beta']);
  });

  testWidgets('a working tab shows progress on its top edge, not in its size', (
    tester,
  ) async {
    await pumpStrip(tester, ['alpha', 'beta']);
    final tab = app.tabs.first;
    final bar = find.byKey(const ValueKey('tab-progress'));
    Size size() => tester.getSize(
      find
          .ancestor(
            of: find.text('alpha'),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    final idle = size();
    expect(bar, findsNothing);
    // Nothing animates while no tab works.
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.binding.hasScheduledFrame, isFalse);

    tab.busy = 'Fetch'; // working
    tab.toggleDetails(); // (tells the tab; no git involved)
    await tester.pump();
    expect(bar, findsOneWidget);
    expect(size(), idle);
    // …and it keeps moving.
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.binding.hasScheduledFrame, isTrue);
    expect(size(), idle);
    // The other tab isn't affected.
    expect(bar, findsOneWidget);

    tab.busy = null;
    tab.toggleDetails();
    await tester.pump();
    expect(bar, findsNothing);
    expect(size(), idle);
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a group chip keeps its size while collapsing and expanding '
      'quickly', (tester) async {
    await pumpStrip(tester, ['alpha', 'beta', 'gamma']);
    final g = app.createGroup([app.tabs[0], app.tabs[1]]); // no name
    await tester.pump();
    final chip = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_GroupChip',
    );
    // A dot (28 wide with its padding) or a count badge (44), never in between:
    // an animated container swelled it to 170 wide mid-way.
    double width() => tester.getSize(chip).width;
    expect(width(), 28);
    for (var i = 0; i < 12; i++) {
      await tester.tap(chip);
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(Duration(milliseconds: 10 + (i % 3) * 20));
        expect(chip, findsOneWidget, reason: 'click ${i + 1}');
        expect(width(), lessThanOrEqualTo(60), reason: 'click ${i + 1}');
        expect(width(), greaterThanOrEqualTo(20), reason: 'click ${i + 1}');
      }
    }
    await tester.pumpAndSettle();
    expect(g.collapsed, isFalse); // an even number of clicks
    expect(app.groups, [g]);
    expect(width(), 28);
  });

  testWidgets('a tab shows its path after a second, but not while dragging', (
    tester,
  ) async {
    await pumpStrip(tester, ['alpha', 'beta', 'gamma']);
    final path = app.tabs[1].repo.path;
    // Only the hovered tab has a tooltip: a hundred would be a hundred
    // widgets to rebuild whenever tooltips are hidden for a drag.
    expect(find.byType(Tooltip), findsNWidgets(2)); // home and all tabs

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('beta')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.text(path), findsOneWidget);

    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(path), findsNothing);
    expect(find.byType(Tooltip), findsNWidgets(2));

    // While dragging another tab over it: no tooltip.
    final start = tester.getCenter(find.text('alpha'));
    final over = tester.getCenter(find.text('beta'));
    final drag = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    for (var i = 1; i <= 8; i++) {
      await drag.moveTo(Offset.lerp(start, over, i / 8)!);
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text(path), findsNothing);
    await drag.up();
    await tester.pump();
  });

  testWidgets('chips collapse and expand; menus group and ungroup', (
    tester,
  ) async {
    await pumpStrip(tester, ['alpha', 'beta', 'gamma']);

    // Right-click → Add to new group: the editor opens to name it.
    await tester.tap(find.text('beta'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to new group'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('group-editor')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('group-name')), 'work');
    await tester.tap(find.byKey(const ValueKey('group-color-4')));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final g = app.groups.single;
    expect((g.name, g.color), ('work', 4));
    expect(find.text('work'), findsOneWidget);

    // Another tab joins from the menu.
    await tester.tap(find.text('gamma'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to work'));
    await tester.pumpAndSettle();
    expect(order(), ['alpha', 'beta*', 'gamma*']);

    // The chip folds its tabs away, showing their count.
    await tester.tap(find.text('work'));
    await tester.pump();
    expect(find.text('beta'), findsNothing);
    expect(find.text('work  2'), findsOneWidget);
    await tester.tap(find.text('work  2'));
    await tester.pump();
    expect(find.text('beta'), findsOneWidget);

    // Right-click the chip → Ungroup.
    await tester.tap(find.text('work'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ungroup'));
    await tester.pumpAndSettle();
    expect(app.groups, isEmpty);
    expect(find.text('work'), findsNothing);
  });

  testWidgets('all tabs: grouped, searchable, Enter shows the pick', (
    tester,
  ) async {
    await pumpStrip(tester, ['alpha', 'beta', 'gamma', 'delta']);
    app.createGroup([app.tabs[1], app.tabs[2]], name: 'clients');
    app.setGroupCollapsed(app.groups.single, true);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('all-tabs')));
    await tester.pumpAndSettle();
    expect(find.byType(TabSwitcher), findsOneWidget);
    expect(find.text('CLIENTS'), findsOneWidget);
    expect(find.text('NOT IN A GROUP'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('tab-search')), 'gam');
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(TabSwitcher),
        matching: find.text('alpha'),
      ),
      findsNothing,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(TabSwitcher), findsNothing);
    expect(app.activeTab!.name, 'gamma');
    // Its collapsed group opened to show it.
    expect(app.groups.single.collapsed, isFalse);
    app.closeTabs(List.of(app.tabs)); // stops its timers
    await tester.pump();
  });
}
