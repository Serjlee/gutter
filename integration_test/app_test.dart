// End-to-end smoke test of the real app. Run it AOT-compiled so release-only
// miscompilations surface:
//   xvfb-run flutter drive --profile -d linux \
//     --driver test_driver/integration_test.dart \
//     --target integration_test/app_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/app/zoom.dart';
import 'package:gutter/ui/shell/app_shell.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

String git(String dir, List<String> args) {
  final r = Process.runSync('git', [
    '-c',
    'user.name=Test',
    '-c',
    'user.email=test@example.com',
    ...args,
  ], workingDirectory: dir);
  if (r.exitCode != 0) throw StateError('git $args: ${r.stderr}');
  return r.stdout as String;
}

/// Pumps frames until [done] holds, then one more so the UI reflects it.
Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(done(), isTrue);
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('dirty repository: staging panel, refreshes, focus changes', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('gutter_it_').path;
    addTearDown(() => Directory(dir).deleteSync(recursive: true));
    git(dir, ['init', '-q', '-b', 'main']);
    File(p.join(dir, 'a.txt')).writeAsStringSync('a\n');
    git(dir, ['add', '.']);
    git(dir, ['commit', '-qm', 'first']);
    git(dir, ['checkout', '-qb', 'side']);
    File(p.join(dir, 'b.txt')).writeAsStringSync('b\n');
    git(dir, ['add', '.']);
    git(dir, ['commit', '-qm', 'side work']);
    git(dir, ['checkout', '-q', 'main']);
    // A mix of untracked, modified and staged files.
    for (var i = 0; i < 40; i++) {
      File(p.join(dir, 'new$i.txt')).writeAsStringSync('$i\n');
    }
    File(p.join(dir, 'a.txt')).writeAsStringSync('a\nchanged\n');
    git(dir, ['add', 'new0.txt', 'new1.txt']);

    final app = AppController(null, Settings());
    // Tear-downs run in reverse: stop the tabs before deleting the repo.
    addTearDown(() {
      for (var i = app.tabs.length - 1; i >= 0; i--) {
        app.closeTab(i);
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        builder: (context, child) => ListenableBuilder(
          listenable: app,
          builder: (context, _) => ZoomScope(
            zoom: app.zoom,
            onZoomChanged: app.setZoom,
            child: child!,
          ),
        ),
        home: AppShell(app: app),
      ),
    );
    expect(await app.openRepo(dir), isTrue);
    final tab = app.activeTab!;
    await pumpUntil(tester, () => !tab.loading && tab.graph.hasWip);

    // The WIP panel shows the staging area.
    expect(find.text('UNSTAGED FILES'), findsOneWidget);
    // The list is lazy: the staged section is further down.
    expect(tab.status.staged.map((e) => e.path).toSet(), {
      'new0.txt',
      'new1.txt',
    });
    expect(find.text('a.txt'), findsWidgets);

    // Flip clean <-> dirty a few times, with focus changes in between
    // (re-focus refreshes the active tab).
    for (var round = 0; round < 3; round++) {
      git(dir, ['stash', 'push', '-q', '-u']);
      app.setFocused(false);
      app.setFocused(true);
      await tab.refresh();
      await pumpUntil(tester, () => !tab.graph.hasWip);
      expect(find.text('UNSTAGED FILES'), findsNothing);

      git(dir, ['stash', 'pop', '-q', '--index']);
      app.setFocused(false);
      app.setFocused(true);
      await tab.refresh();
      await pumpUntil(tester, () => tab.graph.hasWip);
      expect(find.text('UNSTAGED FILES'), findsOneWidget);
    }

    // Commit details and a diff.
    await tester.tap(find.text('side work'));
    await pumpUntil(tester, () => tab.details?.subject == 'side work');
    expect(find.text('1 CHANGED FILES'), findsOneWidget);
    await tester.tap(find.text('b.txt').last);
    await pumpUntil(tester, () => tab.diff != null);
    expect(find.text('Unified'), findsOneWidget);

    // Zoom renders the whole shell at another scale.
    app.setZoom(1.5);
    await tester.pump(const Duration(milliseconds: 100));
    app.setZoom(1.0);
    await tester.pump(const Duration(seconds: 2));

    app.closeTab(0);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
