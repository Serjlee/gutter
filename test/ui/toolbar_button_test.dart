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
    // The arrow's target covers its slot and the space to the right edge,
    // down to the label.
    final arrow = tester.getSize(find.byType(PopupMenuButton<VoidCallback>));
    expect(arrow, const Size(18 + (ToolbarButton.width - 20 - 18) / 2, 26));
  });

  testWidgets('the label is centered under the icon and the arrow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Center(
            child: ToolbarButton(
              icon: Icons.download,
              label: 'Pu', // test font: 22 px, narrower than the icon row
              onPressed: () {},
              menu: const [],
            ),
          ),
        ),
      ),
    );
    final icon = tester.getRect(find.byIcon(Icons.download));
    final arrow = tester.getRect(find.byType(PopupMenuButton<VoidCallback>));
    final label = tester.getRect(find.text('Pu'));
    // Between the icon box's left edge and the arrow slot's right edge
    // (the arrow button minus the space to the button's right edge).
    final rowLeft = icon.left;
    final slotRight = arrow.right - (ToolbarButton.width - 20 - 18) / 2;
    expect(label.center.dx, closeTo((rowLeft + slotRight) / 2, 0.01));
    expect(slotRight - rowLeft, 20 + 18);
    final button = tester.getRect(find.byType(ToolbarButton));
    expect(label.center.dx, closeTo(button.center.dx, 0.01));
  });
}
