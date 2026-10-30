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
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byKey(const ValueKey('theme-mode')), findsOneWidget);
    // The current graph mode and line hint, shown without opening their
    // menus.
    expect(find.byKey(const ValueKey('line-hint-preview')), findsOneWidget);
    final graphPreview = find.byKey(const ValueKey('graph-mode-preview'));
    double gap() {
      double x(String t) => tester
          .getTopLeft(find.descendant(of: graphPreview, matching: find.text(t)))
          .dx;
      return x('Fix typo') - x('main');
    }

    final full = gap(); // the label in its column, the message past the graph
    app.setGraphMode(GraphMode.fork);
    await tester.pump();
    expect(gap(), lessThan(full)); // the message right after the label

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

    // What the macOS runner sends for "Preferences…".
    Future<void> preferences() async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'gutter/menu',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('openSettings'),
        ),
        (_) {},
      );
      await tester.pump();
    }

    await preferences();
    expect(find.byKey(const ValueKey('theme-mode')), findsOneWidget);
    // Not twice, over itself.
    await preferences();
    expect(find.text('Settings'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });
}
