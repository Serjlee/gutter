import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../git/git_runner.dart';

/// Where the executable [name] is: on PATH, or where it usually installs
/// (apps started from Finder or the Dock get a short PATH). Null if none.
String? findExecutable(
  String name, {
  Map<String, String>? environment,
  bool? windows,
  bool? macOS,
  bool Function(String path)? exists,
}) {
  final env = environment ?? Platform.environment;
  final win = windows ?? Platform.isWindows;
  final mac = macOS ?? Platform.isMacOS;
  final found = exists ?? (String f) => File(f).existsSync();
  final names = win ? ['$name.exe', '$name.cmd', '$name.bat'] : [name];
  final dirs = [
    ...(env['PATH'] ?? '').split(win ? ';' : ':'),
    if (mac) ...['/opt/homebrew/bin', '/usr/local/bin'],
    if (!win) ...['/usr/local/bin', '/usr/bin', '/bin', '/snap/bin'],
  ];
  for (final d in dirs) {
    if (d.isEmpty) continue;
    for (final n in names) {
      final f = win ? '$d\\$n' : '$d/$n';
      if (found(f)) return f;
    }
  }
  return null;
}

/// VS Code's `code` command, if installed: on PATH, or where its installers
/// put it.
String? findVSCode({
  Map<String, String>? environment,
  bool? windows,
  bool? macOS,
  bool Function(String path)? exists,
}) {
  // Sandboxed, host apps aren't reachable.
  if (GitRunner.inFlatpak && environment == null) return null;
  final env = environment ?? Platform.environment;
  final win = windows ?? Platform.isWindows;
  final mac = macOS ?? Platform.isMacOS;
  final found = exists ?? (String f) => File(f).existsSync();
  final onPath = findExecutable(
    'code',
    environment: env,
    windows: win,
    macOS: mac,
    exists: found,
  );
  if (onPath != null) return onPath;
  final bundled = [
    if (mac) ...[
      '/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code',
      if (env['HOME'] case final home?)
        '$home/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code',
    ],
    if (win)
      if (env['LOCALAPPDATA'] case final local?)
        '$local\\Programs\\Microsoft VS Code\\bin\\code.cmd',
  ];
  return bundled.where(found).firstOrNull;
}

/// The name an "Open with" app goes by in menus: its command's, or its
/// app bundle's, without the folder.
String openWithLabel(String command) {
  final base = p.basename(command.trim());
  return base.endsWith('.app') ? base.substring(0, base.length - 4) : base;
}

/// Starts a program, not waiting for it: replaced in tests.
@visibleForTesting
Future<void> Function(String exe, List<String> args, String workingDirectory)
startDetached = (exe, args, cwd) async {
  await Process.start(
    exe,
    args,
    workingDirectory: cwd,
    mode: ProcessStartMode.detached,
    // .cmd scripts (VS Code's `code`) only run through the shell.
    runInShell: Platform.isWindows,
  );
};

/// Shows the folder [path] in the platform's file manager.
Future<void> openFolder(String path) => startDetached(
  Platform.isMacOS
      ? 'open'
      : Platform.isWindows
      ? 'explorer'
      : 'xdg-open',
  [path],
  path,
);

/// Opens the folder [path] with [command]: a program (on PATH or by path)
/// given the folder, or, on macOS, an app by name or bundle (`open -a`).
Future<void> openWith(String command, String path) {
  command = command.trim();
  final exe = command.contains(Platform.pathSeparator)
      ? command
      : findExecutable(command);
  if (Platform.isMacOS && (command.endsWith('.app') || exe == null)) {
    return startDetached('open', ['-a', command, path], path);
  }
  return startDetached(exe ?? command, [path], path);
}
