import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/ui/repo/repo_actions.dart';
import 'package:gutter/ui/shell/app_shell.dart';

import '../support/temp_repo.dart';

void main() {
  testWidgets('checking out a diverged remote branch offers to reset to it, '
      'stashing uncommitted work', (tester) async {
    late TempRepo t;
    late String remoteSha, localSha;
    final app = AppController(null, Settings());
    await tester.runAsync(() async {
      t = await TempRepo.create();
      final a = t.commit('a', {'a.txt': 'a\n'});
      // The remote's side was rewritten (a force push): b there, c here.
      remoteSha = t.commit('b', {'a.txt': 'b\n'});
      t.git(['checkout', '-q', '-b', 'side', a]);
      localSha = t.commit('c', {'c.txt': 'c\n'});
      // Working on side when origin/side was rewritten (just fetched).
      t.git(['remote', 'add', 'origin', '/nonexistent/origin.git']);
      t.git(['update-ref', 'refs/remotes/origin/side', remoteSha]);
      t.write('a.txt', 'work in progress\n');
      await app.openRepo(t.path);
      final tab = app.activeTab!;
      for (var i = 0; i < 200 && tab.loading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    addTearDown(() {
      app.closeTabs(List.of(app.tabs));
      t.dispose();
    });
    final tab = app.activeTab!;
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: AppShell(app: app),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    /// Lets git answer, then shows what it said.
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    String head() => t.git(['rev-parse', 'HEAD']).trim();
    Future<void> checkout() async {
      final remote = tab.refs.firstWhere((r) => r.name == 'origin/side');
      final context = tester.element(find.byType(AppShell));
      // Not awaited: it waits for the dialog's answer.
      unawaited(RepoActions(context, tab).checkoutRef(remote));
      await settle();
    }

    // Kept: side stays as it was, the work too.
    await checkout();
    expect(find.text('side and origin/side have diverged'), findsOneWidget);
    expect(
      find.textContaining('side has 1 commit that origin/side doesn\'t'),
      findsOneWidget,
    );
    expect(find.textContaining('Reset side to origin/side?'), findsOneWidget);
    await tester.tap(find.text('Keep side'));
    await settle();
    expect(t.git(['branch', '--show-current']).trim(), 'side');
    expect(head(), localSha);
    expect(t.read('a.txt'), 'work in progress\n');

    // Reset: side is origin/side's, the work is in the stash.
    await checkout();
    await tester.tap(find.text('Reset to origin/side'));
    await settle();
    expect(head(), remoteSha);
    expect(t.git(['status', '--porcelain']).trim(), isEmpty);
    expect(
      t.git(['stash', 'list']),
      contains('Before resetting side to origin/side'),
    );

    // Stops the tab's timers, and lets the views' ones run out.
    app.closeTabs(List.of(app.tabs));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
