import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/update_checker.dart';
import 'package:gutter/app/version.dart';
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
    });
    expect(r!.tag, 'v1.2.3');
    expect(r.publishedAt, DateTime.utc(2026, 9, 24, 10));
    expect(ReleaseInfo.fromGitHubJson({'message': 'Not Found'}), isNull);
    expect(ReleaseInfo.fromGitHubJson('nope'), isNull);
  });

  group('UpdateChecker', () {
    test('flags newer releases for release builds only', () async {
      final older = UpdateChecker(
        current: const AppVersion(version: '0.1.0'),
        fetcher: () async => release,
      );
      await older.check();
      expect(older.updateAvailable, isTrue);

      final same = UpdateChecker(
        current: const AppVersion(version: '0.2.0'),
        fetcher: () async => release,
      );
      await same.check();
      expect(same.updateAvailable, isFalse);

      final dev = UpdateChecker(
        current: const AppVersion(commit: 'abc1234'),
        fetcher: () async => release,
      );
      await dev.check();
      expect(dev.latest, isNotNull);
      expect(dev.updateAvailable, isFalse, reason: 'dev builds cannot compare');
    });

    test('records errors and recovers', () async {
      var fail = true;
      final c = UpdateChecker(
        current: const AppVersion(version: '0.1.0'),
        fetcher: () async => fail ? throw Exception('offline') : release,
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
        fetcher: () async => null,
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
      fetcher: () async => release,
    );
    final app = AppController(null, Settings(), updates: checker);
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
    expect(find.text('Open release page'), findsOneWidget);
  });
}
