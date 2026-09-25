import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/ui/widgets/common.dart';

void main() {
  testWidgets('the button runs its action; its arrow opens the menu', (
    tester,
  ) async {
    var pressed = 0, picked = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Center(
            child: ToolbarButton(
              icon: Icons.download,
              label: 'Pull',
              onPressed: () => pressed++,
              menu: [menuItem('Pull (rebase)', () => picked++)],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pull'));
    await tester.pump();
    expect(pressed, 1);

    await tester.tap(find.byIcon(Icons.arrow_drop_down));
    await tester.pumpAndSettle();
    expect(pressed, 1); // the arrow doesn't trigger the main action
    await tester.tap(find.text('Pull (rebase)'));
    await tester.pumpAndSettle();
    expect(picked, 1);
  });

  testWidgets('with or without an arrow, buttons have the same padding', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ToolbarButton(icon: Icons.download, label: 'A', menu: const []),
              const ToolbarButton(icon: Icons.sync, label: 'B'),
            ],
          ),
        ),
      ),
    );
    // Each button is its content plus 10 px on both sides: the arrow is
    // inside the content (icon row = 20 px icon + 9 px arrow).
    final withArrow = tester.getSize(find.byType(ToolbarButton).first).width;
    final plain = tester.getSize(find.byType(ToolbarButton).last).width;
    expect(withArrow, 10 + 29 + 10);
    expect(plain, 10 + 20 + 10);
  });
}
