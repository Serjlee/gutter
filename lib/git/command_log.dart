import 'dart:async';

import 'package:flutter/foundation.dart';

/// One git command, for a repository's output log. It's added when the
/// command starts and completed when it exits.
class GitLogEntry {
  GitLogEntry({
    required this.id,
    required this.args,
    required this.cwd,
    required this.started,
    this.background = false,
    this.expectFailure = false,
  });

  /// Increasing, unique within the app.
  final int id;
  final List<String> args;
  final String cwd;
  final DateTime started;

  /// Run by background refreshes (status polling, file watching) rather
  /// than by something the user did.
  final bool background;

  /// A non-zero exit is an answer, not an error (e.g. `merge-base
  /// --is-ancestor`).
  final bool expectFailure;

  Duration? duration;
  int? exitCode;
  String stderr = '';

  /// Kept only when the command exits non-zero (and truncated): failures
  /// sometimes explain themselves on stdout (e.g. merge conflicts).
  String stdout = '';

  /// Why git couldn't be started at all.
  String? startError;

  bool get running => exitCode == null && startError == null;
  bool get failed =>
      startError != null ||
      (exitCode != null && exitCode != 0 && !expectFailure);

  String get commandLine => ['git', ...args.map(_quote)].join(' ');

  /// Everything the command printed, for the details view.
  String get output {
    final parts = [
      ?startError,
      if (stderr.trim().isNotEmpty) stderr.trimRight(),
      if (stdout.trim().isNotEmpty) stdout.trimRight(),
    ];
    return parts.join('\n');
  }

  static String _quote(String a) =>
      a.isEmpty || a.contains(RegExp(r'''[\s'"$\\;&|<>()*?`]'''))
      ? "'${a.replaceAll("'", r"'\''")}'"
      : a;
}

/// The commands git ran for one repository, oldest first.
class CommandLog extends ChangeNotifier {
  CommandLog({this.maxEntries = 1000});

  final int maxEntries;
  final entries = <GitLogEntry>[];
  static int _nextId = 0;

  /// Whether commands run by [body] (and whatever it awaits) are logged as
  /// background ones.
  static const _backgroundKey = #gutterBackgroundGit;

  static Future<T> background<T>(Future<T> Function() body) =>
      runZoned(body, zoneValues: {_backgroundKey: true});

  static bool get inBackground => Zone.current[_backgroundKey] == true;

  GitLogEntry start(
    List<String> args, {
    required String cwd,
    bool expectFailure = false,
  }) {
    final e = GitLogEntry(
      id: _nextId++,
      args: args,
      cwd: cwd,
      started: DateTime.now(),
      background: inBackground,
      expectFailure: expectFailure,
    );
    entries.add(e);
    if (entries.length > maxEntries) {
      // Background refreshes go first: they are the bulk of the log.
      final i = entries.indexWhere((x) => x.background && !x.running);
      entries.removeAt(i >= 0 ? i : 0);
    }
    notifyListeners();
    return e;
  }

  /// Call after updating [e].
  void changed(GitLogEntry e) => notifyListeners();

  void clear() {
    entries.removeWhere((e) => !e.running);
    notifyListeners();
  }

  GitLogEntry? byId(int id) {
    for (var i = entries.length - 1; i >= 0; i--) {
      if (entries[i].id == id) return entries[i];
    }
    return null;
  }
}
