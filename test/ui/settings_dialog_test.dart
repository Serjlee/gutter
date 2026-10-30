import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/ui/shell/app_shell.dart';

void main() {
  testWidgets('the settings open in a dialog: from the home tab, and with '
      'Ctrl+P', (tester) async {
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
    await tester.tap(find.byKey(const ValueKey('settings-close')));
    await tester.pump();
    expect(find.byKey(const ValueKey('theme-mode')), findsNothing);

    // (Linux here: Ctrl+P; ⌘, on macOS.)
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.byKey(const ValueKey('theme-mode')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });
}
