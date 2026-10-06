import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/ui/shell/git_missing_banner.dart';

void main() {
  test('a git that doesn\'t run is a problem, until it does', () async {
    final app = AppController(
      null,
      Settings()..gitPath = '/nonexistent/bin/git',
    );
    await app.checkGit();
    expect(app.gitVersion, isNull);
    expect(app.gitProblem, contains('/nonexistent/bin/git'));

    // Back to looking for git: this machine's.
    app.setGitPath(null);
    await app.checkGit();
    expect(app.gitProblem, isNull);
    expect(app.gitVersion, startsWith('git version'));
  });

  testWidgets('the banner says how to get git, and checks again', (
    tester,
  ) async {
    final app = AppController(null, Settings());
    Future<void> show(String platform) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: app,
              builder: (_, _) => GitMissingBanner(
                key: ValueKey(platform),
                app: app,
                platform: platform,
              ),
            ),
          ),
        ),
      );
    }

    // Fine: nothing shown.
    await show('windows');
    expect(find.byKey(const ValueKey('git-missing')), findsNothing);

    app.gitProblem = 'Gutter can\'t find git.';
    await show('windows');
    expect(find.text('Git isn\'t installed'), findsOneWidget);
    expect(find.text('Install Git'), findsOneWidget);
    expect(find.textContaining('Git for Windows'), findsOneWidget);

    await show('macos');
    expect(find.text('Install command line tools'), findsOneWidget);

    await show('linux');
    expect(find.byKey(const ValueKey('git-install')), findsNothing);
    expect(find.textContaining('sudo apt install git'), findsOneWidget);

    // Something else wrong with git: its reason.
    app.gitProblem = 'The git at /usr/bin/git needs Apple\'s tools.';
    await show('macos');
    expect(find.text('Gutter can\'t run git'), findsOneWidget);
    expect(find.textContaining('Apple\'s tools'), findsOneWidget);

    // Check again: this machine has git.
    await tester.tap(find.byKey(const ValueKey('git-check')));
    for (var i = 0; i < 50 && app.gitProblem != null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump();
    expect(app.gitProblem, isNull);
    expect(find.byKey(const ValueKey('git-missing')), findsNothing);
  });
}
