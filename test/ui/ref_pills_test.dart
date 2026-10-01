import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/ui/graph_view/commit_graph_view.dart';
import 'package:gutter/ui/graph_view/scroll_marks.dart';
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
    // Marked by a light border, not bold (only the checked-out branch is).
    final main = tester.widget<Text>(find.text('main'));
    expect(main.style!.fontWeight, isNot(FontWeight.w700));
    final pill = tester.widget<Container>(
      find
          .ancestor(of: find.text('main'), matching: find.byType(Container))
          .first,
    );
    final border = (pill.decoration! as BoxDecoration).border! as Border;
    expect(border.top.color, ScrollMarks.trunkColor);
    expect(border.top.width, 1.5);
    // The checked-out branch: bold, with no checkmark; its commit bold too.
    final feature = tester.widget<Text>(find.text('feature'));
    expect(feature.style!.fontWeight, FontWeight.w700);
    expect(find.byIcon(Icons.check), findsNothing);
    final message = tester.widget<Text>(find.text('two'));
    expect(message.style!.fontWeight, FontWeight.w700);
    expect(
      tester.widget<Text>(find.text('one')).style!.fontWeight,
      isNot(FontWeight.w700),
    );
    // Other remote branches still fold behind the first pill as before.
    expect(find.text('origin/other'), findsOneWidget);
    expect(find.text('v0'), findsNothing);
  });

  testWidgets('labels fit however narrow the window is', (tester) async {
    late TempRepo upstream;
    late TempRepo t;
    late RepoTabController tab;
    await tester.runAsync(() async {
      upstream = await TempRepo.create();
      upstream.commit('one', {'a.txt': '1\n'});
      t = await TempRepo.create();
      t.git(['remote', 'add', 'origin', upstream.path]);
      t.git(['fetch', '-q', 'origin']);
      // HEAD, origin/main and a tag together; a long name with its remote.
      t.git([
        'checkout',
        '-q',
        '-b',
        'feature/a-rather-long-name',
        'origin/main',
      ]);
      t.git(['tag', 'v1']);
      t.commit('two', {'a.txt': '2\n'});
      t.git(['branch', 'origin-tracked-with-a-long-name']);
      t.git([
        'update-ref',
        'refs/remotes/origin/origin-tracked-with-a-long-name',
        'HEAD',
      ]);
      t.git(['checkout', '-q', '--detach', 'HEAD~1']);
      tab = RepoTabController(t.repo, AppController(null, Settings()));
      await tab.load();
    });
    addTearDown(() {
      tab.dispose();
      t.dispose();
      upstream.dispose();
    });
    for (final width in const <double>[1400, 700, 420, 300, 200]) {
      tester.view.physicalSize = Size(width, 500);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(body: CommitGraphView(tab: tab)),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'at ${width}px');
    }
    addTearDown(tester.view.reset);
  });

  group('scroll marks', () {
    const blue = Color(0xFF0000FF);
    List<ScrollMark> marks({
      required int rows,
      required double height,
      int? head,
      List<int> trunk = const [],
    }) => scrollMarks(
      height: height,
      rowCount: rows,
      rowHeight: 30,
      head: head,
      headColor: blue,
      trunk: trunk,
    );

    test('level with their rows when the list is shorter than the view', () {
      final m = marks(rows: 10, height: 600, head: 0, trunk: [3]);
      expect(m.map((m) => m.top), [105, 15]); // row centers
      expect(m.first.color, ScrollMarks.trunkColor);
      expect(m.last.color, blue);
    });

    test('on the scrollbar scale when it is longer', () {
      final m = marks(rows: 200, height: 600, trunk: [100]);
      expect(m.single.top, closeTo(301.5, 0.01)); // (100.5 / 200) of 600
    });

    test('overlapping marks merge, in between the colors', () {
      final m = marks(rows: 400, height: 600, head: 0, trunk: [1]);
      expect(m, hasLength(1));
      expect(m.single.top, lessThan(m.single.bottom));
      expect(m.single.color, Color.lerp(ScrollMarks.trunkColor, blue, 0.5));
    });
  });
}
