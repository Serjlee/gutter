import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../git/git_runner.dart';
import 'user_env.dart';

/// Where the executable [name] is: on PATH, or where it usually installs
/// (apps started from Finder or the Dock get a short PATH). Null if none.
String? findExecutable(
  String name, {
  Map<String, String>? environment,
  bool? windows,
  bool? macOS,
  bool Function(String path)? exists,
}) {
  final env = environment ?? userEnvironment;
  final win = windows ?? Platform.isWindows;
  final mac = macOS ?? Platform.isMacOS;
  // (Sandboxed, the host's system folders are seen elsewhere.)
  final found = exists ?? (String f) => File(sandboxPath(f)).existsSync();
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
  final env = environment ?? userEnvironment;
  final win = windows ?? Platform.isWindows;
  final mac = macOS ?? Platform.isMacOS;
  final found = exists ?? (String f) => File(sandboxPath(f)).existsSync();
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
    this.terminal = false,
  });
  final String name;

  /// The command line, with field codes (`%f`, `%U`, …) for the files.
  final String exec;

  /// Not to be listed (`NoDisplay`, `Hidden`, or not an application).
  final bool hidden;

  /// Runs in a terminal (`Terminal`): opened in one.
  final bool terminal;

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
  var hidden = false, terminal = false, inEntry = false;
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
      case 'NoDisplay' || 'Hidden':
        if (value == 'true') hidden = true;
      case 'Terminal':
        terminal = value == 'true';
    }
  }
  if (name == null || exec == null) return null;
  return DesktopEntry(
    name: name,
    exec: exec,
    hidden: hidden || (type != null && type != 'Application'),
    terminal: terminal,
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
  bool? flatpak,
}) async {
  final sandboxed = flatpak ?? (GitRunner.inFlatpak && environment == null);
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
    // Sandboxed, the XDG folders are the sandbox's: the host's usual ones,
    // where the sandbox sees them.
    final dataHome = sandboxed
        ? '$home/.local/share'
        : env['XDG_DATA_HOME'] ?? '$home/.local/share';
    final dataDirs = sandboxed
        ? [
            for (final d in ['/usr/local/share', '/usr/share'])
              sandboxPath(d, flatpak: true),
          ]
        : (env['XDG_DATA_DIRS'] ?? '/usr/local/share:/usr/share').split(':');
    // The first file by an id wins, as for the desktops: the user's own
    // before the system's.
    final ids = <String>{};
    for (final dir in [
      '$dataHome/applications',
      '$dataHome/flatpak/exports/share/applications',
      for (final d in dataDirs) '$d/applications',
      '/var/lib/flatpak/exports/share/applications',
      '/var/lib/snapd/desktop/applications',
      if (sandboxed) ...[
        '/run/host/var/lib/flatpak/exports/share/applications',
        '/run/host/var/lib/snapd/desktop/applications',
      ],
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

/// Why [command] can't open a repository, if it can't: a path that isn't
/// there, a folder (bar a macOS app bundle), a file that isn't a program,
/// or, on Linux, a command not on PATH. Null when it looks fine (macOS
/// also takes apps by name, which only opening tells).
String? openWithProblem(String command, {bool? macOS, bool? windows}) {
  command = command.trim();
  final mac = macOS ?? Platform.isMacOS;
  final win = windows ?? Platform.isWindows;
  if (command.isEmpty) return 'Enter an app or a command';
  if (command.startsWith(desktopPrefix)) {
    final file = command.substring(desktopPrefix.length);
    return readDesktopEntry(file) == null
        ? '$file is gone: the app may have been uninstalled'
        : null;
  }
  if (command.contains('/') || (win && command.contains(r'\'))) {
    final seen = sandboxPath(command);
    switch (FileSystemEntity.typeSync(seen)) {
      case FileSystemEntityType.notFound:
        return '$command doesn\'t exist';
      case FileSystemEntityType.directory:
        if (mac && command.endsWith('.app')) return null;
        return '$command is a folder, not a program';
      default:
        // Anyone may run it.
        if (!win && File(seen).statSync().mode & 0x49 == 0) {
          return '$command isn\'t a program (it can\'t be run)';
        }
        return null;
    }
  }
  if (!mac && !win && findExecutable(command) == null) {
    return 'No $command command found';
  }
  return null;
}

/// Starts a program, not waiting for it: replaced in tests.
@visibleForTesting
Future<void> Function(String exe, List<String> args, String workingDirectory)
startDetached = (exe, args, cwd) async {
  final (program, argv) = startCommand(
    exe,
    args,
    cwd: cwd,
    path: userPath,
    flatpak: GitRunner.inFlatpak,
  );
  await Process.start(
    program,
    argv,
    workingDirectory: cwd,
    // The user's PATH, for the app and what it starts.
    environment: {'PATH': ?userPath},
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
/// A [terminal] app, or an installed one that says it is, runs in
/// [terminalApp] (a terminal's path), on Linux.
Future<void> openWith(
  String command,
  String path, {
  bool terminal = false,
  String? terminalApp,
}) {
  command = command.trim();
  List<String> argv;
  if (command.startsWith(desktopPrefix)) {
    final file = command.substring(desktopPrefix.length);
    final entry = readDesktopEntry(file);
    if (entry == null) throw FileSystemException('Not found', file);
    argv = execArgs(entry.exec, path);
    terminal |= entry.terminal;
  } else {
    final exe = command.contains(Platform.pathSeparator)
        ? command
        : findExecutable(command);
    if (Platform.isMacOS && (command.endsWith('.app') || exe == null)) {
      return startDetached('open', ['-a', command, path], path);
    }
    argv = [exe ?? command, path];
  }
  if (terminal && !Platform.isMacOS && !Platform.isWindows) {
    if (terminalApp == null) throw StateError('No terminal found');
    argv = [terminalApp, ...terminalArgs(terminalApp, path, argv)];
  }
  return startDetached(argv.first, argv.sublist(1), path);
}

/// The terminals known, by command, and how each runs a command line in a
/// folder (most also start in their own working directory, the folder).
final _terminals = <String, List<String> Function(String, List<String>)>{
  // The user's pick of terminal, where the desktop has the standard's.
  'xdg-terminal-exec': (dir, cmd) => cmd,
  'cosmic-term': (dir, cmd) => ['-w', dir, '--', ...cmd],
  'ptyxis': (dir, cmd) => [
    '--new-window',
    '--working-directory=$dir',
    '--',
    ...cmd,
  ],
  'kgx': (dir, cmd) => ['--working-directory=$dir', '--', ...cmd],
  'gnome-terminal': (dir, cmd) => ['--working-directory=$dir', '--', ...cmd],
  'konsole': (dir, cmd) => ['--workdir', dir, '-e', ...cmd],
  'xfce4-terminal': (dir, cmd) => ['--working-directory=$dir', '-x', ...cmd],
  'kitty': (dir, cmd) => ['--directory', dir, ...cmd],
  'ghostty': (dir, cmd) => ['--working-directory=$dir', '-e', ...cmd],
  'wezterm': (dir, cmd) => ['start', '--cwd', dir, '--', ...cmd],
  'alacritty': (dir, cmd) => ['--working-directory', dir, '-e', ...cmd],
  'foot': (dir, cmd) => ['--working-directory=$dir', ...cmd],
  'terminator': (dir, cmd) => ['--working-directory=$dir', '-x', ...cmd],
  'urxvt': (dir, cmd) => ['-cd', dir, '-e', ...cmd],
  'xterm': (dir, cmd) => ['-e', ...cmd],
};

/// The terminals each desktop comes with (by `XDG_CURRENT_DESKTOP`).
const _desktopTerminals = {
  'COSMIC': ['cosmic-term'],
  'KDE': ['konsole'],
  'GNOME': ['ptyxis', 'kgx', 'gnome-terminal'],
  'XFCE': ['xfce4-terminal'],
};

/// The arguments that make [terminal] (its path or command) run [command]
/// in [dir]: `-e` and the command, for a terminal not known.
List<String> terminalArgs(String terminal, String dir, List<String> command) =>
    (_terminals[p.basename(terminal)] ?? (_, cmd) => ['-e', ...cmd])(
      dir,
      command,
    );

/// The terminals installed (their paths), the likeliest pick first: the
/// one `$TERMINAL` names, `xdg-terminal-exec` (which runs the user's pick),
/// the desktop's own, then the others known. None on macOS and Windows.
List<String> findTerminals({
  Map<String, String>? environment,
  bool? linux,
  bool Function(String path)? exists,
}) {
  if (!(linux ?? (!Platform.isMacOS && !Platform.isWindows))) return const [];
  final env = environment ?? userEnvironment;
  String? find(String name) => name.contains('/')
      ? ((exists ?? (String f) => File(sandboxPath(f)).existsSync())(name)
            ? name
            : null)
      : findExecutable(
          name,
          environment: env,
          windows: false,
          macOS: false,
          exists: exists,
        );
  final desktops = (env['XDG_CURRENT_DESKTOP'] ?? '').toUpperCase().split(':');
  final found = <String>{};
  for (final name in [
    if (env['TERMINAL'] case final t? when t.trim().isNotEmpty) t.trim(),
    'xdg-terminal-exec',
    for (final d in desktops) ...?_desktopTerminals[d],
    ..._terminals.keys,
  ]) {
    if (find(name) case final path?) found.add(path);
  }
  return found.toList();
}
