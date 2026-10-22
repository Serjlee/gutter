import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/git/models.dart';
import 'package:gutter/ui/graph_view/commit_graph_view.dart';
import 'package:gutter/ui/graph_view/date_groups.dart';
import 'package:gutter/ui/repo/repo_tab_controller.dart';
import 'package:gutter/ui/widgets/common.dart';

import '../support/temp_repo.dart';

void main() {
  final now = DateTime(2026, 10, 22, 11, 30);

  Commit at(DateTime d, {DateTime? authored}) {
    final t = d.millisecondsSinceEpoch ~/ 1000;
    return Commit(
      sha: '$t',
      parents: const [],
      authorName: 'A',
      authorEmail: 'a@x',
      authorTime: authored == null
          ? t
          : authored.millisecondsSinceEpoch ~/ 1000,
      commitTime: t,
      subject: 's',
    );
  }

  test('groups by calendar days', () {
    DateGroup g(DateTime d) => DateGroup.of(d, now);
    expect(g(DateTime(2026, 10, 22, 0, 1)), DateGroup.today);
    expect(g(DateTime(2026, 10, 23)), DateGroup.today); // a clock ahead
    expect(g(DateTime(2026, 10, 21, 23, 59)), DateGroup.yesterday);
    expect(g(DateTime(2026, 10, 20)), DateGroup.lastWeek);
    expect(g(DateTime(2026, 10, 16)), DateGroup.lastWeek);
    expect(g(DateTime(2026, 10, 15)), DateGroup.lastMonth);
    expect(g(DateTime(2026, 9, 22)), DateGroup.lastMonth);
    expect(g(DateTime(2026, 9, 21)), DateGroup.lastYear);
    expect(g(DateTime(2025, 10, 22)), DateGroup.lastYear);
    expect(g(DateTime(2025, 10, 20)), DateGroup.older);
  });

  test('a separator under the last row of each group', () {
    final rows = <Commit?>[
      null, // WIP
      at(DateTime(2026, 10, 22, 9)),
      at(DateTime(2026, 10, 22, 8)),
      at(DateTime(2026, 10, 21, 20)),
      at(DateTime(2026, 10, 2)), // stash, made on the row below
      at(DateTime(2026, 9, 1)),
      at(DateTime(2024, 1, 1)),
      at(DateTime(2023, 1, 1)),
    ];
    final seps = dateSeparators(rows, now, isStash: (row) => row == 4);
    expect(seps, {
      2: DateGroup.today,
      3: DateGroup.yesterday,
      5: DateGroup.lastYear,
    });
  });

  test('groups by commit date, and a commit out of order stays put', () {
    final rows = [
      // Rebased today: authored long ago, committed today.
      at(DateTime(2026, 10, 22, 9), authored: DateTime(2025, 1, 1)),
      at(DateTime(2026, 10, 20)),
      // A clock ahead: newer than the row above, still in its group.
      at(DateTime(2026, 10, 22, 7)),
      at(DateTime(2026, 9, 30)),
    ];
    expect(dateSeparators(rows, now), {
      0: DateGroup.today,
      2: DateGroup.lastWeek,
    });
    expect(dateSeparators(const [], now), isEmpty);
  });

  test('short ages', () {
    String age(Duration d) => shortAge(now.subtract(d), now: now);
    expect(age(const Duration(seconds: 20)), 'now');
    expect(age(const Duration(minutes: 5)), '5m');
    expect(age(const Duration(hours: 3, minutes: 59)), '3h');
    expect(age(const Duration(days: 12)), '12d');
    expect(age(const Duration(days: 30)), '30d');
    expect(age(const Duration(days: 100)), '3mo');
    expect(age(const Duration(days: 800)), '2y');
  });

  testWidgets('the graph shows ages, and separators in gaps', (tester) async {
    late TempRepo t;
    late RepoTabController tab;
    final now = DateTime.now();
    final fresh = now.subtract(const Duration(minutes: 1));
    await tester.runAsync(() async {
      t = await TempRepo.create();
      t.commit('ancient', {
        'a.txt': '1',
      }, now.subtract(const Duration(days: 400)));
      t.commit('recent', {'a.txt': '2'}, now.subtract(const Duration(days: 3)));
      t.commit('fresh', {'a.txt': '3'}, fresh);
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
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: CommitGraphView(tab: tab)),
      ),
    );
    await tester.pump();

    expect(find.text('AGE'), findsOneWidget);
    expect(find.text('1m'), findsOneWidget);
    expect(find.text('3d'), findsOneWidget);
    expect(find.text('1y'), findsOneWidget);
    // Today, unless the test runs in the first minute of the day.
    final group = DateGroup.of(fresh, DateTime.now());
    expect(
      find.byKey(ValueKey('date-separator-${group.name}')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('date-separator-lastWeek')),
      findsOneWidget,
    );
    // Each separator takes its own space between the rows.
    double y(String s) => tester.getTopLeft(find.text(s)).dy;
    expect(y('recent') - y('fresh'), greaterThan(40));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
