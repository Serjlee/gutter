import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late List<String> repos;

  setUp(() {
    root = Directory.systemTemp.createTempSync('gutter_groups_');
    repos = [
      for (final name in ['a', 'b', 'c', 'd', 'e'])
        (Directory(p.join(root.path, name))..createSync()).path,
    ];
    for (final r in repos) {
      Process.runSync('git', ['init', '-q', r]);
    }
  });
  tearDown(() => root.deleteSync(recursive: true));

  /// An app with the five repositories open, none loaded.
  Future<AppController> openAll() async {
    final app = AppController(null, Settings());
    for (final r in repos) {
      await app.openRepo(r, activate: false);
    }
    addTearDown(() => app.closeTabs(List.of(app.tabs)));
    return app;
  }

  List<String> names(AppController app) => [
    for (final t in app.tabs) '${t.name}${t.group == null ? '' : '*'}',
  ];

  test('a group gathers its tabs where the first one is', () async {
    final app = await openAll();
    final [a, b, c, d, _] = app.tabs;
    final g = app.createGroup([d, b]);
    expect(names(app), ['a', 'b*', 'd*', 'c', 'e']);
    expect(app.tabsIn(g), [b, d]);

    // A second group gets another color.
    final h = app.createGroup([a, c]);
    expect(h.color, isNot(g.color));
    expect(names(app), ['a*', 'c*', 'b*', 'd*', 'e']);
  });

  test('tabs join, leave and move; groups stay together', () async {
    final app = await openAll();
    final [a, b, c, d, e] = app.tabs;
    app.activate(app.tabs.indexOf(d));
    final g = app.createGroup([b, c]);

    // Dropped among a group's tabs without joining: after the group.
    app.placeTab(e, 2);
    expect(app.tabs, [a, b, c, e, d]);
    expect(app.activeTab, d); // moving tabs doesn't switch tabs

    app.addToGroup(a, g);
    expect(app.tabs, [b, c, a, e, d]);
    expect(a.group, g);

    app.removeFromGroup(b);
    expect(app.tabs, [c, a, b, e, d]);
    expect(b.group, isNull);

    app.moveGroup(g, 5);
    expect(app.tabs, [b, e, d, c, a]);
    expect(app.activeTab, d);

    app.ungroup(g);
    expect(app.groups, isEmpty);
    expect(app.tabs.every((t) => t.group == null), isTrue);
  });

  test('collapsing and closing groups', () async {
    final app = await openAll();
    final [a, b, c, d, _] = app.tabs;
    final g = app.createGroup([b, c]);
    app.activate(app.tabs.indexOf(c));

    // Collapsing the active tab's group shows the next tab outside it.
    app.setGroupCollapsed(g, true);
    expect(app.activeTab, d);
    expect(app.isHidden(b), isTrue);

    // Ctrl+Tab skips the collapsed tabs.
    app.activate(0);
    app.nextTab(1);
    expect(app.activeTab, d);

    // Showing a tab of a collapsed group expands it.
    app.activate(app.tabs.indexOf(b));
    expect(g.collapsed, isFalse);

    app.closeGroup(g);
    expect(app.tabs, [a, d, app.tabs.last]);
    expect(app.groups, isEmpty);
    expect(app.activeTab, a);
  });

  test('groups come back with the session; tabs load when shown', () async {
    final app = await openAll();
    final [_, b, c, _, e] = app.tabs;
    final g = app.createGroup([b, e], name: 'work');
    app.setGroupCollapsed(g, true);
    app.activate(app.tabs.indexOf(c));
    expect(c.started, isTrue);
    expect(b.started, isFalse);

    final json = app.settings.toJson();
    final again = AppController(null, Settings.fromJson(json));
    addTearDown(() => again.closeTabs(List.of(again.tabs)));
    await again.restoreSession();
    expect(names(again), ['a', 'b*', 'e*', 'c', 'd']);
    final restored = again.tabs[1].group!;
    expect(restored.name, 'work');
    expect(restored.collapsed, isTrue);
    expect(restored.color, g.color);
    expect(again.activeTab!.name, 'c');
    expect(
      [for (final t in again.tabs) t.started],
      [false, false, false, true, false],
    );
  });
}
