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

  test('compact, the graph column has room for the labels', () {
    final full = GraphColumns(const {});
    final compact = GraphColumns(const {})..mode = GraphMode.compact;
    expect(compact.graphWidth(4), full.graphWidth(4) + 160);
    expect(compact.fit(800, compact.graphWidth(4)).refs, 0);
    for (final m in [GraphMode.fork, GraphMode.alignedFork]) {
      final cols = GraphColumns(const {})..mode = m;
      expect(cols.graphWidth(4), full.graphWidth(4));
      expect(cols.fit(800, cols.graphWidth(4)).refs, 0);
    }
  });

  testWidgets('each graph mode puts the labels and messages its way', (
    tester,
  ) async {
    late TempRepo t;
    late RepoTabController tab;
    await tester.runAsync(() async {
      // one (tagged), two: one lane; then side and three: two lanes.
      t = await TempRepo.create();
      t.commit('one', {'a.txt': '1\n'});
      t.git(['tag', 'v1']);
      t.commit('two', {'a.txt': '2\n'});
      t.git(['checkout', '-q', '-b', 'side']);
      t.commit('side work', {'b.txt': '1\n'});
      t.git(['checkout', '-q', 'main']);
      t.commit('three', {'a.txt': '3\n'});
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
    double x(String text) => tester.getTopLeft(find.text(text)).dx;
    double nodeX() => tester
        .getTopLeft(
          find
              .byWidgetPredicate(
                (w) => w is CustomPaint && w.painter is GraphRowPainter,
              )
              .last,
        )
        .dx;
    double pillX(String label) => tester
        .getTopLeft(
          find
              .ancestor(of: find.text(label), matching: find.byType(Container))
              .first,
        )
        .dx;
    Future<void> mode(GraphMode m) async {
      tab.app.setGraphMode(m);
      await tester.pump();
    }

    // Full: a column of their own, left of the graph.
    expect(find.text('BRANCH / TAG'), findsOneWidget);
    expect(x('v1'), lessThan(nodeX()));

    // Compact: in the graph column; messages in theirs, all aligned.
    await mode(GraphMode.compact);
    expect(find.text('BRANCH / TAG'), findsNothing);
    expect(x('v1'), greaterThan(nodeX()));
    expect(x('one'), x('two'));

    // Aligned Fork: before the message, where unlabelled messages start.
    await mode(GraphMode.alignedFork);
    expect(pillX('v1'), x('two'));
    expect(x('one'), greaterThan(x('two')));
    final aligned = pillX('v1');

    // Fork: right after each row's own lanes, so further left on the
    // bottom row, where the graph is one lane wide.
    await mode(GraphMode.fork);
    expect(pillX('v1'), lessThan(aligned - 10));
    expect(x('one'), greaterThan(pillX('v1')));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  test('the graph mode is saved; compact from before is aligned Fork', () {
    final s = Settings()..graphMode = GraphMode.fork;
    expect(Settings.fromJson(s.toJson()).graphMode, GraphMode.fork);
    expect(Settings.fromJson({}).graphMode, GraphMode.full);
    expect(
      Settings.fromJson({'compactGraph': true}).graphMode,
      GraphMode.alignedFork,
    );
  });
}
