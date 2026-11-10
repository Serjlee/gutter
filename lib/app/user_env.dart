import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../git/git_runner.dart';

/// The user's PATH, as their login shell has it ([readLoginShellPath]):
/// null until read, or if it couldn't be.
String? userPath;

/// The environment apps are looked for in: Gutter's, with the user's PATH.
Map<String, String> get userEnvironment => {
  ...Platform.environment,
  'PATH': ?userPath,
};

const _mark = '__GUTTER_PATH__';

/// The PATH the user's login shell has, its rc files run, as in a
/// terminal: Gutter started from a menu or the Dock, or sandboxed, lacks
/// what those add (`~/.cargo/bin`, nvm's, …). Sandboxed, it asks the
/// host's. Null on Windows, for shells it doesn't know, or if the shell
/// doesn't answer within [timeout].
Future<String?> readLoginShellPath({
  String? shell,
  Map<String, String>? environment,
  bool? flatpak,
  Duration timeout = const Duration(seconds: 5),
}) async {
  if (Platform.isWindows) return null;
  final sh = shell ?? Platform.environment['SHELL'] ?? '/bin/bash';
  // The PATH between marks: rc files may print more.
  final script = switch (p.basename(sh)) {
    'fish' => 'printf "$_mark%s$_mark" (string join : \$PATH)',
    'bash' ||
    'zsh' ||
    'sh' ||
    'dash' ||
    'ksh' ||
    'mksh' => 'printf "$_mark%s$_mark" "\$PATH"',
    _ => null,
  };
  if (script == null) return null;
  final (exe, args) = (flatpak ?? GitRunner.inFlatpak)
      ? ('flatpak-spawn', ['--host', sh, '-ilc', script])
      : (sh, ['-ilc', script]);
  try {
    final process = await Process.start(exe, args, environment: environment);
    // Nothing to read: an interactive shell would wait for it.
    unawaited(process.stdin.close());
    unawaited(process.stderr.drain<void>());
    final out = process.stdout.transform(utf8.decoder).join();
    final exited = await process.exitCode.timeout(
      timeout,
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
    if (exited == -1) return null;
    // (A daemon an rc file starts may keep the output open.)
    return parseShellPath(
      await out.timeout(const Duration(seconds: 1), onTimeout: () => ''),
    );
  } on ProcessException {
    return null;
  }
}

/// The PATH printed between marks in [out], if any.
String? parseShellPath(String out) {
  final m = RegExp('$_mark(.*?)$_mark', dotAll: true).firstMatch(out);
  final path = m?.group(1)?.trim();
  return path == null || path.isEmpty ? null : path;
}

/// Where the host's [path] is seen in the Flatpak sandbox: its system
/// folders are under /run/host there; the rest (home, /opt) as is.
String sandboxPath(String path, {bool? flatpak}) {
  if (!(flatpak ?? GitRunner.inFlatpak)) return path;
  for (final dir in const ['/usr/', '/bin/', '/sbin/', '/lib/', '/etc/']) {
    if (path.startsWith(dir)) return '/run/host$path';
  }
  return path;
}

/// The program and arguments that start [exe] with [args] in [cwd],
/// with the user's [path]: on the host, through `flatpak-spawn`, when
/// sandboxed ([flatpak]).
(String, List<String>) startCommand(
  String exe,
  List<String> args, {
  required String cwd,
  required String? path,
  required bool flatpak,
}) => flatpak
    ? (
        'flatpak-spawn',
        [
          '--host',
          '--directory=$cwd',
          if (path != null) '--env=PATH=$path',
          exe,
          ...args,
        ],
      )
    : (exe, args);
