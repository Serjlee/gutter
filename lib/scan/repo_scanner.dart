import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

/// Directory names never descended into while scanning.
const defaultSkipDirs = {
  'node_modules',
  'build',
  'target',
  'dist',
  'Pods',
  'DerivedData',
  'vendor',
  '__pycache__',
  'venv',
};

/// Finds git repositories below a root directory.
///
/// A directory containing `.git` (a directory, or a file for worktrees and
/// submodules) is a repository. The walk keeps descending into repositories
/// (to find nested ones) but never into `.git` itself, dot-directories, or
/// [defaultSkipDirs]. Symlinks are not followed.
class RepoScan {
  RepoScan._(this._results, this._isolate, this._done);

  final Stream<String> _results;
  final Isolate? _isolate;
  final Future<void> _done;

  Stream<String> get results => _results;
  Future<void> get done => _done;

  static Future<RepoScan> start(String root, {int maxDepth = 8}) async {
    final controller = StreamController<String>();
    final port = ReceivePort();
    final done = Completer<void>();
    final isolate = await Isolate.spawn(_scanEntry, [
      port.sendPort,
      root,
      maxDepth,
    ], errorsAreFatal: false);
    port.listen((msg) {
      if (msg is String) {
        controller.add(msg);
      } else {
        port.close();
        controller.close();
        if (!done.isCompleted) done.complete();
      }
    });
    isolate.addOnExitListener(port.sendPort, response: null);
    return RepoScan._(controller.stream, isolate, done.future);
  }

  void cancel() => _isolate?.kill(priority: Isolate.immediate);

  /// Synchronous scan (used by the isolate and in tests).
  static void scanSync(String root, int maxDepth, void Function(String) found) {
    void walk(Directory dir, int depth) {
      List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } catch (_) {
        return; // permission denied etc.
      }
      var isRepo = false;
      final subdirs = <Directory>[];
      for (final e in entries) {
        final name = p.basename(e.path);
        if (name == '.git') {
          isRepo = true;
          continue;
        }
        if (e is Directory) {
          if (name.startsWith('.') || defaultSkipDirs.contains(name)) continue;
          subdirs.add(e);
        }
      }
      if (isRepo) found(p.normalize(dir.path));
      if (depth >= maxDepth) return;
      subdirs.sort((a, b) => a.path.compareTo(b.path));
      for (final d in subdirs) {
        walk(d, depth + 1);
      }
    }

    walk(Directory(root), 0);
  }
}

void _scanEntry(List<Object> args) {
  final send = args[0] as SendPort;
  final root = args[1] as String;
  final maxDepth = args[2] as int;
  RepoScan.scanSync(root, maxDepth, send.send);
  send.send(null);
}
