import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/ui/shell/app_shell.dart';

void main() {
  testWidgets('the settings open in a dialog: from the home tab, with '
      'Ctrl+P, and from the macOS app menu', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = AppController(null, Settings());
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: AppShell(app: app),
      ),
    );
    await tester.pump();
    // Not on the home tab itself any more.
    expect(find.byKey(const ValueKey('theme-mode')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('open-settings')));
    await tester.pump();
    expect(find.byKey(const ValueKey('theme-mode')), findsOneWidget);
    // Each graph mode and line hint shows what it looks like, side by side;
    // a tap picks one.
    double gap(GraphMode mode) {
      final tile = find.byKey(ValueKey('graph-mode-${mode.name}'));
      double x(String t) => tester
          .getTopLeft(find.descendant(of: tile, matching: find.text(t)))
          .dx;
      return x('Fix typo') - x('main');
    }

    // Full: the label in its column, the message past the graph; Fork: the
    // message right after the label.
    expect(gap(GraphMode.fork), lessThan(gap(GraphMode.full)));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('line-hint')),
        matching: find.text('Fix typo'),
      ),
      findsNWidgets(4),
    );
    await tester.tap(find.byKey(const ValueKey('graph-mode-fork')));
    await tester.pump();
    expect(app.settings.graphMode, GraphMode.fork);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('graph-mode-fork')),
        matching: find.byKey(const ValueKey('graph-mode-selected')),
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('syntax-highlighting')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('syntax-highlighting')));
    await tester.pump();
    expect(app.settings.syntaxHighlight, isFalse);

    // The other sections, a tab each.
    await tester.tap(find.byKey(const ValueKey('settings-tab-git')));
    await tester.pump();
    expect(find.byKey(const ValueKey('theme-mode')), findsNothing);
    expect(find.byKey(const ValueKey('git-path')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('force-tag-fetch')));
    await tester.pump();
    expect(app.settings.forceTagFetch, isTrue);
    await tester.tap(find.byKey(const ValueKey('settings-tab-performance')));
    await tester.pump();
    expect(find.text('Commits loaded'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-close')));
    await tester.pump();
    expect(find.byKey(const ValueKey('theme-mode')), findsNothing);

    // (Linux here: Ctrl+P; ⌘, on macOS.)
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.byKey(const ValueKey('theme-mode')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-close')));
    await tester.pump();

    // What the macOS runner sends for "Settings…".
    Future<void> settingsItem() async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'gutter/menu',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('openSettings'),
        ),
        (_) {},
      );
      await tester.pump();
    }

    await settingsItem();
    expect(find.byKey(const ValueKey('theme-mode')), findsOneWidget);
    // Not twice, over itself.
    await settingsItem();
    expect(find.byKey(const ValueKey('settings-close')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });
}
