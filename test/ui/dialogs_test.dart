import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/ui/dialogs/dialogs.dart';

void main() {
  Future<String?> prompt(WidgetTester tester, {required bool optional}) async {
    String? result = 'not closed';
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await promptText(
              context,
              title: 'Stash changes',
              label: 'Message',
              optional: optional,
              confirmLabel: 'Stash',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.tap(find.text('Stash').last);
    await tester.pump();
    return result;
  }

  testWidgets('an optional field accepts an empty value', (tester) async {
    expect(await prompt(tester, optional: true), '');
    expect(find.text('Message (optional)'), findsNothing); // closed
  });

  testWidgets('a required field refuses an empty value', (tester) async {
    expect(await prompt(tester, optional: false), 'not closed');
    expect(find.text('Message is required'), findsOneWidget);
  });
}
