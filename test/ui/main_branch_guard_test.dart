import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/ui/repo/repo_actions.dart';
import 'package:gutter/ui/repo/repo_tab_controller.dart';
import 'package:gutter/ui/shell/home_tab.dart';
import 'package:path/path.dart' as p;

import '../support/temp_repo.dart';

void main() {
  testWidgets('committing or pushing to main asks first, unless told not to', (
    tester,
  ) async {
    late TempRepo t;
    late Directory remote;
    late RepoTabController tab;
    await tester.runAsync(() async {
      t = await TempRepo.create();
      t.commit('one', {'a.txt': '1\n'});
      remote = await Directory.systemTemp.createTemp('gutter_remote_');
      Process.runSync('git', ['init', '-q', '--bare', remote.path]);
      t.git(['remote', 'add', 'origin', remote.path]);
      t.git(['push', '-q', '-u', 'origin', 'main']);
      tab = RepoTabController(t.repo, AppController(null, Settings()));
      await tab.load();
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
    final actions = RepoActions(context, tab);

    /// Lets git answer, then shows what it said.
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 30));
      }
    }

    Future<void> stage(String content) async {
      await tester.runAsync(() async {
        t.write('a.txt', content);
        t.git(['add', 'a.txt']);
        await tab.refresh();
      });
      tab.commitMessage.text = 'change $content';
    }

    String remoteMain() =>
        (Process.runSync('git', ['-C', remote.path, 'rev-parse', 'main']).stdout
                as String)
            .trim();

    // Commit on main: asked; cancelled, nothing is committed.
    await stage('2\n');
    unawaited(actions.commit());
    await tester.pumpAndSettle();
    expect(find.text('Commit to main?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle();
    expect(t.subjects(), ['one']);

    // Confirmed, it is.
    unawaited(actions.commit());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Commit to main'));
    await settle();
    expect(t.subjects(), ['change 2', 'one']);

    // Push to main: asked too; cancelled, nothing is pushed.
    final before = remoteMain();
    unawaited(actions.push());
    await tester.pumpAndSettle();
    expect(find.text('Push to main?'), findsOneWidget);
    expect(find.textContaining('(origin/main)'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle();
    expect(remoteMain(), before);

    // "Don't ask again": confirmed, and not asked again in this repository.
    unawaited(actions.push());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('opt-out')));
    await tester.pump();
    await tester.tap(find.text('Push to main'));
    await settle();
    expect(remoteMain(), t.git(['rev-parse', 'main']).trim());
    expect(tab.app.settings.mainBranchUnguarded, [t.path]);
    await stage('3\n');
    unawaited(actions.commit());
    await settle();
    expect(find.text('Commit to main?'), findsNothing);
    expect(t.subjects().first, 'change 3');

    // Other branches are never asked about.
    tab.app.settings.mainBranchUnguarded = [];
    await tester.runAsync(() async {
      t.git(['checkout', '-q', '-b', 'feature']);
      await tab.refresh();
    });
    await stage('4\n');
    unawaited(actions.commit());
    await settle();
    expect(find.text('Commit to feature?'), findsNothing);
    expect(t.subjects().first, 'change 4');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('the home tab turns the question back on, repository by '
      'repository', (tester) async {
    late TempRepo quiet, asking;
    await tester.runAsync(() async {
      quiet = await TempRepo.create();
      asking = await TempRepo.create();
    });
    addTearDown(() {
      quiet.dispose();
      asking.dispose();
    });
    final app = AppController(
      null,
      Settings()
        ..knownRepos = [quiet.path, asking.path]
        ..mainBranchUnguarded = [quiet.path],
    );
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: app,
            builder: (_, _) => HomeTab(app: app),
          ),
        ),
      ),
    );
    await tester.pump();
    const item = 'Ask again before committing to main';

    Future<void> openMenu(TempRepo t) async {
      await tester.tap(
        find.text(p.basename(t.path)).first,
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
    }

    await openMenu(asking);
    expect(find.text(item), findsNothing);
    await tester.tapAt(const Offset(1390, 890)); // closes it
    await tester.pumpAndSettle();

    await openMenu(quiet);
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
    expect(app.settings.mainBranchUnguarded, isEmpty);
  });
}
