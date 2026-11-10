import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/git/repository.dart';
import 'package:gutter/ui/repo/repo_tab_controller.dart';
import 'package:gutter/ui/repo/repo_view.dart';

import '../support/temp_repo.dart';

void main() {
  testWidgets('the Pull menu picks what the button does', (tester) async {
    late TempRepo t;
    late RepoTabController tab;
    await tester.runAsync(() async {
      t = await TempRepo.create();
      t.commit('one', {'a.txt': '1\n'});
      tab = RepoTabController(t.repo, AppController(null, Settings()));
      await tab.load();
    });
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
            listenable: tab.app,
            builder: (_, _) => RepoToolbar(tab: tab, searchFocus: focus),
          ),
        ),
      ),
    );
    expect(find.byTooltip('Pull (fast-forward only)'), findsOneWidget);

    await tester.tap(find.byTooltip('How to pull'));
    await tester.pumpAndSettle();
    // The current one is ticked; picking another pulls nothing.
    expect(find.byIcon(Icons.check), findsOneWidget);
    await tester.tap(find.text('Pull (rebase)'));
    await tester.pumpAndSettle();
    expect(tab.busy, isNull);
    expect(tab.app.settings.pullMode, PullMode.rebase);
    expect(find.byTooltip('Pull (rebase)'), findsOneWidget);

    // Kept.
    final saved = Settings.fromJson(tab.app.settings.toJson());
    expect(saved.pullMode, PullMode.rebase);
    expect(Settings.fromJson({}).pullMode, PullMode.ffOnly);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
