import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/ui/widgets/common.dart';

void main() {
  testWidgets('copying says what was copied', (tester) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    final app = AppController(null, Settings());
    final messages = <String>[];
    app.messages.listen((m) => messages.add(m.text));

    await copyToClipboard(app, 'abc1234def', label: 'SHA abc1234');
    expect(clipboard, 'abc1234def');

    // Without a label: the text's first line, shortened.
    await copyToClipboard(app, 'feature/graph');
    await copyToClipboard(app, 'first line\nsecond line');
    await copyToClipboard(app, 'x' * 100);
    await tester.pump();

    expect(messages, [
      'Copied SHA abc1234',
      'Copied feature/graph',
      'Copied first line',
      'Copied ${'x' * 59}…',
    ]);
  });
}
