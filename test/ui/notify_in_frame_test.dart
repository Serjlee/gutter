import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/app_controller.dart';
import 'package:gutter/app/settings_store.dart';
import 'package:gutter/ui/repo/repo_tab_controller.dart';

import '../support/temp_repo.dart';

/// Calls [onDispose] as it goes away: like a tap that a disposed
/// double-click detector lets through while the frame tears widgets down.
class _Disposer extends StatefulWidget {
  const _Disposer(this.onDispose);
  final VoidCallback onDispose;
  @override
  State<_Disposer> createState() => _DisposerState();
}

class _DisposerState extends State<_Disposer> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  testWidgets('a change while the frame tears widgets down shows up after it', (
    tester,
  ) async {
    final t = await tester.runAsync(TempRepo.create);
    addTearDown(t!.dispose);
    final tab = RepoTabController(t.repo, AppController(null, Settings()));
    addTearDown(tab.dispose);

    Widget view({required bool disposer}) => MaterialApp(
      home: Column(
        children: [
          ListenableBuilder(
            listenable: tab,
            builder: (_, _) => Text(tab.detailsOpen ? 'open' : 'closed'),
          ),
          if (disposer) _Disposer(tab.toggleDetails),
        ],
      ),
    );
    await tester.pumpWidget(view(disposer: true));
    expect(find.text('open'), findsOneWidget);

    await tester.pumpWidget(view(disposer: false));
    expect(tester.takeException(), isNull);
    await tester.pump();
    expect(find.text('closed'), findsOneWidget);
  });
}
