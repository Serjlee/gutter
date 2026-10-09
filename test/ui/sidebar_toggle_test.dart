import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/ui/graph_view/commit_graph_view.dart';
import 'package:gutter/ui/shell/app_shell.dart';
import 'package:gutter/ui/sidebar/sidebar.dart';

import '../support/temp_repo.dart';

void main() {
  test('the sidebar setting is saved, and defaults to shown', () {
    final s = Settings()..sidebarOpen = false;
    expect(Settings.fromJson(s.toJson()).sidebarOpen, isFalse);
    expect(Settings.fromJson({}).sidebarOpen, isTrue);
  });

  testWidgets('the sidebar hides and shows from its button and its shortcut', (
    tester,
  ) async {
    late TempRepo t;
    final settings = Settings();
    final app = AppController(null, settings);
    await tester.runAsync(() async {
      t = await TempRepo.create();
      t.commit('one', {'a.txt': '1\n'});
      t.commit('two', {'a.txt': '2\n'});
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
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: AppShell(app: app),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final sidebar = find.byType(Sidebar);
    final graph = find.byType(CommitGraphView);
    final button = find.byKey(const ValueKey('toggle-sidebar'));
    double graphLeft() => tester.getTopLeft(graph).dx;
    expect(sidebar, findsOneWidget);
    final withSidebar = graphLeft();

    // The toolbar button.
    await tester.tap(button);
    await tester.pump();
    expect(sidebar, findsNothing);
    expect(settings.sidebarOpen, isFalse);
    expect(graph, findsOneWidget);
    expect(graphLeft(), lessThan(withSidebar)); // it took the room
    await tester.tap(button);
    await tester.pump();
    expect(sidebar, findsOneWidget);
    expect(graphLeft(), withSidebar);

    // Ctrl+B.
    Future<void> ctrlB() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    await ctrlB();
    expect(sidebar, findsNothing);
    await ctrlB();
    expect(sidebar, findsOneWidget);

    // Hidden stays hidden when the tab's view is built again (another tab,
    // or the next start).
    await tester.tap(button);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: AppShell(app: app),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(sidebar, findsNothing);
    expect(graph, findsOneWidget);

    // Let the views' timers (tooltips, scrollbars) run out.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
