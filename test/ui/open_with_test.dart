import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/open_with.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/ui/repo/repo_tab_controller.dart';
import 'package:gutter/ui/repo/repo_view.dart';
import 'package:gutter/ui/shell/app_shell.dart';
import 'package:gutter/ui/shell/home_tab.dart';

import '../support/temp_repo.dart';

void main() {
  test('VS Code is found on PATH, or where its installers put it', () {
    String? find(Set<String> files, {bool mac = false, bool win = false}) =>
        findVSCode(
          environment: {
            'PATH': win ? r'C:\bin' : '/usr/bin',
            'HOME': '/Users/me',
            'LOCALAPPDATA': r'C:\Users\me\AppData\Local',
          },
          macOS: mac,
          windows: win,
          exists: files.contains,
        );

    expect(find({}), isNull);
    expect(find({'/usr/bin/code'}), '/usr/bin/code');
    expect(find({'/snap/bin/code'}), '/snap/bin/code');
    // From Finder, PATH lacks it: the app bundle has it.
    const bundle =
        '/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code';
    expect(find({bundle}, mac: true), bundle);
    expect(find({bundle}), isNull);
    expect(find({r'C:\bin\code.cmd'}, win: true), r'C:\bin\code.cmd');
    const user =
        r'C:\Users\me\AppData\Local\Programs\Microsoft VS Code\bin'
        r'\code.cmd';
    expect(find({user}, win: true), user);
  });

  test('apps go by their command\'s name', () {
    expect(openWithLabel('subl'), 'subl');
    expect(openWithLabel('/opt/idea/bin/idea.sh'), 'idea.sh');
    expect(openWithLabel('/Applications/Sublime Text.app'), 'Sublime Text');
    expect(openWithLabel(' Sublime Text '), 'Sublime Text');
  });

  testWidgets('a dashboard row opens with the file manager, VS Code when '
      'installed, or the apps added in the settings', (tester) async {
    final started = <String>[];
    final saved = startDetached;
    startDetached = (exe, args, _) async =>
        started.add([exe, ...args].join(' '));
    addTearDown(() => startDetached = saved);
    const repo = '/work/gutter';
    final app = AppController(null, Settings()..knownRepos = [repo])
      ..vsCode = null;
    // Two programs of the user's, in a folder of their own.
    final bin = Directory.systemTemp.createTempSync('gutter_bin_');
    addTearDown(() => bin.deleteSync(recursive: true));
    String program(String name) {
      final f = File('${bin.path}/$name')..writeAsStringSync('#!/bin/sh\n');
      Process.runSync('chmod', ['+x', f.path]);
      return f.path;
    }

    final myeditor = program('myeditor'), other = program('other');
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

    Future<List<String>> menu() async {
      await tester.tap(find.text('gutter').first, buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      return [
        for (final t in tester.widgetList<Text>(
          find.descendant(
            of: find.byType(PopupMenuItem<VoidCallback>),
            matching: find.byType(Text),
          ),
        ))
          t.data!,
      ];
    }

    // No VS Code here, and nothing added yet.
    var items = await menu();
    expect(items, contains('Show in the file manager'));
    expect(items, isNot(contains('Open in VS Code')));
    // Managed in the settings, not from here; and the shortcut is the
    // repository view's.
    expect(items, isNot(contains('Manage…')));
    expect(items, isNot(contains('Ctrl+Shift+O')));
    await tester.tapAt(const Offset(1390, 890)); // closes the menu
    await tester.pumpAndSettle();

    // The settings' Apps, where apps are added.
    await tester.tap(find.byKey(const ValueKey('open-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-tab-apps')));
    await tester.pumpAndSettle();
    expect(
      find.text('Not found: its code command isn\'t installed'),
      findsOneWidget,
    );
    Future<String?> add(String text) async {
      await tester.enterText(find.byKey(const ValueKey('add-app')), text);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('add-app-confirm')));
      await tester.pump();
      final error = find.byKey(const ValueKey('add-app-error'));
      return error.evaluate().isEmpty ? null : tester.widget<Text>(error).data;
    }

    // What can't run isn't added: it says why.
    expect(await add('no-such-editor'), 'No no-such-editor command found');
    expect(await add(bin.path), '${bin.path} is a folder, not a program');
    expect(app.settings.openWithApps, [':files', ':vscode']);
    // Programs are, by path (or on PATH).
    expect(await add(myeditor), isNull);
    await tester.enterText(find.byKey(const ValueKey('add-app')), other);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(app.settings.openWithApps, [':files', ':vscode', myeditor, other]);
    // And removed.
    await tester.tap(find.byKey(ValueKey('remove-app-$other')));
    await tester.pump();
    expect(app.settings.openWithApps, [':files', ':vscode', myeditor]);
    // Named, and given an icon, by its row.
    await tester.enterText(
      find.byKey(ValueKey('app-name-$myeditor')),
      'My Editor',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(app.settings.openWithNames, {myeditor: 'My Editor'});
    await tester.tap(find.byKey(ValueKey('app-icon-$myeditor')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('icon-choice-bolt')));
    await tester.pumpAndSettle();
    expect(app.settings.openWithIcons, {myeditor: 'bolt'});
    // Shown in the toolbar, unless unticked.
    await tester.tap(find.byKey(ValueKey('app-show-$myeditor')));
    await tester.pump();
    expect(app.settings.openWithHidden, [myeditor]);
    await tester.tap(find.byKey(ValueKey('app-show-$myeditor')));
    await tester.pump();
    expect(app.settings.openWithHidden, isEmpty);
    // Installed apps are suggested by name, and added as such.
    app.installedApps = Future.value(const [
      InstalledApp(id: '/Applications/Sublime Text.app', name: 'Sublime Text'),
      InstalledApp(
        id: '/Applications/Sublime Merge.app',
        name: 'Sublime Merge',
      ),
    ]);
    await tester.tap(find.byKey(const ValueKey('settings-tab-git')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('settings-tab-apps')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('add-app')), 'text');
    await tester.pump();
    expect(find.text('Sublime Text'), findsOneWidget);
    expect(find.text('Sublime Merge'), findsNothing);
    await tester.tap(find.text('Sublime Text'));
    await tester.pump();
    expect(app.settings.openWithApps.last, '/Applications/Sublime Text.app');
    // Typed out in full, Enter adds the app too.
    await tester.enterText(
      find.byKey(const ValueKey('add-app')),
      'sublime merge',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(app.settings.openWithApps.last, '/Applications/Sublime Merge.app');
    app.removeOpenWithApp('/Applications/Sublime Text.app');
    app.removeOpenWithApp('/Applications/Sublime Merge.app');
    await tester.pump();

    // Many: they scroll, in a list of their own.
    for (var i = 0; i < 9; i++) {
      app.addOpenWithApp('app$i');
    }
    await tester.pump();
    final list = find.byKey(const ValueKey('app-list'));
    expect(tester.getSize(list).height, lessThanOrEqualTo(230));
    expect(
      tester
          .state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)).first,
          )
          .position
          .maxScrollExtent,
      greaterThan(0),
    );
    for (var i = 0; i < 9; i++) {
      app.removeOpenWithApp('app$i');
    }
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('settings-close')));
    await tester.pumpAndSettle();

    // Listed, with VS Code once installed; a pick opens the repository.
    app.vsCode = '/usr/bin/code';
    items = await menu();
    expect(
      items,
      containsAll([
        'Show in the file manager',
        'Open in VS Code',
        'Open in My Editor',
      ]),
    );
    expect(items, isNot(contains('Open in other')));
    await tester.tap(find.text('Open in My Editor'));
    await tester.pumpAndSettle();
    expect(started.single, '$myeditor $repo');
  });

  testWidgets('the toolbar: the file manager, and each app shown', (
    tester,
  ) async {
    final started = <String>[];
    final saved = startDetached;
    startDetached = (exe, args, _) async =>
        started.add([exe, ...args].join(' '));
    addTearDown(() => startDetached = saved);
    late TempRepo t;
    late RepoTabController tab;
    await tester.runAsync(() async {
      t = await TempRepo.create();
      t.commit('one', {'a.txt': '1\n'});
      tab = RepoTabController(t.repo, AppController(null, Settings()));
      await tab.load();
    });
    final app = tab.app
      ..vsCode = '/usr/bin/code'
      ..addOpenWithApp('alpha')
      ..addOpenWithApp('beta')
      ..addOpenWithApp('gamma')
      ..setOpenWithShown('beta', false);
    final focus = FocusNode();
    addTearDown(() {
      focus.dispose();
      tab.dispose();
      t.dispose();
    });
    tester.view.physicalSize = const Size(1400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: app,
            builder: (_, _) => RepoToolbar(tab: tab, searchFocus: focus),
          ),
        ),
      ),
    );
    // As tall as the search box beside them.
    expect(
      tester.getSize(find.byKey(const ValueKey('open-:files'))).height,
      32,
    );
    List<String> buttons() => [
      for (final t in tester.widgetList<Tooltip>(
        find.descendant(
          of: find.byType(RepoToolbar),
          matching: find.byType(Tooltip),
        ),
      ))
        if (t.message case final String m when m.contains(' in ')) m,
    ];
    // VS Code, found, by default; beta not shown.
    expect(buttons(), [
      'Show in the file manager (Ctrl+Shift+O)',
      'Open in VS Code',
      'Open in alpha',
      'Open in gamma',
    ]);
    await tester.tap(find.byTooltip('Open in gamma'));
    await tester.pump();
    expect(started.single, 'gamma ${t.path}');

    // A PNG of the user's as its icon; gone, its own again.
    final png = File('${t.path}/../icon.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
        ),
      );
    addTearDown(() {
      if (png.existsSync()) png.deleteSync();
    });
    app.setOpenWithIcon('gamma', 'file:${png.path}');
    await tester.pump();
    Finder gammaImage() => find.descendant(
      of: find.byTooltip('Open in gamma'),
      matching: find.byType(Image),
    );
    expect(gammaImage(), findsOneWidget);
    png.deleteSync();
    app.setOpenWithIcon('gamma', 'file:${png.path}');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(
      find.descendant(
        of: find.byTooltip('Open in gamma'),
        matching: find.byIcon(Icons.terminal),
      ),
      findsOneWidget,
    );
    app.setOpenWithIcon('gamma', null);

    // Named, and moved first: its button, by its name, first.
    app
      ..setOpenWithName('gamma', 'Gamma Editor')
      ..moveOpenWithApp(4, 0);
    await tester.pump();
    expect(app.openWithIds, ['gamma', ':files', ':vscode', 'alpha', 'beta']);
    expect(buttons().sublist(0, 3), [
      'Open in Gamma Editor',
      'Show in the file manager (Ctrl+Shift+O)',
      'Open in VS Code',
    ]);
    // Its own name again, when cleared.
    app.setOpenWithName('gamma', '');
    expect(app.settings.openWithNames, isEmpty);
    // The file manager can go too.
    app.setOpenWithShown(':files', false);
    await tester.pump();
    expect(buttons(), isNot(contains(startsWith('Show in'))));

    // Without VS Code, it has no button, and keeps its place for later.
    app.vsCode = null;
    expect(app.openWithIds, ['gamma', ':files', 'alpha', 'beta']);
    app.moveOpenWithApp(0, 4);
    expect(app.settings.openWithApps, [
      ':files',
      ':vscode',
      'alpha',
      'beta',
      'gamma',
    ]);
    // Removed, it's not hidden any more either.
    app.removeOpenWithApp('beta');
    expect(app.settings.openWithHidden, [':files']);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  test('saved: apps\' order, names and icons; VS Code among them', () {
    final s = Settings()
      ..openWithApps = ['subl', ':vscode']
      ..openWithNames = {'subl': 'Sublime'}
      ..openWithIcons = {'subl': 'bolt'};
    s.openWithHidden = ['subl'];
    final back = Settings.fromJson(s.toJson());
    // (The file manager among them, first, as it wasn't.)
    expect(back.openWithApps, [':files', 'subl', ':vscode']);
    expect(back.openWithHidden, ['subl']);
    expect(back.openWithNames, {'subl': 'Sublime'});
    expect(back.openWithIcons, {'subl': 'bolt'});
    // From before: the file manager and VS Code first.
    expect(
      Settings.fromJson({
        'openWithApps': ['subl'],
      }).openWithApps,
      [':files', ':vscode', 'subl'],
    );
    expect(Settings.fromJson({}).openWithApps, [':files', ':vscode']);
  });

  testWidgets('Ctrl+Shift+O shows the repository in the file manager', (
    tester,
  ) async {
    final started = <String>[];
    final saved = startDetached;
    startDetached = (exe, args, _) async =>
        started.add([exe, ...args].join(' '));
    addTearDown(() => startDetached = saved);
    late TempRepo t;
    final app = AppController(null, Settings());
    await tester.runAsync(() async {
      t = await TempRepo.create();
      t.commit('one', {'a.txt': '1\n'});
      await app.openRepo(t.path);
    });
    addTearDown(t.dispose);
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: AppShell(app: app),
      ),
    );
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(started.single, 'xdg-open ${t.path}');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });
}
