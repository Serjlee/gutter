import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/ui/repo/repo_actions.dart';
import 'package:gutter/ui/repo/repo_tab_controller.dart';
import 'package:gutter/ui/widgets/common.dart';

import '../support/temp_repo.dart';

void main() {
  testWidgets('commits already in HEAD offer no merge, rebase or pick', (
    tester,
  ) async {
    late TempRepo t;
    late RepoTabController tab;
    await tester.runAsync(() async {
      t = await TempRepo.create();
      t.commit('one', {'a.txt': '1\n'});
      t.git(['checkout', '-q', '-b', 'side']);
      t.commit('side work', {'b.txt': '1\n'});
      t.git(['checkout', '-q', 'main']);
      t.commit('two', {'a.txt': '2\n'});
      tab = RepoTabController(t.repo, AppController(null, Settings()));
      await tab.load();
    });
    addTearDown(() {
      tab.dispose();
      t.dispose();
    });
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );

    /// The labels of the commit menu of [subject], opened as the graph
    /// does it.
    Future<List<String>> menu(String subject) async {
      final c = tab.graph.history.firstWhere((c) => c.subject == subject);
      unawaited(
        showContextMenu(
          context,
          const Offset(10, 10),
          RepoActions(context, tab).commitMenu(c),
        ),
      );
      await tester.pumpAndSettle();
      final labels = [
        for (final e in find.byType(Text).evaluate())
          (e.widget as Text).data ?? '',
      ];
      await tester.tapAt(const Offset(790, 590)); // dismisses it
      await tester.pumpAndSettle();
      return labels;
    }

    for (final subject in ['two', 'one']) {
      final labels = await menu(subject);
      expect(labels, contains('Create branch here'), reason: subject);
      expect(labels, isNot(contains('Merge into main')), reason: subject);
      expect(labels, isNot(contains('Rebase main onto this')), reason: subject);
      expect(labels, isNot(contains('Cherry-pick commit')), reason: subject);
    }
    final side = await menu('side work');
    expect(side, contains('Merge into main'));
    expect(side, contains('Rebase main onto this'));
    expect(side, contains('Cherry-pick commit'));
  });
}
