import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/ui/graph_view/commit_graph_view.dart';
import 'package:gutter/ui/repo/repo_tab_controller.dart';
import 'package:gutter/ui/shell/home_tab.dart';

import '../support/temp_repo.dart';

void main() {
  // The palette is global: leave it dark for the other tests.
  tearDown(() => AppColors.current = AppPalette.dark);

  test('the theme setting is saved, unknown values meaning system', () {
    final s = Settings()..themeMode = 'light';
    expect(Settings.fromJson(s.toJson()).themeMode, 'light');
    expect(Settings.fromJson({'themeMode': 'sepia'}).themeMode, 'system');
    expect(Settings.fromJson({}).themeMode, 'system');
  });

  test('picks the palette: the setting, else the OS', () {
    final app = AppController(null, Settings());
    expect(app.paletteFor(Brightness.light), AppPalette.light);
    expect(app.paletteFor(Brightness.dark), AppPalette.dark);
    app.setThemeMode('dark');
    expect(app.paletteFor(Brightness.light), AppPalette.dark);
    app.setThemeMode('light');
    expect(app.paletteFor(Brightness.dark), AppPalette.light);
  });

  test('AppColors follows the active palette', () {
    AppColors.current = AppPalette.light;
    expect(AppColors.background, AppPalette.light.background);
    expect(buildTheme().brightness, Brightness.light);
    expect(AppColors.lane(1), AppPalette.light.lanes[1]);
    AppColors.current = AppPalette.dark;
    expect(AppColors.background, AppPalette.dark.background);
    expect(buildTheme().brightness, Brightness.dark);
  });

  testWidgets('the graph and home tab render in light', (tester) async {
    AppColors.current = AppPalette.light;
    late TempRepo t;
    late RepoTabController tab;
    await tester.runAsync(() async {
      t = await TempRepo.create();
      t.commit('one', {'a.txt': '1\n'});
      t.git(['checkout', '-q', '-b', 'feature']);
      t.commit('two', {'a.txt': '2\n'});
      tab = RepoTabController(t.repo, AppController(null, Settings()));
      await tab.load();
    });
    addTearDown(() {
      tab.dispose();
      t.dispose();
    });
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: CommitGraphView(tab: tab)),
      ),
    );
    await tester.pump();
    // Labels take dark text on the light background.
    final label = tester.widget<Text>(find.text('feature'));
    expect(label.style!.color, AppPalette.light.pillText);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: HomeTab(app: tab.app)),
      ),
    );
    await tester.pump();
    expect(find.text('Light'), findsNothing); // the setting says System
    expect(find.text('System'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
