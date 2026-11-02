import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/ui/details/details_panel.dart';
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
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
    }

    await tapLabel();
    expect(tab.amend, isTrue);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    await tapLabel();
    expect(tab.amend, isFalse);
    // The box itself still works.
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(tab.amend, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
