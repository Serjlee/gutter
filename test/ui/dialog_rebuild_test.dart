import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/ui/dialogs/dialogs.dart';
import 'package:gutter/ui/repo/repo_view.dart';
import 'package:gutter/ui/shell/app_shell.dart';
import 'package:gutter/ui/shell/tab_strip.dart';

import '../support/temp_repo.dart';

void main() {
  testWidgets('opening or closing a dialog rebuilds neither the tab nor the '
      'strip', (tester) async {
    late TempRepo t;
    final app = AppController(null, Settings());
    await tester.runAsync(() async {
      t = await TempRepo.create();
      for (var i = 0; i < 5; i++) {
        t.commit('commit $i', {'f$i.txt': '$i\n'});
      }
      await app.openRepo(t.path);
      final tab = app.activeTab!;
      for (var i = 0; i < 200 && tab.loading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    addTearDown(() {
      debugOnRebuildDirtyWidget = null;
      app.closeTabs(List.of(app.tabs));
      t.dispose();
    });
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: AppShell(app: app),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(RepoView), findsOneWidget);

    var rebuilt = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is RepoView || element.widget is TabStrip) rebuilt++;
    };
    final context = tester.element(find.byType(Scaffold).first);
    unawaited(
      showAppDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: TextField(autofocus: true)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(rebuilt, 0, reason: 'a dialog opened');

    Navigator.of(context).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(AlertDialog), findsNothing);
    expect(rebuilt, 0, reason: 'a dialog closed');
  });
}
