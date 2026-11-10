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
    expect(items, contains('Manage…'));

    // Manage…: the settings, at Apps, where apps are added.
    await tester.tap(find.text('Manage…'));
    await tester.pumpAndSettle();
    expect(
      find.text('Not found: its code command isn\'t installed'),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const ValueKey('add-app')), 'myeditor');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('add-app-confirm')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('add-app')), 'other');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(app.settings.openWithApps, ['myeditor', 'other']);
    // And removed.
    await tester.tap(find.byKey(const ValueKey('remove-app-other')));
    await tester.pump();
    expect(app.settings.openWithApps, ['myeditor']);
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
    expect(tester.getSize(list).height, lessThanOrEqualTo(210));
    expect(
      tester
          .state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)),
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
        'Open in myeditor',
      ]),
    );
    expect(items, isNot(contains('Open in other')));
    await tester.tap(find.text('Open in myeditor'));
    await tester.pumpAndSettle();
    expect(started.single, 'myeditor $repo');
  });

  testWidgets('Open with… in the toolbar lists the apps', (tester) async {
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
    tab.app.vsCode = '/usr/bin/code';
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
          body: RepoToolbar(tab: tab, searchFocus: focus),
        ),
      ),
    );
    // As tall as the search box beside it.
    expect(tester.getSize(find.byKey(const ValueKey('open-with'))).height, 32);

    await tester.tap(find.byKey(const ValueKey('open-with')));
    await tester.pumpAndSettle();
    expect(find.text('Show in the file manager'), findsOneWidget);
    expect(find.text('Ctrl+Shift+O'), findsOneWidget); // its shortcut
    expect(find.text('Manage…'), findsOneWidget);
    await tester.tap(find.text('Open in VS Code'));
    await tester.pumpAndSettle();
    expect(started.single, '/usr/bin/code ${t.path}');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
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
