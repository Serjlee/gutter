import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/app/update_checker.dart';
import 'package:gutter/app/updater.dart';
import 'package:gutter/app/version.dart';
import 'package:gutter/ui/dialogs/update_dialog.dart';
import 'package:gutter/ui/shell/app_shell.dart';
import 'package:gutter/ui/shell/home_tab.dart';

const release = ReleaseInfo(
  tag: 'v0.2.0',
  url: 'https://github.com/serjlee/gutter/releases/tag/v0.2.0',
  publishedAt: null,
);

void main() {
  test('compareVersions', () {
    expect(compareVersions('v0.2.0', '0.1.9'), greaterThan(0));
    expect(compareVersions('1.2.10', 'v1.2.9'), greaterThan(0));
    expect(compareVersions('1.2', '1.2.0'), 0);
    expect(compareVersions('v1.0.0-beta', '1.0.0'), 0);
    expect(compareVersions('0.1.0', '0.10.0'), lessThan(0));
  });

  test('version labels', () {
    expect(
      const AppVersion(version: '0.1.0', commit: 'abc1234').label,
      'v0.1.0 (abc1234)',
    );
    expect(const AppVersion(version: '0.1.0').label, 'v0.1.0');
    expect(const AppVersion(commit: 'abc1234').label, 'dev abc1234');
    expect(const AppVersion().label, 'unknown version');
  });

  test('parses the GitHub latest-release payload', () {
    final r = ReleaseInfo.fromGitHubJson({
      'tag_name': 'v1.2.3',
      'html_url': 'https://github.com/serjlee/gutter/releases/tag/v1.2.3',
      'published_at': '2026-09-24T10:00:00Z',
      'name': 'Gutter v1.2.3',
      'body': 'What\'s new',
      'assets': [
        {
          'name': 'SHA256SUMS',
          'size': 200,
          'browser_download_url': 'https://github.com/serjlee/gutter/releases/download/v1.2.3/SHA256SUMS',
        },
        {'name': 'broken'},
      ],
    });
    expect(r!.tag, 'v1.2.3');
    expect(r.version, '1.2.3');
    expect(r.notes, 'What\'s new');
    expect(r.assets.single.name, 'SHA256SUMS');
    expect(r.assets.single.size, 200);
    expect(r.publishedAt, DateTime.utc(2026, 9, 24, 10));
    expect(ReleaseInfo.fromGitHubJson({'message': 'Not Found'}), isNull);
    expect(ReleaseInfo.fromGitHubJson('nope'), isNull);
  });

  test('parses a list of releases, without pre-releases', () {
    Map<String, Object?> json(String tag, {bool pre = false}) => {
      'tag_name': tag,
      'html_url': 'https://github.com/serjlee/gutter/releases/tag/$tag',
      'prerelease': pre,
    };
    expect(
      releasesFromGitHubJson([
        json('v0.3.0'),
        json('v0.4.0-rc1', pre: true),
        json('v0.2.0'),
      ]).map((r) => r.tag),
      ['v0.3.0', 'v0.2.0'],
    );
    // A single release, as releases/latest returns it.
    expect(releasesFromGitHubJson(json('v0.3.0')).single.tag, 'v0.3.0');
    expect(releasesFromGitHubJson({'message': 'Not Found'}), isEmpty);
  });

  group('UpdateChecker', () {
    test('lists what is new since this build, newest first', () async {
      ReleaseInfo r(String tag) =>
          ReleaseInfo(tag: tag, url: 'https://x/$tag', publishedAt: null);
      final all = [r('v0.1.0'), r('v0.10.0'), r('v0.2.0'), r('v0.9.1')];
      final c = UpdateChecker(
        current: const AppVersion(version: '0.2.0'),
        fetcher: () async => all,
      );
      await c.check();
      expect(c.latest!.tag, 'v0.10.0');
      expect(c.newReleases.map((r) => r.tag), ['v0.10.0', 'v0.9.1']);

      final dev = UpdateChecker(
        current: const AppVersion(commit: 'abc1234'),
        fetcher: () async => all,
        comparer: (_, _) async => 'ahead',
      );
      await dev.check();
      expect(dev.newReleases.map((r) => r.tag), ['v0.10.0']);
    });

    test('flags newer releases: by version, else by commit', () async {
      final older = UpdateChecker(
        current: const AppVersion(version: '0.1.0'),
        fetcher: () async => [release],
      );
      await older.check();
      expect(older.updateAvailable, isTrue);

      final same = UpdateChecker(
        current: const AppVersion(version: '0.2.0'),
        fetcher: () async => [release],
      );
      await same.check();
      expect(same.updateAvailable, isFalse);

      // A build from a commit: offered the release when it contains the
      // commit and more, and only then.
      Future<bool> dev(
        Object? Function() status, {
        String commit = 'abc1234',
      }) async {
        final compared = <(String, String)>[];
        final c = UpdateChecker(
          current: AppVersion(commit: commit),
          fetcher: () async => [release],
          comparer: (base, head) async {
            compared.add((base, head));
            final s = status();
            if (s is Exception) throw s;
            return s as String?;
          },
        );
        await c.check();
        expect(c.latest, isNotNull);
        if (commit.isNotEmpty) expect(compared, [(commit, 'v0.2.0')]);
        if (commit.isEmpty) expect(compared, isEmpty);
        return c.updateAvailable;
      }

      expect(await dev(() => 'ahead'), isTrue);
      expect(await dev(() => 'identical'), isFalse);
      expect(await dev(() => 'behind'), isFalse);
      // Commits of its own (an unmerged branch): updating would lose them.
      expect(await dev(() => 'diverged'), isFalse);
      // Unknown to GitHub, or offline.
      expect(await dev(() => null), isFalse);
      expect(await dev(() => Exception('offline')), isFalse);
      // No commit either: nothing to compare.
      expect(await dev(() => 'ahead', commit: ''), isFalse);
    });

    test('records errors and recovers', () async {
      var fail = true;
      final c = UpdateChecker(
        current: const AppVersion(version: '0.1.0'),
        fetcher: () async => fail ? throw Exception('offline') : [release],
      );
      await c.check();
      expect(c.error, contains('offline'));
      expect(c.latest, isNull);
      fail = false;
      await c.check();
      expect(c.error, isNull);
      expect(c.updateAvailable, isTrue);
    });

    test('no release published yet', () async {
      final c = UpdateChecker(
        current: const AppVersion(version: '0.1.0'),
        fetcher: () async => const [],
      );
      await c.check();
      expect(c.latest, isNull);
      expect(c.updateAvailable, isFalse);
      expect(c.error, isNull);
    });
  });

  testWidgets('home tab shows the version and an update banner', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final checker = UpdateChecker(
      current: const AppVersion(version: '0.1.0', commit: 'abc1234'),
      fetcher: () async => [release],
    );
    final app = AppController(
      null,
      Settings(),
      updates: checker,
      updater: Updater(
        installation: const Installation(InstallKind.flatpak),
        flatpakInfo: '/nonexistent',
        // flatpak update on the host, then the installed commit.
        runOnHost: (command) async =>
            ProcessResult(0, 0, command[1] == 'info' ? 'bbb222\n' : '', ''),
        startOnHost: (_) async {},
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HomeTab(app: app)),
      ),
    );
    expect(find.text('v0.1.0 (abc1234)'), findsOneWidget);
    expect(find.byKey(const ValueKey('update-available')), findsNothing);

    await tester.runAsync(checker.check);
    await tester.pump();
    expect(find.byKey(const ValueKey('update-available')), findsOneWidget);
    expect(find.text('v0.2.0 is available'), findsOneWidget);
    // The dialog: Flatpak installs update with flatpak, then restart.
    await tester.tap(find.byKey(const ValueKey('update-open')));
    await tester.pump();
    expect(find.text('Gutter 0.2.0 is available'), findsOneWidget);
    expect(find.text('You have 0.1.0.'), findsOneWidget);
    expect(find.text('Update now'), findsOneWidget);
    await tester.runAsync(() => app.updater.prepare(release));
    await tester.pump();
    expect(find.textContaining('Updated. Restart Gutter'), findsOneWidget);
    expect(find.text('Restart now'), findsOneWidget);
    expect(find.text('Install on quit'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('update-later')));
    await tester.pump();
    // A new dialog for another check: skip this version.
    app.updater.stage = UpdateStage.idle;
    await tester.tap(find.byKey(const ValueKey('update-open')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('update-skip')));
    await tester.pump();
    expect(app.settings.skippedUpdate, 'v0.2.0');
    expect(app.takeUpdateOffer(), isFalse);
  });

  test('offers each release once, and never a skipped one', () async {
    final checker = UpdateChecker(
      current: const AppVersion(version: '0.1.0'),
      fetcher: () async => [release],
    );
    final app = AppController(null, Settings(), updates: checker);
    expect(app.takeUpdateOffer(), isFalse); // nothing known yet
    await checker.check();
    expect(app.takeUpdateOffer(), isTrue);
    expect(app.takeUpdateOffer(), isFalse);
  });

  test('release notes without the install notes', () {
    expect(
      releaseNotesText(
        '## What\'s new\n\n- **Faster** `fetch`\n\n---\n\n**macOS**: unzip',
      ),
      'What\'s new\n\n- Faster fetch',
    );
    // Early releases: an Installation heading, or nothing but install notes.
    expect(
      releaseNotesText(
        '## New features\r\n\r\n- Select\r\n\r\n## Installation\r\n\r\n**macOS**',
      ),
      'New features\n\n- Select',
    );
    expect(releaseNotesText('**macOS** (`Gutter-macos-*.zip`): unzip'), '');
  });

  testWidgets('the update dialog lists every release since this build', (
    tester,
  ) async {
    ReleaseInfo r(String tag, String notes) => ReleaseInfo(
      tag: tag,
      url: 'https://x/$tag',
      publishedAt: DateTime.utc(2026, 10, 2),
      notes: '$notes\n\n---\n\n**macOS**: unzip',
    );
    final checker = UpdateChecker(
      current: const AppVersion(version: '0.5.0'),
      fetcher: () async => [
        r('v0.5.0', 'Installed already'),
        r('v0.7.0', 'Rebase panel'),
        r('v0.6.0', 'Windows support'),
      ],
    );
    await checker.check();
    final app = AppController(null, Settings(), updates: checker);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdateDialog(app: app, release: checker.latest!),
        ),
      ),
    );
    expect(find.text('Gutter 0.7.0 is available'), findsOneWidget);
    expect(find.text('Rebase panel'), findsOneWidget);
    expect(find.text('Windows support'), findsOneWidget);
    expect(find.text('Installed already'), findsNothing);
    expect(find.textContaining('macOS'), findsNothing);
    // Newest first.
    expect(
      tester.getTopLeft(find.text('Rebase panel')).dy,
      lessThan(tester.getTopLeft(find.text('Windows support')).dy),
    );
  });

  testWidgets('"Check for Updates…" offers even a skipped release, or says '
      'why there is none', (tester) async {
    var releases = [release];
    var fail = false;
    final checker = UpdateChecker(
      current: const AppVersion(version: '0.1.0'),
      fetcher: () async => fail ? throw Exception('offline') : releases,
    );
    final app = AppController(
      null,
      Settings()..skippedUpdate = 'v0.2.0',
      updates: checker,
    );
    final messages = <String>[];
    app.messages.listen((m) => messages.add(m.text));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: AppShell(app: app),
      ),
    );
    await tester.pump();

    /// What the macOS runner sends when the menu item is chosen.
    Future<void> choose() async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'gutter/menu',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('checkForUpdates'),
        ),
        (_) {},
      );
      // (The app shell never settles: a few frames.)
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    // Skipped, yet asked for: offered, once.
    await choose();
    expect(find.text('Gutter 0.2.0 is available'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('update-later')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    releases = [const ReleaseInfo(tag: 'v0.1.0', url: 'u', publishedAt: null)];
    await choose();
    expect(find.textContaining('is available'), findsNothing);
    expect(messages.last, 'Gutter is up to date (latest release: v0.1.0)');

    fail = true;
    await choose();
    expect(messages.last, startsWith("Couldn't check for updates"));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });
}
