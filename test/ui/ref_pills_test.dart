import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/ui/graph_view/commit_graph_view.dart';
import 'package:gutter/ui/repo/repo_tab_controller.dart';

import '../support/temp_repo.dart';

void main() {
  testWidgets('origin/main never folds into "+N"', (tester) async {
    late TempRepo upstream;
    late TempRepo t;
    late RepoTabController tab;
    await tester.runAsync(() async {
      upstream = await TempRepo.create();
      upstream.commit('one', {'a.txt': '1\n'});
      upstream.commit('two', {'a.txt': '2\n'});
      t = await TempRepo.create();
      t.git(['remote', 'add', 'origin', upstream.path]);
      t.git(['fetch', '-q', 'origin']);
      // A checked-out branch, origin/main and a tag on one commit; a
      // remote branch and a tag on another.
      t.git(['checkout', '-q', '-b', 'feature', 'origin/main']);
      t.git(['tag', 'v1']);
      t.git(['update-ref', 'refs/remotes/origin/other', 'HEAD~1']);
      t.git(['tag', 'v0', 'HEAD~1']);
      tab = RepoTabController(t.repo, AppController(null, Settings()));
      await tab.load();
    });
    addTearDown(() {
      tab.dispose();
      t.dispose();
      upstream.dispose();
    });
    tester.view.physicalSize = const Size(1400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: CommitGraphView(tab: tab)),
      ),
    );
    await tester.pump();

    // The head row: feature, then origin/main (as "main", with the cloud
    // icon), then the tag folded.
    expect(find.text('feature'), findsOneWidget);
    expect(find.text('main'), findsOneWidget);
    expect(find.text('+1'), findsNWidgets(2));
    final main = tester.widget<Text>(find.text('main'));
    expect(main.style!.fontWeight, FontWeight.w700);
    // Other remote branches still fold behind the first pill as before.
    expect(find.text('origin/other'), findsOneWidget);
    expect(find.text('v0'), findsNothing);
  });
}
