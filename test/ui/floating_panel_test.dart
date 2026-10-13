import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/ui/widgets/floating_panel.dart';

void main() {
  testWidgets('a floating panel moves by its handle and resizes from its '
      'edges, within its area', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Size? resized;
    var behind = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  key: const ValueKey('behind'),
                  onTap: () => behind++,
                ),
              ),
              Positioned.fill(
                child: FloatingPanel(
                  size: const Size(800, 600),
                  onResized: (s) => resized = s,
                  builder: (context, move) =>
                      Column(children: [move(const Text('Title'))]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final panel = find.byKey(const ValueKey('floating-panel'));
    Rect rect() => tester.getRect(panel);
    Future<void> drag(String key, Offset by) async {
      await tester.drag(
        find.byKey(ValueKey(key)),
        by,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
    }

    // Centered.
    expect(rect(), const Rect.fromLTWH(200, 150, 800, 600));

    // What's around it can still be clicked.
    await tester.tapAt(const Offset(50, 50));
    expect(behind, 1);

    // Moved by its title, not past the edges.
    await tester.drag(
      find.text('Title'),
      const Offset(-100, -50),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(rect(), const Rect.fromLTWH(100, 100, 800, 600));
    await tester.drag(
      find.text('Title'),
      const Offset(-500, -500),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(rect().topLeft, Offset.zero);

    // An edge moves alone: the opposite one stays.
    await drag('resize-right', const Offset(100, 0));
    expect(rect(), const Rect.fromLTWH(0, 0, 900, 600));
    expect(resized, const Size(900, 600));
    await drag('resize-bottom-left', const Offset(50, 40));
    expect(rect(), const Rect.fromLTWH(50, 0, 850, 640));

    // Never smaller than the minimum, nor past the area.
    await drag('resize-corner', const Offset(-800, -800));
    expect(rect().size, const Size(600, 420));
    await drag('resize-corner', const Offset(2000, 2000));
    expect(rect().bottomRight, const Offset(1200, 900));
  });
}
