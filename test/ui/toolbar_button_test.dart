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

  testWidgets('button sizes, with and without an arrow', (tester) async {
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
    // A plain button is its content plus 10 px on both sides; with a menu,
    // the top row is the icon plus the 18 px arrow slot, then 5 px.
    final withArrow = tester.getSize(find.byType(ToolbarButton).first).width;
    final plain = tester.getSize(find.byType(ToolbarButton).last).width;
    expect(plain, 10 + 20 + 10);
    expect(withArrow, 10 + 20 + 18 + 5);
    // The arrow's target covers its slot and the right padding, down to
    // the label.
    final arrow = tester.getSize(find.byType(PopupMenuButton<VoidCallback>));
    expect(arrow, const Size(18 + 5, 26));
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
    // (the arrow button minus the 5 px right padding).
    final rowLeft = icon.left;
    final slotRight = arrow.right - 5;
    expect(label.center.dx, closeTo((rowLeft + slotRight) / 2, 0.01));
    expect(slotRight - rowLeft, 20 + 18);
  });
}
