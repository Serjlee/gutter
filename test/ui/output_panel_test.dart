import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/ui/repo/output_panel.dart';
import 'package:gutter/ui/repo/repo_tab_controller.dart';

import '../support/temp_repo.dart';

void main() {
  late TempRepo t;
  late AppController app;
  late RepoTabController tab;

  setUp(() async {
    t = await TempRepo.create();
    t.commit('one', {'a.txt': 'a\n'});
    app = AppController(null, Settings());
    tab = RepoTabController(t.repo, app);
  });

  tearDown(() {
    tab.dispose();
    t.dispose();
  });

  testWidgets('a failed command offers its details in the output panel', (
    tester,
  ) async {
    final messages = <AppMessage>[];
    app.messages.listen(messages.add);
    await tester.runAsync(() async {
      await tab.refresh(); // background commands
      await tab.run('Checkout', () => tab.repo.checkout('nope'));
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Column(
            children: [
              const Spacer(),
              ListenableBuilder(
                listenable: tab,
                builder: (_, _) => OutputPanel(tab: tab),
              ),
            ],
          ),
        ),
      ),
    );

    // A readable message, with a way to the full output.
    final m = messages.single;
    expect(m.error, isTrue);
    expect(m.text, startsWith('Checkout failed: '));
    expect(m.text, isNot(contains('GitException')));
    expect(m.onDetails, isNotNull);

    // Collapsed by default: the header shows the last command.
    expect(tab.outputOpen, isFalse);
    expect(find.byType(ListView), findsNothing);
    expect(find.text('git checkout nope'), findsOneWidget);

    // "Details" opens it on the failed command, expanded.
    m.onDetails!();
    await tester.pumpAndSettle();
    expect(tab.outputOpen, isTrue);
    final output = find.byWidgetPredicate(
      (w) => w is SelectableText && (w.data ?? '').contains('nope'),
    );
    expect(output, findsOneWidget);

    // Background refreshes are hidden unless asked for.
    final list = find.byType(ListView);
    expect(
      find.descendant(of: list, matching: find.textContaining('status')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('output-background')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: list, matching: find.textContaining('status')),
      findsWidgets,
    );

    // The header collapses it again.
    await tester.tap(find.byKey(const ValueKey('output-toggle')));
    await tester.pumpAndSettle();
    expect(find.byType(ListView), findsNothing);
  });
}
