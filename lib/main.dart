import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app_controller.dart';
import 'app/settings_store.dart';
import 'app/theme.dart';
import 'app/window_chrome.dart';
import 'app/zoom.dart';
import 'ui/shell/app_shell.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      title: 'Gutter',
      size: Size(1400, 880),
      minimumSize: Size(900, 560),
      center: true,
      backgroundColor: AppColors.background,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );

  final dir =
      Platform.environment['GUTTER_CONFIG_DIR'] ??
      (await getApplicationSupportDirectory()).path;
  final store = await SettingsStore.open(dir);
  final app = AppController(store, store.load());
  runApp(GutterApp(app: app));
  app.startUpdateChecks();

  // Repositories passed on the command line open as tabs.
  await app.restoreSession();
  for (final a in args) {
    await app.openRepo(a);
  }
}

class GutterApp extends StatefulWidget {
  const GutterApp({super.key, required this.app});
  final AppController app;

  @override
  State<GutterApp> createState() => _GutterAppState();
}

class _GutterAppState extends State<GutterApp>
    with WindowListener, WidgetsBindingObserver {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addObserver(this);
    // Fallback focus signal for platforms where window events are missing.
    _lifecycle = AppLifecycleListener(
      onStateChange: (s) {
        if (s == AppLifecycleState.resumed) widget.app.setFocused(true);
        if (s == AppLifecycleState.inactive || s == AppLifecycleState.hidden) {
          widget.app.setFocused(false);
        }
      },
    );
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    _lifecycle.dispose();
    widget.app.dispose();
    super.dispose();
  }

  /// "System" theme: follow the OS when it switches.
  @override
  void didChangePlatformBrightness() => setState(() {});

  /// Picks the palette for the theme setting; on a change, restyles the
  /// window frame. True when it changed.
  bool _applyPalette() {
    final palette = widget.app.paletteFor(
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
    if (identical(palette, AppColors.current) && _framed) return false;
    AppColors.current = palette;
    _framed = true;
    unawaited(setWindowBrightness(palette.brightness));
    return true;
  }

  bool _framed = false;
  final _themes = <Brightness, ThemeData>{};

  @override
  void onWindowFocus() => widget.app.setFocused(true);

  @override
  void onWindowBlur() => widget.app.setFocused(false);

  @override
  void onWindowClose() => widget.app.store?.saveNow(widget.app.settings);

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    // The theme setting changes through the app; the palette is read by
    // every widget as it builds, so a switch rebuilds the whole tree.
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        _applyPalette();
        return KeyedSubtree(
          key: ValueKey(AppColors.current.brightness),
          child: MaterialApp(
            title: 'Gutter',
            debugShowCheckedModeBanner: false,
            // One ThemeData per palette: a new one would rebuild every
            // widget that uses the theme, on any app change.
            theme: _themes.putIfAbsent(
              AppColors.current.brightness,
              buildTheme,
            ),
            builder: (context, child) => ListenableBuilder(
              listenable: app,
              builder: (context, _) => ZoomScope(
                zoom: app.zoom,
                onZoomChanged: app.setZoom,
                child: child!,
              ),
            ),
            home: AppShell(app: app),
          ),
        );
      },
    );
  }
}
