import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/graph/graph_painter.dart';
import 'package:gutter/ui/graph_view/commit_graph_view.dart';
import 'package:gutter/ui/repo/repo_tab_controller.dart';
import 'package:gutter/ui/shell/home_tab.dart';

import '../support/temp_repo.dart';

void main() {
  test('the line hint is saved, unknown values meaning the leader line', () {
    final s = Settings()..lineHint = LineHint.fade;
    expect(Settings.fromJson(s.toJson()).lineHint, LineHint.fade);
    expect(Settings.fromJson({'lineHint': 'zigzag'}).lineHint, LineHint.leader);
    expect(Settings.fromJson({}).lineHint, LineHint.leader);
  });

  testWidgets('picked in the settings, with previews, and drawn by the graph', (
    tester,
  ) async {
    late TempRepo t;
    late RepoTabController tab;
    await tester.runAsync(() async {
      t = await TempRepo.create();
      t.commit('one', {'a.txt': '1\n'});
      tab = RepoTabController(t.repo, AppController(null, Settings()));
      await tab.load();
    });
    addTearDown(() {
      tab.dispose();
      t.dispose();
    });
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = tab.app;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: app,
            builder: (_, _) => HomeTab(app: app),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Leader line'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('line-hint')));
    await tester.pumpAndSettle();
    // Each option shows what it looks like.
    final menu = find.byType(PopupMenuItem<LineHint>);
    expect(menu, findsNWidgets(4));
    for (final label in ['Leader line', 'Line', 'Fade', 'None']) {
      final item = find.ancestor(of: find.text(label).last, matching: menu);
      expect(
        find.descendant(of: item, matching: find.text('Add the login form')),
        findsOneWidget,
        reason: label,
      );
    }
    await tester.tap(find.text('Fade').last);
    await tester.pumpAndSettle();
    expect(app.settings.lineHint, LineHint.fade);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: CommitGraphView(tab: tab)),
      ),
    );
    await tester.pump();
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<GraphRowPainter>()
        .first;
    expect(painter.hint, LineHint.fade);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
