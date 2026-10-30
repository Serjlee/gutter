import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/graph/graph_painter.dart';
import 'package:gutter/ui/graph_view/commit_graph_view.dart';
import 'package:gutter/ui/repo/repo_tab_controller.dart';
import 'package:gutter/ui/dialogs/settings_dialog.dart';

import '../support/temp_repo.dart';

void main() {
  test('the line hint picked is saved; otherwise, the default', () {
    LineHint load(Map<String, Object?> j) => Settings.fromJson(j).lineHint;
    final s = Settings()..lineHint = LineHint.leader;
    expect(Settings.fromJson(s.toJson()).lineHint, LineHint.leader);
    expect(Settings().toJson().containsKey('lineHintChoice'), isFalse);
    expect(load({}), LineHint.fade);
    expect(load({'lineHintChoice': 'zigzag'}), LineHint.fade);
    // Saved by 0.7: the leader line, the default then, may not have been
    // picked; any other style was.
    expect(load({'lineHint': 'leader'}), LineHint.fade);
    expect(load({'lineHint': 'line'}), LineHint.line);
    expect(load({'lineHint': 'none'}), LineHint.none);
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
            builder: (_, _) =>
                SingleChildScrollView(child: SettingsForm(app: app)),
          ),
        ),
      ),
    );
    await tester.pump();
    // Each option shows what it looks like; Fade is picked.
    final picker = find.byKey(const ValueKey('line-hint'));
    for (final hint in LineHint.values) {
      final tile = find.byKey(ValueKey('line-hint-${hint.name}'));
      expect(find.descendant(of: picker, matching: tile), findsOneWidget);
      expect(
        find.descendant(of: tile, matching: find.text('Fix typo')),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('line-hint-fade')),
        matching: find.byKey(const ValueKey('line-hint-selected')),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('line-hint-line')));
    await tester.pump();
    expect(app.settings.lineHint, LineHint.line);

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
    expect(painter.hint, LineHint.line);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
