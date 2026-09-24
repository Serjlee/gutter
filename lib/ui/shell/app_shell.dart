import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../repo/repo_view.dart';
import 'home_tab.dart';
import 'tab_strip.dart';

/// Top-level layout: tab strip + active tab content, global shortcuts and
/// message snackbars.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.app});
  final AppController app;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  StreamSubscription<AppMessage>? _messages;

  AppController get app => widget.app;

  late final Map<ShortcutActivator, VoidCallback> _bindings = _shortcuts();

  @override
  void initState() {
    super.initState();
    _messages = app.messages.listen(_showMessage);
    // Global shortcuts are handled at the keyboard level so they keep working
    // whatever has focus (focus falls back to the root scope, above any
    // Shortcuts widget, when the focused widget goes away).
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _messages?.cancel();
    super.dispose();
  }

  ModalRoute<Object?>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    // Leave keys alone while a dialog or menu is open.
    final route = _route;
    if (route != null && !route.isCurrent) return false;
    for (final entry in _bindings.entries) {
      if (entry.key.accepts(event, HardwareKeyboard.instance)) {
        entry.value();
        return true;
      }
    }
    return false;
  }

  void _showMessage(AppMessage m) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: Duration(seconds: m.error ? 8 : 3),
        width: 640,
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              m.error ? Icons.error_outline : Icons.info_outline,
              size: 18,
              color: m.error ? AppColors.danger : AppColors.accent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SelectableText(
                m.text,
                maxLines: 12,
                style: const TextStyle(fontSize: 13, color: AppColors.text),
              ),
            ),
          ],
        ),
        action: SnackBarAction(label: 'Dismiss', onPressed: () {}),
      ),
    );
  }

  Future<void> _openRepoDialog() async {
    final dir = await getDirectoryPath(confirmButtonText: 'Open repository');
    if (dir != null) await app.openRepo(dir);
  }

  Map<ShortcutActivator, VoidCallback> _shortcuts() {
    final map = <ShortcutActivator, VoidCallback>{};
    void both(LogicalKeyboardKey key, VoidCallback cb, {bool shift = false}) {
      map[SingleActivator(key, control: true, shift: shift)] = cb;
      map[SingleActivator(key, meta: true, shift: shift)] = cb;
    }

    both(LogicalKeyboardKey.equal, app.zoomIn);
    both(LogicalKeyboardKey.equal, app.zoomIn, shift: true); // Ctrl + '+'
    both(LogicalKeyboardKey.add, app.zoomIn);
    both(LogicalKeyboardKey.numpadAdd, app.zoomIn);
    both(LogicalKeyboardKey.minus, app.zoomOut);
    both(LogicalKeyboardKey.numpadSubtract, app.zoomOut);
    both(LogicalKeyboardKey.digit0, app.zoomReset);
    both(LogicalKeyboardKey.numpad0, app.zoomReset);
    both(LogicalKeyboardKey.keyT, () => app.activate(-1));
    both(LogicalKeyboardKey.keyO, _openRepoDialog);
    both(LogicalKeyboardKey.keyW, () {
      if (app.activeIndex >= 0) app.closeTab(app.activeIndex);
    });
    map[const SingleActivator(LogicalKeyboardKey.tab, control: true)] = () =>
        app.nextTab(1);
    map[const SingleActivator(
      LogicalKeyboardKey.tab,
      control: true,
      shift: true,
    )] = () =>
        app.nextTab(-1);
    both(LogicalKeyboardKey.keyR, () => app.activeTab?.refresh(forceLog: true));
    map[const SingleActivator(LogicalKeyboardKey.f5)] = () =>
        app.activeTab?.refresh(forceLog: true);
    for (var i = 1; i <= 9; i++) {
      final key = LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i - 1);
      both(
        key,
        () =>
            app.activate(i - 1 < app.tabs.length ? i - 1 : app.tabs.length - 1),
      );
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      autofocus: true,
      child: Scaffold(
        body: ListenableBuilder(
          listenable: app,
          builder: (context, _) {
            final tab = app.activeTab;
            return Column(
              children: [
                TabStrip(app: app),
                const Divider(),
                Expanded(
                  child: tab == null
                      ? HomeTab(app: app)
                      : RepoView(key: ObjectKey(tab), tab: tab),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
