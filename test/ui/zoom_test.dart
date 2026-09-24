import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/zoom.dart';
import 'package:gutter/ui/shell/app_shell.dart';

/// App shell with a zoom scope, like main.dart builds it.
Widget harness(AppController app) => MaterialApp(
  builder: (context, child) => ListenableBuilder(
    listenable: app,
    builder: (context, _) =>
        ZoomScope(zoom: app.zoom, onZoomChanged: app.setZoom, child: child!),
  ),
  home: AppShell(app: app),
);

void main() {
  testWidgets('child is laid out at window size / zoom and taps still hit', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            ZoomScope(zoom: 1.5, onZoomChanged: (_) {}, child: child!),
        home: LayoutBuilder(
          builder: (context, c) {
            return Stack(
              children: [
                Positioned(
                  left: 100,
                  top: 100,
                  width: 50,
                  height: 20,
                  child: GestureDetector(
                    onTap: () => taps++,
                    child: Container(
                      key: const Key('target'),
                      color: Colors.red,
                    ),
                  ),
                ),
                Text(
                  '${c.maxWidth.round()}x${c.maxHeight.round()}',
                  key: const Key('size'),
                ),
              ],
            );
          },
        ),
      ),
    );
    expect(find.text('800x533'), findsOneWidget);
    // Visually the target is scaled: 100..150 * 1.5 = 150..225.
    final rect = tester.getRect(find.byKey(const Key('target')));
    expect(rect.left, closeTo(150, 0.01));
    expect(rect.width, closeTo(75, 0.01));
    await tester.tapAt(const Offset(200, 165));
    expect(taps, 1);
    await tester.tapAt(const Offset(120, 110)); // unscaled position: a miss
    expect(taps, 1);
  });

  testWidgets('keyboard shortcuts step, clamp and reset zoom; value persists', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final app = AppController(null, Settings()..zoom = 1.5);
    await tester.pumpWidget(harness(app));
    await tester.pump();
    expect(app.zoom, 1.5);

    Future<void> ctrl(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    await ctrl(LogicalKeyboardKey.equal);
    expect(app.zoom, 1.6);
    await ctrl(LogicalKeyboardKey.minus);
    await ctrl(LogicalKeyboardKey.minus);
    expect(app.zoom, 1.4);
    await ctrl(LogicalKeyboardKey.digit0);
    expect(app.zoom, 1.0);
    for (var i = 0; i < 12; i++) {
      await ctrl(LogicalKeyboardKey.minus);
    }
    expect(app.zoom, minZoom);
    for (var i = 0; i < 40; i++) {
      await ctrl(LogicalKeyboardKey.equal);
    }
    expect(app.zoom, maxZoom);
    expect(app.settings.toJson()['zoom'], maxZoom);
    expect(Settings.fromJson(app.settings.toJson()).zoom, maxZoom);
    await tester.pump(const Duration(seconds: 2)); // badge timer
  });

  testWidgets('home tab renders at 150% without layout errors', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final app = AppController(null, Settings()..zoom = 1.5);
    await tester.pumpWidget(harness(app));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Gutter'), findsOneWidget);
    // The zoom control in settings shows the current value.
    expect(find.text('150%'), findsWidgets);
  });

  test('clampZoom rounds and bounds', () {
    expect(clampZoom(1.2300001), 1.23);
    expect(clampZoom(0.1), minZoom);
    expect(clampZoom(9), maxZoom);
  });
}
