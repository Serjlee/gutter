import 'dart:io';

import 'git_runner.dart';

/// A short, readable explanation of why a git command failed, with a hint
/// at the fix for the usual suspects (credentials, ssh, the network…).
/// The full output stays available through [gitErrorDetails].
String summarizeGitError(Object e) {
  if (e is ProcessException) {
    return 'Couldn\'t run ${e.executable}: ${e.message}. Is git installed? '
        'You can set its path in the settings on the home tab.';
  }
  if (e is! GitException) return e.toString();
  final text = '${e.stderr}\n${e.stdout}';
  final s = text.toLowerCase();
  bool has(String x) => s.contains(x);

  if (has('terminal prompts disabled') ||
      has('could not read username') ||
      has('could not read password')) {
    return 'The remote asked for a username and password, and Gutter can\'t '
        'prompt for them. Set up a credential helper (for GitHub: '
        '`gh auth setup-git`) or use an SSH remote.';
  }
  if (has('permission denied (publickey')) {
    return 'SSH authentication failed. Gutter can\'t ask for a key '
        'passphrase: add your key to the SSH agent (`ssh-add`).';
  }
  if (has('host key verification failed')) {
    return 'The server\'s SSH host key isn\'t trusted yet. Connect once from '
        'a terminal (e.g. `ssh -T git@github.com`) to accept it.';
  }
  if (has('could not resolve host')) {
    return 'Couldn\'t find the remote\'s server. Check your network '
        'connection.';
  }
  if (has('connection timed out') ||
      has('operation timed out') ||
      has('connection refused') ||
      has('failed to connect') ||
      has('network is unreachable')) {
    return 'Couldn\'t connect to the remote\'s server.';
  }
  if (has('repository not found') ||
      has('does not appear to be a git repository')) {
    return 'The remote repository wasn\'t found, or you don\'t have access '
        'to it.';
  }
  if (has('authentication failed') || has('invalid username or password')) {
    return 'The remote rejected your credentials. Check the ones your '
        'credential helper saved.';
  }
  if (has('[rejected]') && (has('fetch first') || has('non-fast-forward'))) {
    return 'The remote has commits you don\'t have. Pull first, then push.';
  }
  if (has('would be overwritten by')) {
    return 'Your local changes would be overwritten. Commit or stash them '
        'first.';
  }
  if (has('.lock') && has('file exists')) {
    return 'Another git process is working in this repository. If none is, '
        'delete the leftover .lock file in .git.';
  }
  return _firstMessage(text) ?? e.message;
}

/// The first line git flagged as the problem (`fatal:`/`error:`), without
/// the prefix, else the first line.
String? _firstMessage(String text) {
  final lines = text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) return null;
  final prefixed = RegExp(r'^(fatal|error):\s*', caseSensitive: false);
  final line = lines.firstWhere(prefixed.hasMatch, orElse: () => lines.first);
  final m = line.replaceFirst(prefixed, '');
  return m.isEmpty ? null : '${m[0].toUpperCase()}${m.substring(1)}';
}

/// The command and everything it printed, or null when there's nothing
/// more to show than the summary.
String? gitErrorDetails(Object e) {
  if (e is! GitException || e.args.isEmpty) return null;
  final cmd = e.entry?.commandLine ?? ['git', ...e.args].join(' ');
  final out = [
    e.stderr.trimRight(),
    e.stdout.trimRight(),
  ].where((x) => x.isNotEmpty).join('\n');
  return '\$ $cmd\n${out.isEmpty ? '(no output)' : out}\n'
      '(exit code ${e.exitCode})';
}
