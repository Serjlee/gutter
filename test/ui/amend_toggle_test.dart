import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/ui/details/details_panel.dart';
import 'package:gutter/ui/repo/repo_actions.dart';
import 'package:gutter/ui/repo/repo_tab_controller.dart';

import '../support/temp_repo.dart';

void main() {
  testWidgets('"Amend previous commit" toggles from its label too', (
    tester,
  ) async {
    late TempRepo t;
    late RepoTabController tab;
    await tester.runAsync(() async {
      t = await TempRepo.create();
      t.commit('one', {'a.txt': '1\n'});
      t.write('a.txt', 'dirty\n');
      tab = RepoTabController(t.repo, AppController(null, Settings()));
      await tab.load();
    });
    addTearDown(() {
      tab.dispose();
      t.dispose();
    });
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: tab,
            builder: (_, _) => WipPanel(tab: tab),
          ),
        ),
      ),
    );
    await tester.pump();

    Future<void> tapLabel() async {
      await tester.tap(find.text('Amend previous commit'));
      // Amending fetches the last message from git.
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
      }
    }

    await tapLabel();
    expect(tab.amend, isTrue);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    await tapLabel();
    expect(tab.amend, isFalse);

    // Ticked, it brings the last message; unticked, takes it back, unless
    // edited. (Git answers outside the test's clock.)
    await tester.runAsync(() => tab.setAmend(true));
    expect(tab.commitMessage.text.trim(), 'one');
    await tester.runAsync(() => tab.setAmend(false));
    expect(tab.commitMessage.text, isEmpty);
    await tester.runAsync(() => tab.setAmend(true));
    tab.commitMessage.text = 'one, reworded';
    await tester.runAsync(() => tab.setAmend(false));
    expect(tab.commitMessage.text, 'one, reworded');
    tab.commitMessage.clear();
    await tester.pump();
    // The box itself still works.
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(tab.amend, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('amending a pushed commit asks first', (tester) async {
    late TempRepo t;
    late Directory remote;
    late RepoTabController tab;
    await tester.runAsync(() async {
      t = await TempRepo.create();
      t.commit('one', {'a.txt': '1\n'});
      remote = await Directory.systemTemp.createTemp('gutter_remote_');
      Process.runSync('git', ['init', '-q', '--bare', remote.path]);
      t.git(['remote', 'add', 'origin', remote.path]);
      t.git(['checkout', '-q', '-b', 'feature']);
      t.commit('two', {'a.txt': '2\n'});
      t.git(['push', '-q', '-u', 'origin', 'feature']);
      t.write('a.txt', '3\n');
      t.git(['add', 'a.txt']);
      tab = RepoTabController(t.repo, AppController(null, Settings()));
      await tab.load();
      await tab.setAmend(true);
    });
    addTearDown(() {
      tab.dispose();
      t.dispose();
      remote.deleteSync(recursive: true);
    });
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    /// Lets git answer, then shows what it said.
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 30));
      }
    }

    final pushed = t.git(['rev-parse', 'HEAD']).trim();
    unawaited(RepoActions(context, tab).commit());
    await settle();
    expect(find.text('Amend a pushed commit?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle();
    expect(t.git(['rev-parse', 'HEAD']).trim(), pushed);

    unawaited(RepoActions(context, tab).commit());
    await settle();
    await tester.tap(find.text('Amend'));
    await settle();
    expect(t.git(['rev-parse', 'HEAD']).trim(), isNot(pushed));
    expect(t.subjects(), ['two', 'one']);

    // Not pushed any more (amended), it doesn't ask.
    await tester.runAsync(() async {
      t.write('a.txt', '4\n');
      t.git(['add', 'a.txt']);
      await tab.refresh();
      await tab.setAmend(true);
    });
    unawaited(RepoActions(context, tab).commit());
    await settle();
    expect(find.text('Amend a pushed commit?'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
