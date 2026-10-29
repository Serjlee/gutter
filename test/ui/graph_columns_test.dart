import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/graph/graph_painter.dart';
import 'package:gutter/ui/graph_view/commit_graph_view.dart';
import 'package:gutter/ui/repo/repo_tab_controller.dart';

import '../support/temp_repo.dart';

void main() {
  test('columns give way to the message, the age last', () {
    // Refs 190, author 140, age 64, sha 70; a 100 px graph; 200 px kept
    // for the message.
    final cols = GraphColumns(const {});
    String fit(double width) {
      final f = cols.fit(width, 100);
      return [
        'refs ${f.refs.round()}',
        if (f.author != null) 'author',
        if (f.age != null) 'age',
        if (f.sha != null) 'sha',
      ].join(', ');
    }

    expect(fit(800), 'refs 190, author, age, sha');
    expect(fit(700), 'refs 190, author, age');
    // The refs shrink before the author goes, and again before the age.
    expect(fit(620), 'refs 116, author, age');
    expect(fit(560), 'refs 110, age');
    expect(fit(450), 'refs 86, age');
    expect(fit(380), 'refs 80');
    expect(fit(300), 'refs 70');
  });

  test('compact, the ref labels take room in the graph column instead', () {
    final cols = GraphColumns(const {})..compact = true;
    // 100 px of lanes, and the labels' room past them.
    expect(cols.graphWidth(4), GraphColumns(const {}).graphWidth(4) + 160);
    final f = cols.fit(800, cols.graphWidth(4));
    expect(f.refs, 0);
    expect(f.author, isNotNull);
  });

  testWidgets('the header toggle moves the labels into the graph column', (
    tester,
  ) async {
    late TempRepo t;
    late RepoTabController tab;
    await tester.runAsync(() async {
      t = await TempRepo.create();
      t.commit('one', {'a.txt': '1\n'});
      t.git(['branch', 'side']);
      tab = RepoTabController(t.repo, AppController(null, Settings()));
      await tab.load();
    });
    addTearDown(() {
      tab.dispose();
      t.dispose();
    });
    tester.view.physicalSize = const Size(1400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: tab.app,
            builder: (_, _) => CommitGraphView(tab: tab),
          ),
        ),
      ),
    );
    await tester.pump();
    double labelX() => tester.getTopLeft(find.text('side')).dx;
    double nodeX() => tester
        .getTopLeft(
          find
              .byWidgetPredicate(
                (w) => w is CustomPaint && w.painter is GraphRowPainter,
              )
              .last,
        )
        .dx;

    // Their own column, left of the graph.
    expect(find.text('BRANCH / TAG'), findsOneWidget);
    expect(labelX(), lessThan(nodeX()));

    await tester.tap(find.byKey(const ValueKey('compact-graph')));
    await tester.pump();
    expect(tab.app.settings.compactGraph, isTrue);
    expect(find.text('BRANCH / TAG'), findsNothing);
    // Past the lanes, in the graph column.
    expect(labelX(), greaterThan(nodeX()));

    await tester.tap(find.byKey(const ValueKey('compact-graph')));
    await tester.pump();
    expect(tab.app.settings.compactGraph, isFalse);
    expect(find.text('BRANCH / TAG'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
