// End-to-end smoke test of the real app. Run it AOT-compiled so release-only
// miscompilations surface:
//   xvfb-run flutter drive --profile -d linux \
//     --driver test_driver/integration_test.dart \
//     --target integration_test/app_test.dart
import 'dart:io';

import 'package:flutter/gestures.dart';
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

/// Fails with the full diagnostics if a frame reported an error (e.g. a
/// layout overflow) since the last call.
void expectNoErrors(WidgetTester tester, String step) {
  final e = tester.takeException();
  if (e != null) {
    fail('$step: ${e is FlutterError ? e.toStringDeep() : e}');
  }
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
    // Code with a very long line, for split view and highlighting.
    File(p.join(dir, 'b.dart')).writeAsStringSync(
      '/* A block comment\n   spanning lines */\n'
      'void main() {\n'
      '  final s = "${'long ' * 80}";\n'
      '  print(s);\n'
      '}\n',
    );
    git(dir, ['add', '.']);
    git(dir, ['commit', '-qm', 'side work']);
    git(dir, ['checkout', '-q', 'main']);
    // A mix of untracked, modified and staged files.
    for (var i = 0; i < 40; i++) {
      File(p.join(dir, 'new$i.txt')).writeAsStringSync('$i\n');
    }
    for (final f in ['src/app/x.dart', 'src/app/y.dart', 'docs/guide.md']) {
      File(p.join(dir, f))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('$f\n');
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

    // Tree view: folders (compacted), collapse, stage a whole folder.
    await tester.tap(find.byKey(const ValueKey('file-view-toggle')));
    await tester.pump();
    expect(app.settings.fileTree, isTrue);
    expect(find.text('src/app'), findsOneWidget);
    expect(find.text('docs'), findsOneWidget);
    expect(find.text('x.dart'), findsOneWidget);
    await tester.tap(find.text('src/app'));
    await tester.pump();
    expect(find.text('x.dart'), findsNothing);
    await tester.tap(find.text('src/app'));
    await tester.pump();
    expect(find.text('x.dart'), findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('docs')));
    await tester.pump();
    await tester.tap(find.byTooltip('Stage folder'));
    await pumpUntil(
      tester,
      () => tab.status.staged.any((e) => e.path == 'docs/guide.md'),
    );
    expect(tab.status.unstaged.any((e) => e.path.startsWith('docs/')), isFalse);

    await tester.tap(find.byKey(const ValueKey('file-view-toggle')));
    await tester.pump();
    expect(app.settings.fileTree, isFalse);
    git(dir, ['reset', '-q', 'docs']);

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
    await tester.tap(find.text('b.dart').last);
    await pumpUntil(tester, () => tab.diff != null);
    expect(find.text('Unified'), findsOneWidget);

    // Split view with syntax highlighting, then zoomed in so the pane is
    // narrow: nothing may overflow (layout errors fail the test).
    expectNoErrors(tester, 'unified diff');
    await tester.tap(find.text('Split'));
    await tester.pump();
    expectNoErrors(tester, 'split view');
    await tester.tap(find.byKey(const ValueKey('syntax-toggle')));
    await tester.pump();
    expect(app.settings.syntaxHighlight, isTrue);
    expect(find.textContaining('print(s);', findRichText: true), findsWidgets);
    expectNoErrors(tester, 'split view, highlighted');
    for (final zoom in [1.5, 2.0, 1.0]) {
      app.setZoom(zoom);
      await tester.pump(const Duration(milliseconds: 100));
      expectNoErrors(tester, 'split view at zoom $zoom');
    }
    await tester.tap(find.text('File'));
    await tester.pump(const Duration(milliseconds: 300));
    expectNoErrors(tester, 'file view');
    expect(find.textContaining('print(s);', findRichText: true), findsWidgets);
    await tester.tap(find.text('Unified'));
    await tester.pump(const Duration(seconds: 2));

    app.closeTab(0);
    await tester.pump();
    expectNoErrors(tester, 'end');
  });
}
