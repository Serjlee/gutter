import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/ui/graph_view/commit_graph_view.dart';
import 'package:gutter/ui/repo/repo_tab_controller.dart';

import '../support/temp_repo.dart';

void main() {
  testWidgets('search marks what matched and fades the rest, labels too', (
    tester,
  ) async {
    late TempRepo t;
    late RepoTabController tab;
    await tester.runAsync(() async {
      t = await TempRepo.create();
      t.commit('Set things up', {'a.txt': '1\n'});
      t.git(['branch', 'old']);
      t.commit('Draw the Graph edges', {'a.txt': '2\n'});
      tab = RepoTabController(t.repo, AppController(null, Settings()));
      await tab.load();
    });
    addTearDown(() {
      tab.dispose();
      t.dispose();
    });
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tab.setSearch('graph');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: CommitGraphView(tab: tab)),
      ),
    );
    await tester.pump();

    // "Graph" is marked, in its own case.
    final hit = tester.widget<Text>(find.text('Draw the Graph edges'));
    final marked = (hit.textSpan! as TextSpan).children!.cast<TextSpan>().where(
      (s) => s.style?.backgroundColor != null,
    );
    expect(marked.map((s) => s.text), ['Graph']);

    // The other commit's label fades with its row.
    final label = find.ancestor(
      of: find.text('old'),
      matching: find.byType(Opacity),
    );
    expect(tester.widget<Opacity>(label.first).opacity, lessThan(1));
    final mainLabel = find.ancestor(
      of: find.text('main'),
      matching: find.byType(Opacity),
    );
    expect(tester.widget<Opacity>(mainLabel.first).opacity, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
