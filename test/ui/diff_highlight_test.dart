import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/ui/diff/diff_view.dart';
import 'package:gutter/ui/diff/syntax.dart';
import 'package:gutter/ui/repo/repo_tab_controller.dart';

import '../support/temp_repo.dart';

void main() {
  testWidgets('diff lines are highlighted as in their whole file', (
    tester,
  ) async {
    // A change near the end of a long multi-line string: the hunk doesn't
    // include its opening quotes, so on its own it would read the closing
    // ones as an opening, and the code after them as a string.
    const quotes = "'''";
    String code(String value) => [
      'const doc = $quotes',
      for (var i = 0; i < 12; i++) 'text $i',
      'value $value',
      '$quotes;',
      'void f() => print(doc);',
      '',
    ].join('\n');
    const line = 'void f() => print(doc);';

    late TempRepo t;
    late RepoTabController tab;
    await tester.runAsync(() async {
      t = await TempRepo.create();
      t.commit('one', {'a.dart': code('1')});
      t.commit('two', {'a.dart': code('2')});
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
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: DiffView(tab: tab)),
      ),
    );

    final expected = highlightLines(
      code('2'),
      'dart',
    )!.firstWhere((l) => l.map((s) => s.text).join() == line);
    expect(expected.length, greaterThan(1)); // keyword, name…: not a string
    String colors(List<InlineSpan> spans) =>
        spans.map((s) => (s as TextSpan).style?.color?.toARGB32()).join(',');
    List<InlineSpan>? shown() {
      for (final e in find.byType(RichText).evaluate()) {
        final text = (e.widget as RichText).text;
        if (text.toPlainText() != line) continue;
        // Text.rich > the line's span > its highlight spans.
        final lineSpan = (text as TextSpan).children!.single as TextSpan;
        return lineSpan.children;
      }
      return null;
    }

    for (var i = 0; i < 100; i++) {
      final s = shown();
      if (s != null && colors(s) == colors(expected)) break;
      // Real git runs (the file's two versions load) while fake time
      // advances for the timers waiting on them.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(colors(shown()!), colors(expected));

    // Let the view's timers (tooltips, scrollbars) run out.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
