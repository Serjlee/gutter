import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app_controller.dart';
import 'app/settings_store.dart';
import 'app/theme.dart';
import 'app/zoom.dart';
import 'ui/shell/app_shell.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
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

class _GutterAppState extends State<GutterApp> with WindowListener {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
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
    _lifecycle.dispose();
    widget.app.dispose();
    super.dispose();
  }

  @override
  void onWindowFocus() => widget.app.setFocused(true);

  @override
  void onWindowBlur() => widget.app.setFocused(false);

  @override
  void onWindowClose() => widget.app.store?.saveNow(widget.app.settings);

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return MaterialApp(
      title: 'Gutter',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      builder: (context, child) => ListenableBuilder(
        listenable: app,
        builder: (context, _) => ZoomScope(
          zoom: app.zoom,
          onZoomChanged: app.setZoom,
          child: child!,
        ),
      ),
      home: AppShell(app: app),
    );
  }
}
