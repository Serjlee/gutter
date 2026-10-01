import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/ui/diff/diff_view.dart';
import 'package:gutter/ui/repo/repo_tab_controller.dart';

import '../support/temp_repo.dart';

void main() {
  test('the wrap setting is saved', () {
    final s = Settings()..diffWrap = true;
    expect(Settings.fromJson(s.toJson()).diffWrap, isTrue);
    expect(Settings.fromJson({}).diffWrap, isFalse);
  });

  testWidgets('long lines wrap in the unified diff when asked', (tester) async {
    final long = List.filled(60, 'word').join(' ');
    late TempRepo t;
    late RepoTabController tab;
    await tester.runAsync(() async {
      t = await TempRepo.create();
      t.commit('one', {'a.txt': 'short\n'});
      t.commit('two', {'a.txt': 'short\n$long\n'});
      tab = RepoTabController(t.repo, AppController(null, Settings()));
      await tab.load();
      final commit = tab.graph.commits.first;
      await tab.select(commit.sha);
      tab.openCommitFile(commit, tab.commitFiles.single);
      for (var i = 0; i < 100 && tab.diff == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    addTearDown(() {
      tab.dispose();
      t.dispose();
    });
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: DiffView(tab: tab)),
      ),
    );
    await tester.pump();

    double lineHeight() => tester
        .getSize(
          find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText() == long,
          ),
        )
        .height;

    expect(lineHeight(), lessThan(20)); // one row, scrolling sideways
    await tester.tap(find.byKey(const ValueKey('diff-wrap')));
    await tester.pump();
    expect(tab.app.settings.diffWrap, isTrue);
    expect(lineHeight(), greaterThan(40)); // several rows

    // Let the view's timers (tooltips, scrollbars) run out.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
