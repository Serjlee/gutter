import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class GitException implements Exception {
  GitException(this.args, this.exitCode, this.stderr, [this.stdout = '']);

  final List<String> args;
  final int exitCode;
  final String stderr;
  final String stdout;

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
  GitResult(this.args, this.exitCode, this.stdoutBytes, this.stderr);

  final List<String> args;
  final int exitCode;
  final Uint8List stdoutBytes;
  final String stderr;

  String? _stdout;
  String get stdout =>
      _stdout ??= utf8.decode(stdoutBytes, allowMalformed: true);
  bool get ok => exitCode == 0;
}

/// One executed command, for the output log.
class GitLogEntry {
  GitLogEntry({
    required this.args,
    required this.cwd,
    required this.started,
    required this.duration,
    required this.exitCode,
    required this.stderr,
  });

  final List<String> args;
  final String cwd;
  final DateTime started;
  final Duration duration;
  final int exitCode;
  final String stderr;
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

/// Spawns the system git binary.
class GitRunner {
  GitRunner({String? gitPath}) : gitPath = gitPath ?? resolveGitPath();

  String gitPath;

  /// Limits concurrent network operations (fetch/pull/push/clone).
  static final network = Semaphore(2);

  /// Recent command log, newest last. Listeners are notified on append.
  static final log = <GitLogEntry>[];
  static final _logController = StreamController<GitLogEntry>.broadcast();
  static Stream<GitLogEntry> get onLog => _logController.stream;

  static String resolveGitPath() {
    final exe = Platform.isWindows ? 'git.exe' : 'git';
    final pathEnv = Platform.environment['PATH'] ?? '';
    final dirs = [
      ...pathEnv.split(Platform.isWindows ? ';' : ':'),
      '/opt/homebrew/bin',
      '/usr/local/bin',
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
        // Never block on ssh host-key prompts.
        'GIT_SSH_COMMAND':
            Platform.environment['GIT_SSH_COMMAND'] ?? 'ssh -oBatchMode=yes',
      };

  /// Runs git and returns the result. Throws [GitException] on non-zero exit
  /// unless [allowFailure] is true.
  Future<GitResult> run(
    List<String> args, {
    required String cwd,
    List<int>? stdin,
    Map<String, String>? env,
    bool allowFailure = false,
    bool logCommand = true,
  }) async {
    final started = DateTime.now();
    final sw = Stopwatch()..start();
    final process = await Process.start(
      gitPath,
      [..._baseArgs, ...args],
      workingDirectory: cwd,
      environment: {...baseEnvironment(), ...?env},
    );
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
    final result = GitResult(args, code, out.takeBytes(), stderr);
    if (logCommand) {
      final entry = GitLogEntry(
        args: args,
        cwd: cwd,
        started: started,
        duration: sw.elapsed,
        exitCode: code,
        stderr: stderr,
      );
      log.add(entry);
      if (log.length > 500) log.removeRange(0, log.length - 500);
      _logController.add(entry);
    }
    if (code != 0 && !allowFailure) {
      throw GitException(args, code, stderr, result.stdout);
    }
    return result;
  }
}
