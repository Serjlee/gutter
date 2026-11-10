import 'dart:convert';
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

/// How an app found installed (a Linux `.desktop` file) is saved among
/// the apps to open with: this, then the file's path.
const desktopPrefix = 'desktop:';

/// The name an "Open with" app goes by in menus: an installed app's own,
/// else its command's or its app bundle's, without the folder.
String openWithLabel(String command) {
  command = command.trim();
  if (command.startsWith(desktopPrefix)) {
    final file = command.substring(desktopPrefix.length);
    return readDesktopEntry(file)?.name ?? p.basenameWithoutExtension(file);
  }
  final base = p.basename(command);
  return base.endsWith('.app') ? base.substring(0, base.length - 4) : base;
}

/// An app found installed, to suggest among the apps to open with.
class InstalledApp {
  const InstalledApp({required this.id, required this.name});

  /// What is saved among the apps to open with: a `.desktop` file
  /// ([desktopPrefix] and its path), or an app bundle's path (macOS).
  final String id;
  final String name;
}

/// What a Linux `.desktop` file says of its app.
class DesktopEntry {
  const DesktopEntry({
    required this.name,
    required this.exec,
    this.hidden = false,
  });
  final String name;

  /// The command line, with field codes (`%f`, `%U`, …) for the files.
  final String exec;

  /// Not to be listed (`NoDisplay`, `Hidden`, a terminal app, or not an
  /// application).
  final bool hidden;

  /// Whether it takes files or folders to open.
  bool get opensFiles => RegExp('%[fFuU]').hasMatch(exec);
}

final _desktopEntries = <String, DesktopEntry?>{};

/// The `[Desktop Entry]` of the `.desktop` file at [path], read once.
DesktopEntry? readDesktopEntry(String path) =>
    _desktopEntries.putIfAbsent(path, () {
      try {
        return parseDesktopEntry(File(path).readAsStringSync());
      } on FileSystemException {
        return null;
      }
    });

/// The `[Desktop Entry]` group of a `.desktop` file's [text], if it has a
/// name and a command.
DesktopEntry? parseDesktopEntry(String text) {
  String? name, exec, type;
  var hidden = false, inEntry = false;
  for (var line in const LineSplitter().convert(text)) {
    line = line.trim();
    if (line.startsWith('[')) {
      inEntry = line == '[Desktop Entry]';
      continue;
    }
    if (!inEntry || line.startsWith('#')) continue;
    final eq = line.indexOf('=');
    if (eq < 0) continue;
    final key = line.substring(0, eq).trim();
    final value = line.substring(eq + 1).trim();
    switch (key) {
      case 'Name':
        name = value;
      case 'Exec':
        exec = value;
      case 'Type':
        type = value;
      // Run in a terminal, they'd start in none: not listed either.
      case 'NoDisplay' || 'Hidden' || 'Terminal':
        if (value == 'true') hidden = true;
    }
  }
  if (name == null || exec == null) return null;
  return DesktopEntry(
    name: name,
    exec: exec,
    hidden: hidden || (type != null && type != 'Application'),
  );
}

/// The program and arguments of a `.desktop` [exec] line, opening [path]:
/// it takes the file codes' place, or comes last if there is none.
List<String> execArgs(String exec, String path) {
  // Arguments split at spaces, outside double quotes, where a backslash
  // escapes the next character.
  final words = <String>[];
  final word = StringBuffer();
  var quoted = false, any = false;
  for (var i = 0; i < exec.length; i++) {
    final c = exec[i];
    if (quoted && c == r'\' && i + 1 < exec.length) {
      word.write(exec[++i]);
    } else if (c == '"') {
      quoted = !quoted;
      any = true;
    } else if (c == ' ' && !quoted) {
      if (any || word.isNotEmpty) words.add(word.toString());
      word.clear();
      any = false;
    } else {
      word.write(c);
    }
  }
  if (any || word.isNotEmpty) words.add(word.toString());

  var placed = false;
  final args = <String>[];
  for (final w in words) {
    if (const {'%f', '%F', '%u', '%U'}.contains(w)) {
      if (!placed) args.add(path);
      placed = true;
    } else if (RegExp('^%[a-zA-Z]\$').hasMatch(w)) {
      // Codes for the icon, name or file of the entry: dropped.
    } else {
      args.add(w.replaceAll('%%', '%'));
    }
  }
  if (!placed) args.add(path);
  return args;
}

/// The apps installed that can open a folder, by name: on Linux, from the
/// `.desktop` files where desktops look for them (Flatpak's and Snap's
/// too); on macOS, the app bundles in the Applications folders. None on
/// other systems, or sandboxed (Flatpak), where they can't be started.
Future<List<InstalledApp>> findInstalledApps({
  Map<String, String>? environment,
  bool? macOS,
  bool? linux,
}) async {
  if (GitRunner.inFlatpak && environment == null) return const [];
  final env = environment ?? Platform.environment;
  final home = env['HOME'] ?? '';
  final apps = <String, InstalledApp>{};
  if (macOS ?? Platform.isMacOS) {
    for (final dir in [
      '/Applications',
      '/Applications/Utilities',
      '$home/Applications',
      '/System/Applications',
    ]) {
      for (final e in await _list(dir)) {
        if (!e.endsWith('.app')) continue;
        final name = p.basenameWithoutExtension(e);
        apps.putIfAbsent(name, () => InstalledApp(id: e, name: name));
      }
    }
  } else if (linux ?? Platform.isLinux) {
    final dataHome = env['XDG_DATA_HOME'] ?? '$home/.local/share';
    final dataDirs = (env['XDG_DATA_DIRS'] ?? '/usr/local/share:/usr/share')
        .split(':');
    // The first file by an id wins, as for the desktops: the user's own
    // before the system's.
    final ids = <String>{};
    for (final dir in [
      '$dataHome/applications',
      '$dataHome/flatpak/exports/share/applications',
      for (final d in dataDirs) '$d/applications',
      '/var/lib/flatpak/exports/share/applications',
      '/var/lib/snapd/desktop/applications',
    ]) {
      for (final f in await _list(dir)) {
        if (!f.endsWith('.desktop') || !ids.add(p.basename(f))) continue;
        final entry = readDesktopEntry(f);
        if (entry == null || entry.hidden || !entry.opensFiles) continue;
        apps.putIfAbsent(
          entry.name,
          () => InstalledApp(id: '$desktopPrefix$f', name: entry.name),
        );
      }
    }
  }
  return apps.values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

Future<List<String>> _list(String dir) async {
  try {
    return [await for (final e in Directory(dir).list()) e.path];
  } on FileSystemException {
    return const [];
  }
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
  if (command.startsWith(desktopPrefix)) {
    final file = command.substring(desktopPrefix.length);
    final entry = readDesktopEntry(file);
    if (entry == null) throw FileSystemException('Not found', file);
    final args = execArgs(entry.exec, path);
    return startDetached(args.first, args.sublist(1), path);
  }
  final exe = command.contains(Platform.pathSeparator)
      ? command
      : findExecutable(command);
  if (Platform.isMacOS && (command.endsWith('.app') || exe == null)) {
    return startDetached('open', ['-a', command, path], path);
  }
  return startDetached(exe ?? command, [path], path);
}
