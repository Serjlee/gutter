import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/ui/widgets/common.dart';

void main() {
  testWidgets('copied lines keep their line breaks', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: SelectionArea(
            child: ListView(
              children: [
                for (final (n, text) in [(1, 'one'), (2, 'two'), (3, 'three')])
                  Row(
                    children: [
                      SelectionContainer.disabled(child: Text('$n ')),
                      Expanded(child: SelectableLine(child: Text(text))),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    // Drag from the start of "one" to inside "three" (test font: 14 px per
    // character).
    final start = tester.getTopLeft(find.text('one')) + const Offset(1, 5);
    final end = tester.getTopLeft(find.text('three')) + const Offset(30, 5);
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    for (var t = 0.25; t <= 1; t += 0.25) {
      await gesture.moveTo(Offset.lerp(start, end, t)!);
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    // No line numbers; line breaks between lines, none after a partial one.
    expect(copied, 'one\ntwo\nth');
  });
}
