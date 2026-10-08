import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../dialogs/dialogs.dart';
import '../dialogs/update_dialog.dart';
import '../repo/repo_view.dart';
import 'home_tab.dart';
import 'tab_strip.dart';
import 'tab_switcher.dart';

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
    app.updates.addListener(_offerUpdate);
  }

  @override
  void dispose() {
    app.updates.removeListener(_offerUpdate);
    HardwareKeyboard.instance.removeHandler(_onKey);
    _messages?.cancel();
    super.dispose();
  }

  ModalRoute<Object?>? _route;

  /// Pops up the update dialog when a newer release shows up.
  void _offerUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Not over another dialog: next check, then.
      if (!mounted || _route?.isCurrent == false) return;
      if (app.takeUpdateOffer()) showUpdateDialog(context, app);
    });
  }

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
    // A compact toast at the bottom, sized to the message: centered, over
    // the graph rather than the commit box, and above the output bar.
    final screen = MediaQuery.sizeOf(context).width;
    final maxWidth = m.error || m.warning ? 520.0 : 380.0;
    final textWidth = (TextPainter(
      text: TextSpan(text: m.text, style: const TextStyle(fontSize: 12.5)),
      textDirection: TextDirection.ltr,
    )..layout()).width;
    final hasDetails = m.onDetails != null || m.details != null;
    final width = (textWidth + (hasDetails ? 170 : 90)).clamp(
      200.0,
      maxWidth + (hasDetails ? 80 : 0),
    );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: Duration(seconds: m.error || m.warning ? 8 : 3),
          margin: EdgeInsets.symmetric(
            horizontal: ((screen - width) / 2).clamp(16.0, double.infinity),
          ).copyWith(bottom: 40),
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          showCloseIcon: true,
          closeIconColor: AppColors.textDim,
          action: hasDetails
              ? SnackBarAction(
                  label: 'Details',
                  textColor: AppColors.accent,
                  onPressed:
                      m.onDetails ??
                      () => showErrorDetails(context, m.details!),
                )
              : null,
          content: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  m.error
                      ? Icons.error_outline
                      : m.warning
                      ? Icons.warning_amber
                      : Icons.check_circle_outline,
                  size: 16,
                  color: m.error
                      ? AppColors.danger
                      : m.warning
                      ? AppColors.warning
                      : AppColors.success,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SelectableText(
                  m.text,
                  minLines: 1,
                  maxLines: 8,
                  style: TextStyle(fontSize: 12.5, color: AppColors.text),
                ),
              ),
            ],
          ),
        ),
        snackBarAnimationStyle: const AnimationStyle(
          duration: Duration(milliseconds: 100),
          reverseDuration: Duration(milliseconds: 80),
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
    both(
      LogicalKeyboardKey.keyA,
      () => showTabSwitcher(context, app),
      shift: true,
    );
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
    both(LogicalKeyboardKey.keyI, () => app.activeTab?.toggleDetails());
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
