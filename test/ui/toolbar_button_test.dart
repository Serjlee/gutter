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

  testWidgets('every button has the same width', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ToolbarButton(
                icon: Icons.download,
                label: 'Pull',
                menu: const [],
              ),
              const ToolbarButton(icon: Icons.sync, label: 'Pop'),
              const ToolbarButton(icon: Icons.sync, label: 'Branch'),
            ],
          ),
        ),
      ),
    );
    for (final b in tester.widgetList(find.byType(ToolbarButton))) {
      expect(tester.getSize(find.byWidget(b)).width, ToolbarButton.width);
    }
    // The arrow's target covers the space from the icon to the right edge,
    // down to the label.
    final arrow = tester.getSize(find.byType(PopupMenuButton<VoidCallback>));
    expect(arrow, const Size((ToolbarButton.width - 20) / 2, 26));
  });

  testWidgets('icon and label are centered; the arrow is right of the icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Center(
            child: ToolbarButton(
              icon: Icons.download,
              label: 'Pull',
              onPressed: () {},
              menu: const [],
            ),
          ),
        ),
      ),
    );
    final button = tester.getRect(find.byType(ToolbarButton));
    final icon = tester.getRect(find.byIcon(Icons.download));
    final label = tester.getRect(find.text('Pull'));
    final arrow = tester.getRect(find.byType(PopupMenuButton<VoidCallback>));
    expect(icon.center.dx, closeTo(button.center.dx, 0.01));
    expect(label.center.dx, closeTo(button.center.dx, 0.01));
    expect(arrow.left, icon.right);
    expect(arrow.right, button.right);
  });
}
