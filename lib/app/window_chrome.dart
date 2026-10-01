import 'dart:io';

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Matches the native window frame (title bar) to the app's theme: through
/// window_manager on macOS, through the runner's "gutter/window" channel on
/// Linux.
Future<void> setWindowBrightness(Brightness brightness) async {
  try {
    if (Platform.isMacOS) {
      await windowManager.setBrightness(brightness);
    } else if (Platform.isLinux) {
      await const MethodChannel('gutter/window')
          .invokeMethod<void>('setDark', brightness == Brightness.dark);
    }
  } catch (_) {
    // No native side (tests, an older runner): the frame keeps its look.
  }
}
