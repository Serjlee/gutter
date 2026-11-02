import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/app/theme.dart';
import 'package:gutter/app/zoom.dart';
import 'package:gutter/ui/diff/diff_view.dart';
import 'package:gutter/ui/repo/repo_tab_controller.dart';

import '../support/temp_repo.dart';

void main() {
  for (final split in [true, false]) {
    for (final zoom in [1.0, 1.5]) {
      testWidgets('${split ? 'split' : 'unified'} diff at ${zoom * 100}%, '
          'scrolled: a drag selects the line under it', (tester) async {
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
        late TempRepo t;
        late RepoTabController tab;
        await tester.runAsync(() async {
          t = await TempRepo.create();
          t.commit('one', {
            'a.txt': [for (var i = 0; i < 80; i++) 'old $i'].join('\n'),
          });
          t.write('a.txt', [for (var i = 0; i < 80; i++) 'new $i'].join('\n'));
          tab = RepoTabController(
            t.repo,
            AppController(
              null,
              Settings()
                ..diffSplit = split
                ..diffWrap = true,
            ),
          );
          await tab.load();
          tab.openWorkingFile(tab.status.unstaged.single, staged: false);
          for (var i = 0; i < 100 && tab.diff == null; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        addTearDown(() {
          tab.dispose();
          t.dispose();
        });
        tester.view.physicalSize = Size(1200 * zoom, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(),
            builder: (_, child) =>
                ZoomScope(zoom: zoom, onZoomChanged: (_) {}, child: child!),
            home: Scaffold(
              body: ListenableBuilder(
                listenable: tab,
                builder: (_, _) => DiffView(tab: tab),
              ),
            ),
          ),
        );
        await tester.pump();
        // Far enough down that the drift would be rows.
        tester
            .state<ScrollableState>(
              find.descendant(
                of: find.byType(DiffView),
                matching: find.byType(Scrollable),
              ),
            )
            .position
            .jumpTo(800);
        await tester.pump();

        final view = tester.getRect(find.byType(DiffView));
        var tried = 0;
        for (final text in ['new 60', 'new 62', 'old 61']) {
          final line = find.text(text);
          if (line.evaluate().isEmpty) continue;
          final r = tester.getRect(line);
          if (r.top < view.top + 60 || r.bottom > view.bottom) continue;
          final gesture = await tester.startGesture(
            r.centerLeft + const Offset(1, 0),
            kind: PointerDeviceKind.mouse,
          );
          await tester.pump();
          await gesture.moveTo(r.center);
          await tester.pump();
          await gesture.moveTo(r.centerRight - const Offset(1, 0));
          await tester.pump();
          await gesture.up();
          await tester.pump();
          copied = null;
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.pump();
          expect(copied?.trim(), text);
          tried++;
        }
        expect(tried, greaterThan(0));

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 2));
      });
    }
  }
}
