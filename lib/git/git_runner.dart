import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'command_log.dart';

export 'command_log.dart' show CommandLog, GitLogEntry;

class GitException implements Exception {
  GitException(
    this.args,
    this.exitCode,
    this.stderr, {
    this.stdout = '',
    this.entry,
  });

  GitException.fromResult(GitResult r)
    : this(r.args, r.exitCode, r.stderr, stdout: r.stdout, entry: r.entry);

  final List<String> args;
  final int exitCode;
  final String stderr;
  final String stdout;

  /// The command in its repository's log, when it has one.
  final GitLogEntry? entry;

  /// Best human-readable message git gave us.
  String get message {
    final err = stderr.trim();
    if (err.isNotEmpty) return err;
    final out = stdout.trim();
    if (out.isNotEmpty) return out;
    return 'git ${args.join(' ')} failed with exit code $exitCode';
  }

  @override
  String toString() => 'GitException(git ${args.join(' ')}): $message';
}

class GitResult {
  GitResult(
    this.args,
    this.exitCode,
    this.stdoutBytes,
    this.stderr, {
    this.entry,
  });

  final List<String> args;
  final int exitCode;
  final Uint8List stdoutBytes;
  final String stderr;
  final GitLogEntry? entry;

  String? _stdout;
  String get stdout =>
      _stdout ??= utf8.decode(stdoutBytes, allowMalformed: true);
  bool get ok => exitCode == 0;
}

/// Simple async counting semaphore.
class Semaphore {
  Semaphore(this.permits);
  int permits;
  final _waiters = <Completer<void>>[];

  Future<T> run<T>(Future<T> Function() body) async {
    if (permits > 0) {
      permits--;
    } else {
      final c = Completer<void>();
      _waiters.add(c);
      await c.future;
    }
    try {
      return await body();
    } finally {
      if (_waiters.isNotEmpty) {
        _waiters.removeAt(0).complete();
      } else {
        permits++;
      }
    }
  }
}

/// Serializes async work (one at a time, FIFO).
class Mutex {
  Future<void> _last = Future.value();

  Future<T> run<T>(Future<T> Function() body) {
    final prev = _last;
    final c = Completer<void>();
    _last = c.future;
    return prev.then((_) => body()).whenComplete(c.complete);
  }
}

/// A readable reason for git failing in a folder, from its stderr: git
/// failing to run at all (e.g. macOS's stub without the command line tools,
/// or a folder macOS won't let it read) otherwise looks like "not a git
/// repository".
String explainGitFailure(String stderr, {required String gitPath}) {
  final s = stderr.toLowerCase();
  if (s.contains('not a git repository')) return 'Not a git repository';
  if (s.contains('xcrun: error') ||
      s.contains('invalid active developer path') ||
      s.contains('xcode-select')) {
    return 'The git at $gitPath needs Apple\'s command line tools: run '
        '`xcode-select --install`, or set another git (e.g. Homebrew\'s) '
        'in the home tab settings.';
  }
  if (s.contains('operation not permitted')) {
    return 'macOS blocked access to this folder. Allow Gutter in System '
        'Settings → Privacy & Security → Files and Folders (or Full Disk '
        'Access), then try again.';
  }
  if (s.contains('failed to start command')) {
    return 'Couldn\'t run $gitPath on your system. The Flatpak runs the '
        'system\'s git: install git (e.g. with your package manager).';
  }
  if (s.contains('dubious ownership')) {
    return 'git refuses this repository because another user owns it '
        '(see `git config --global --add safe.directory <path>`).';
  }
  final first = stderr
      .split('\n')
      .map((l) => l.trim())
      .firstWhere((l) => l.isNotEmpty, orElse: () => '');
  return first.isEmpty ? 'git failed' : first;
}

/// Spawns the system git binary.
class GitRunner {
  GitRunner({String? gitPath}) : gitPath = gitPath ?? resolveGitPath();

  String gitPath;

  /// Limits concurrent network operations (fetch/pull/push/clone).
  static final network = Semaphore(2);

  /// Whether Gutter runs in a Flatpak sandbox. There, git runs on the host
  /// (through `flatpak-spawn --host`), so it's the user's own git, with
  /// their config, credential helpers, signing keys and hook tools.
  static final inFlatpak =
      Platform.isLinux && File('/.flatpak-info').existsSync();

  /// The executable and arguments that run git with [args] in [cwd] and
  /// [env] added to the environment; [flatpak] wraps it in
  /// `flatpak-spawn --host`, which doesn't pass the environment on.
  static (String, List<String>) command(
    String gitPath,
    List<String> args, {
    required String cwd,
    required Map<String, String> env,
    required bool flatpak,
  }) {
    if (!flatpak) return (gitPath, args);
    return (
      'flatpak-spawn',
      [
        '--host',
        '--watch-bus', // the host git dies with the app
        '--directory=$cwd',
        for (final e in env.entries) '--env=${e.key}=${e.value}',
        gitPath,
        ...args,
      ],
    );
  }

  static String resolveGitPath() {
    // The host's PATH, not the sandbox's, decides.
    if (inFlatpak) return 'git';
    final exe = Platform.isWindows ? 'git.exe' : 'git';
    final pathEnv = Platform.environment['PATH'] ?? '';
    // Apps started from Finder/Dock only get /usr/bin:/bin:… on PATH, where
    // /usr/bin/git is a stub that fails until Apple's command line tools
    // are installed: prefer Homebrew's git, as a terminal would.
    const homebrew = ['/opt/homebrew/bin', '/usr/local/bin'];
    final dirs = [
      if (Platform.isMacOS) ...homebrew,
      ...pathEnv.split(Platform.isWindows ? ';' : ':'),
      ...homebrew,
      '/usr/bin',
      '/bin',
    ];
    for (final d in dirs) {
      if (d.isEmpty) continue;
      final f = File('$d${Platform.pathSeparator}$exe');
      if (f.existsSync()) return f.path;
    }
    return exe;
  }

  static const _baseArgs = [
    // Never take the index lock just to refresh stat info: keeps status
    // polling from rewriting .git/index (and from racing the user's git).
    '--no-optional-locks',
    '-c',
    'color.ui=false',
    '-c',
    'core.quotepath=false',
    '-c',
    'log.showSignature=false',
    '--no-pager',
  ];

  static Map<String, String> baseEnvironment() => {
    'GIT_TERMINAL_PROMPT': '0',
    'GIT_EDITOR': 'true',
    'GIT_SEQUENCE_EDITOR': 'true',
    'GIT_MERGE_AUTOEDIT': 'no',
    'LC_ALL': 'C',
    'LANG': 'C',
  };

  /// Environment for commands that may connect over ssh: never block on a
  /// passphrase or host-key prompt, unless the user set up how git runs ssh
  /// (core.sshCommand, GIT_SSH_COMMAND or GIT_SSH), which our
  /// GIT_SSH_COMMAND would override.
  Future<Map<String, String>> sshEnvironment(
    String cwd, {
    CommandLog? log,
  }) async {
    final env = Platform.environment;
    if (env.containsKey('GIT_SSH_COMMAND') || env.containsKey('GIT_SSH')) {
      return const {};
    }
    final res = await run(
      ['config', '--get', 'core.sshCommand'],
      cwd: cwd,
      allowFailure: true,
      log: log,
    );
    if (res.ok && res.stdout.trim().isNotEmpty) return const {};
    return const {'GIT_SSH_COMMAND': 'ssh -oBatchMode=yes'};
  }

  /// Runs git and returns the result. Throws [GitException] on non-zero exit
  /// unless [allowFailure] is true. With a [log], the command is recorded
  /// there.
  Future<GitResult> run(
    List<String> args, {
    required String cwd,
    List<int>? stdin,
    Map<String, String>? env,
    bool allowFailure = false,
    CommandLog? log,
  }) async {
    final entry = log?.start(args, cwd: cwd, expectFailure: allowFailure);
    final sw = Stopwatch()..start();
    final environment = {...baseEnvironment(), ...?env};
    final (exe, argv) = command(
      gitPath,
      [..._baseArgs, ...args],
      cwd: cwd,
      env: environment,
      flatpak: inFlatpak,
    );
    final Process process;
    try {
      process = await Process.start(
        exe,
        argv,
        workingDirectory: cwd,
        environment: environment,
      );
    } catch (e) {
      if (entry != null) {
        entry
          ..duration = sw.elapsed
          ..startError = e is ProcessException
              ? 'Couldn\'t run ${e.executable}: ${e.message}'
              : e.toString();
        log!.changed(entry);
      }
      rethrow;
    }
    final out = BytesBuilder(copy: false);
    final err = BytesBuilder(copy: false);
    final outDone = process.stdout.forEach(out.add);
    final errDone = process.stderr.forEach(err.add);
    if (stdin != null) {
      process.stdin.add(stdin);
    }
    await process.stdin.close().catchError((_) {});
    await Future.wait([outDone, errDone]);
    final code = await process.exitCode;
    sw.stop();
    final stderr = utf8.decode(err.takeBytes(), allowMalformed: true);
    final result = GitResult(args, code, out.takeBytes(), stderr, entry: entry);
    if (entry != null) {
      entry
        ..duration = sw.elapsed
        ..exitCode = code
        ..stderr = _truncate(stderr);
      if (code != 0) entry.stdout = _truncate(result.stdout);
      log!.changed(entry);
    }
    if (code != 0 && !allowFailure) throw GitException.fromResult(result);
    return result;
  }

  static String _truncate(String s, [int max = 16000]) =>
      s.length <= max ? s : '${s.substring(0, max)}\n… (truncated)';
}
