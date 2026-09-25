import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'git_runner.dart';
import 'models.dart';
import 'parsers/diff_parser.dart';
import 'parsers/log_parser.dart';
import 'parsers/refs_parser.dart';
import 'parsers/status_parser.dart';
import 'rebase_plan.dart';

enum ResetMode { soft, mixed, hard }

enum PullMode { ffOnly, merge, rebase }

enum MergeMode { auto, noFastForward, fastForwardOnly, squash }

/// High level git API for one repository working tree.
class Repository {
  Repository(this.path, {GitRunner? runner}) : git = runner ?? GitRunner();

  /// Absolute path to the working tree root.
  final String path;
  final GitRunner git;
  final _mutex = Mutex();
  String? _gitDir;

  String get name => p.basename(path);

  /// Returns the worktree root containing [dir], or null if not a repo.
  static Future<String?> findRoot(String dir, {GitRunner? runner}) async {
    final r = runner ?? GitRunner();
    try {
      final res = await r.run(
        ['rev-parse', '--show-toplevel'],
        cwd: dir,
        allowFailure: true,
        logCommand: false,
      );
      if (!res.ok) return null;
      final out = res.stdout.trim();
      return out.isEmpty ? null : p.normalize(out);
    } on ProcessException {
      return null;
    }
  }

  static Future<void> init(String dir, {GitRunner? runner}) async {
    await Directory(dir).create(recursive: true);
    await (runner ?? GitRunner()).run(['init'], cwd: dir);
  }

  static Future<void> clone(String url, String dir, {GitRunner? runner}) async {
    final r = runner ?? GitRunner();
    final parent = p.dirname(dir);
    await Directory(parent).create(recursive: true);
    await GitRunner.network.run(
      () => r.run(['clone', '--progress', url, dir], cwd: parent),
    );
  }

  Future<GitResult> _run(
    List<String> args, {
    List<int>? stdin,
    Map<String, String>? env,
    bool allowFailure = false,
  }) => git.run(
    args,
    cwd: path,
    stdin: stdin,
    env: env,
    allowFailure: allowFailure,
  );

  Future<String> _out(List<String> args) async => (await _run(args)).stdout;

  /// Serializes mutating commands.
  Future<T> _mutate<T>(Future<T> Function() body) => _mutex.run(body);

  Future<GitResult> _net(List<String> args) =>
      GitRunner.network.run(() => _mutate(() => _run(args)));

  Future<String> gitDir() async {
    return _gitDir ??= p.normalize(
      (await _out(['rev-parse', '--absolute-git-dir'])).trim(),
    );
  }

  /// Writes git's commit-graph cache if the repository has none. It makes
  /// history walks (and so graph loading) several times faster on large
  /// repositories; git itself maintains it during gc/maintenance, but fresh
  /// clones start without one. Returns true if a graph was written.
  Future<bool> ensureCommitGraph() async {
    final info = (await _out(['rev-parse', '--git-path', 'objects/info']))
        .trim();
    final dir = p.isAbsolute(info) ? info : p.join(path, info);
    if (File(p.join(dir, 'commit-graph')).existsSync() ||
        Directory(p.join(dir, 'commit-graphs')).existsSync()) {
      return false;
    }
    final res = await _run([
      'commit-graph',
      'write',
      '--reachable',
    ], allowFailure: true);
    return res.ok;
  }

  // ---------------------------------------------------------------- reads

  /// Commits of all refs (except stash), newest first in date order.
  Future<List<Commit>> log({int maxCount = 20000}) async {
    final bytes = await logBytes(maxCount: maxCount);
    if (bytes.length < 256 * 1024) return parseLog(bytes);
    return Isolate.run(() => parseLog(bytes));
  }

  /// Raw output for [parseLog]; lets callers parse (and lay out) in an
  /// isolate of their own.
  /// [maxCount] 0 loads the whole history.
  Future<Uint8List> logBytes({int maxCount = 20000}) async {
    final res = await _run([
      'log',
      '--exclude=refs/stash',
      '--all',
      '--date-order',
      '-z',
      '--format=$logFormat',
      if (maxCount > 0) ...['-n', '$maxCount'],
    ], allowFailure: true);
    if (!res.ok) {
      // Empty repository (no commits yet).
      if (res.stderr.contains('does not have any commits') ||
          res.stderr.contains('bad default revision') ||
          res.stderr.contains('unknown revision')) {
        return Uint8List(0);
      }
      throw GitException(res.args, res.exitCode, res.stderr);
    }
    return res.stdoutBytes;
  }

  Future<List<GitRef>> refs() async {
    final out = await _out(['for-each-ref', '--format=$refsFormat']);
    return parseRefs(out);
  }

  Future<WorkingTreeStatus> status() async {
    final out = await _out([
      'status',
      '--porcelain=v2',
      '-z',
      '--branch',
      '--untracked-files=all',
    ]);
    return parseStatus(out);
  }

  Future<List<StashEntry>> stashes() async {
    final res = await _run([
      'stash',
      'list',
      '-z',
      '--format=%H%x00%P%x00%ct%x00%an%x00%ae%x00%gs',
    ], allowFailure: true);
    if (!res.ok) return const [];
    final f = res.stdout.split('\x00');
    final out = <StashEntry>[];
    for (var i = 0; i + 6 <= f.length; i += 6) {
      final sha = f[i].trim();
      if (sha.isEmpty) continue;
      out.add(
        StashEntry(
          index: out.length,
          sha: sha,
          parents: f[i + 1].isEmpty ? const [] : f[i + 1].split(' '),
          time: int.tryParse(f[i + 2]) ?? 0,
          authorName: f[i + 3],
          authorEmail: f[i + 4],
          message: f[i + 5],
        ),
      );
    }
    return out;
  }

  Future<List<RemoteInfo>> remotes() async {
    final out = await _out(['remote', '-v']);
    final map = <String, RemoteInfo>{};
    for (final line in const LineSplitter().convert(out)) {
      final m = RegExp(r'^(\S+)\s+(\S+)\s+\((fetch|push)\)$').firstMatch(line);
      if (m == null) continue;
      final name = m.group(1)!;
      final url = m.group(2)!;
      final existing = map[name];
      if (m.group(3) == 'fetch') {
        map[name] = RemoteInfo(
          name: name,
          fetchUrl: url,
          pushUrl: existing?.pushUrl,
        );
      } else {
        map[name] = RemoteInfo(
          name: name,
          fetchUrl: existing?.fetchUrl ?? url,
          pushUrl: url,
        );
      }
    }
    return map.values.toList();
  }

  /// The operation git is currently in the middle of, if any.
  Future<RepoOperation> operation() async {
    final dir = await gitDir();
    bool exists(String f) =>
        FileSystemEntity.typeSync(p.join(dir, f)) !=
        FileSystemEntityType.notFound;
    if (exists('rebase-merge') || exists('rebase-apply')) {
      return RepoOperation.rebase;
    }
    if (exists('MERGE_HEAD')) return RepoOperation.merge;
    if (exists('CHERRY_PICK_HEAD')) return RepoOperation.cherryPick;
    if (exists('REVERT_HEAD')) return RepoOperation.revert;
    if (exists('BISECT_LOG')) return RepoOperation.bisect;
    return RepoOperation.none;
  }

  /// Short description of a stopped rebase (e.g. "3/7").
  Future<String?> rebaseProgress() async {
    final dir = await gitDir();
    for (final d in ['rebase-merge', 'rebase-apply']) {
      final base = p.join(dir, d);
      final next = File(p.join(base, d == 'rebase-merge' ? 'msgnum' : 'next'));
      final last = File(p.join(base, d == 'rebase-merge' ? 'end' : 'last'));
      if (next.existsSync() && last.existsSync()) {
        return '${next.readAsStringSync().trim()}/${last.readAsStringSync().trim()}';
      }
    }
    return null;
  }

  Future<String?> headSha() async {
    final res = await _run([
      'rev-parse',
      '--verify',
      '-q',
      'HEAD',
    ], allowFailure: true);
    return res.ok ? res.stdout.trim() : null;
  }

  Future<CommitDetails> commitDetails(String sha) async {
    final out = await _out([
      'log',
      '-1',
      '--no-walk',
      '--format=$detailsFormat',
      sha,
    ]);
    return parseCommitDetails(out);
  }

  /// Files changed by a commit (compared to its first parent).
  Future<List<FileChange>> commitFiles(Commit commit) async {
    if (commit.parents.isEmpty) {
      return parseNameStatus(
        await _out([
          'diff-tree',
          '-r',
          '-z',
          '--no-commit-id',
          '--name-status',
          '-M',
          '--root',
          commit.sha,
        ]),
      );
    }
    return parseNameStatus(
      await _out([
        'diff',
        '-z',
        '--name-status',
        '-M',
        commit.parents.first,
        commit.sha,
      ]),
    );
  }

  static const _emptyTree = '4b825dc642cb6eb9a060e54bf8d69288fbee4904';

  Future<FileDiff?> commitFileDiff(
    Commit commit,
    FileChange file, {
    int context = 3,
  }) async {
    final base = commit.parents.isEmpty ? _emptyTree : commit.parents.first;
    final paths = [if (file.oldPath != null) file.oldPath!, file.path];
    final out = await _out([
      'diff',
      '-M',
      '-U$context',
      base,
      commit.sha,
      '--',
      ...paths,
    ]);
    final diffs = parseDiff(out);
    return diffs.isEmpty ? null : diffs.first;
  }

  /// Diff of a working tree file: staged (index vs HEAD) or unstaged
  /// (worktree vs index). Untracked files are diffed against /dev/null.
  Future<FileDiff?> workingDiff(
    StatusEntry entry, {
    required bool staged,
    int context = 3,
  }) async {
    GitResult res;
    if (!staged && entry.isUntracked) {
      res = await _run([
        'diff',
        '--no-index',
        '-U$context',
        '--',
        '/dev/null',
        entry.path,
      ], allowFailure: true); // exits 1 when files differ
    } else {
      res = await _run([
        'diff',
        if (staged) '--cached',
        '-M',
        '-U$context',
        '--',
        if (entry.oldPath != null && staged) entry.oldPath!,
        entry.path,
      ], allowFailure: true);
    }
    if (res.exitCode > 1) {
      throw GitException(res.args, res.exitCode, res.stderr);
    }
    final diffs = parseDiff(res.stdout);
    return diffs.isEmpty ? null : diffs.first;
  }

  /// Contents of [filePath] at [rev]; null [rev] reads the working tree.
  Future<Uint8List?> fileContent(String? rev, String filePath) async {
    if (rev == null) {
      final f = File(p.join(path, filePath));
      if (!f.existsSync()) return null;
      return f.readAsBytes();
    }
    final res = await _run(['show', '$rev:$filePath'], allowFailure: true);
    return res.ok ? res.stdoutBytes : null;
  }

  /// Commits in `base..HEAD` for interactive rebase, oldest first, with
  /// full messages. A null [base] means from the root commit.
  Future<List<RebaseStep>> rebaseCandidates(String? base) async {
    final out = await _out([
      'log',
      '--reverse',
      '--topo-order',
      '--no-merges',
      '-z',
      '--format=%H%x00%s%x00%B',
      base == null ? 'HEAD' : '$base..HEAD',
    ]);
    final f = out.split('\x00');
    final steps = <RebaseStep>[];
    for (var i = 0; i + 3 <= f.length; i += 3) {
      final sha = f[i].trim();
      if (sha.isEmpty) continue;
      steps.add(
        RebaseStep(sha: sha, subject: f[i + 1], message: f[i + 2].trimRight()),
      );
    }
    return steps;
  }

  Future<bool> rangeHasMerges(String? base) async {
    final out = await _out([
      'rev-list',
      '--merges',
      '-n',
      '1',
      base == null ? 'HEAD' : '$base..HEAD',
    ]);
    return out.trim().isNotEmpty;
  }

  Future<String> lastCommitMessage() async =>
      (await _out(['log', '-1', '--format=%B'])).trimRight();

  Future<String?> configValue(String key) async {
    final res = await _run(['config', '--get', key], allowFailure: true);
    return res.ok ? res.stdout.trim() : null;
  }

  // -------------------------------------------------------------- staging

  Future<void> stage(List<String> paths) => _mutate(() async {
    if (paths.isEmpty) return;
    await _run(['add', '-A', '--', ...paths]);
  });

  Future<void> stageAll() => _mutate(() => _run(['add', '-A']));

  Future<void> unstage(List<String> paths) => _mutate(() async {
    if (paths.isEmpty) return;
    if (await headSha() == null) {
      await _run(['rm', '--cached', '-r', '-q', '--', ...paths]);
    } else {
      await _run(['reset', '-q', 'HEAD', '--', ...paths]);
    }
  });

  Future<void> unstageAll() => _mutate(() async {
    if (await headSha() == null) {
      await _run(['rm', '--cached', '-r', '-q', '.']);
    } else {
      await _run(['reset', '-q', 'HEAD']);
    }
  });

  /// Discards worktree changes of [entries] (deleting untracked files).
  Future<void> discard(List<StatusEntry> entries) => _mutate(() async {
    final tracked = entries
        .where((e) => !e.isUntracked)
        .map((e) => e.path)
        .toList();
    final untracked = entries
        .where((e) => e.isUntracked)
        .map((e) => e.path)
        .toList();
    if (tracked.isNotEmpty) {
      await _run(['checkout', '--', ...tracked]);
    }
    for (final u in untracked) {
      final f = File(p.join(path, u));
      if (f.existsSync()) await f.delete();
    }
  });

  /// Mark an untracked file as intent-to-add so its hunks can be staged.
  Future<void> intentToAdd(String filePath) =>
      _mutate(() => _run(['add', '-N', '--', filePath]));

  Future<void> applyPatch(
    String patch, {
    bool cached = true,
    bool reverse = false,
  }) => _mutate(
    () => _run([
      'apply',
      if (cached) '--cached',
      if (reverse) '--reverse',
      '--recount',
      '--unidiff-zero',
      '--whitespace=nowarn',
      '-',
    ], stdin: utf8.encode(patch)),
  );

  Future<void> commit(String message, {bool amend = false}) => _mutate(
    () => _run([
      'commit',
      if (amend) '--amend',
      '--cleanup=strip',
      '-F',
      '-',
    ], stdin: utf8.encode(message)),
  );

  // ------------------------------------------------------------- branches

  Future<void> checkout(String ref) => _mutate(() => _run(['checkout', ref]));

  /// Checks out a remote branch, creating/using a local tracking branch.
  /// Checks out the local branch for [remoteRef], creating a tracking
  /// branch if there is none, and fast-forwards it to the remote commit
  /// when it is behind. A local branch that is ahead or has diverged is
  /// only checked out: updating it would drop its own commits.
  Future<RemoteCheckout> checkoutRemote(
    GitRef remoteRef,
    List<GitRef> allRefs,
  ) => _mutate(() async {
    final local = remoteRef.remoteBranchName;
    final localRef = allRefs
        .where((r) => r.type == RefType.localBranch && r.name == local)
        .firstOrNull;
    if (localRef == null) {
      await _run(['checkout', '-b', local, '--track', remoteRef.name]);
      return RemoteCheckout.created;
    }
    await _run(['checkout', local]);
    if (localRef.sha == remoteRef.sha) return RemoteCheckout.upToDate;
    if (await _isAncestor(localRef.sha, remoteRef.sha)) {
      await _run(['merge', '--ff-only', remoteRef.sha]);
      return RemoteCheckout.fastForwarded;
    }
    return await _isAncestor(remoteRef.sha, localRef.sha)
        ? RemoteCheckout.ahead
        : RemoteCheckout.diverged;
  });

  Future<bool> _isAncestor(String ancestor, String of) async {
    final res = await _run([
      'merge-base',
      '--is-ancestor',
      ancestor,
      of,
    ], allowFailure: true);
    if (res.exitCode > 1) {
      throw GitException(res.args, res.exitCode, res.stderr);
    }
    return res.exitCode == 0;
  }

  Future<void> createBranch(
    String name, {
    String? startPoint,
    bool checkout = true,
  }) => _mutate(
    () => checkout
        ? _run(['checkout', '-b', name, ?startPoint])
        : _run(['branch', name, ?startPoint]),
  );

  Future<void> deleteBranch(String name, {bool force = false}) =>
      _mutate(() => _run(['branch', force ? '-D' : '-d', name]));

  Future<void> renameBranch(String from, String to) =>
      _mutate(() => _run(['branch', '-m', from, to]));

  Future<void> setUpstream(String branch, String upstream) =>
      _mutate(() => _run(['branch', '--set-upstream-to=$upstream', branch]));

  Future<void> deleteRemoteBranch(String remote, String branch) =>
      _net(['push', remote, '--delete', branch]);

  Future<void> createTag(String name, String sha, {String? message}) => _mutate(
    () => _run([
      'tag',
      if (message != null && message.trim().isNotEmpty) ...[
        '-a',
        '-m',
        message,
      ],
      name,
      sha,
    ]),
  );

  Future<void> deleteTag(String name) =>
      _mutate(() => _run(['tag', '-d', name]));

  Future<void> pushTag(String remote, String name) =>
      _net(['push', remote, 'refs/tags/$name']);

  Future<void> deleteRemoteTag(String remote, String name) =>
      _net(['push', remote, '--delete', 'refs/tags/$name']);

  // ------------------------------------------------------ history editing

  Future<void> merge(String ref, {MergeMode mode = MergeMode.auto}) => _mutate(
    () => _run([
      'merge',
      '--no-edit',
      switch (mode) {
        MergeMode.auto => '--ff',
        MergeMode.noFastForward => '--no-ff',
        MergeMode.fastForwardOnly => '--ff-only',
        MergeMode.squash => '--squash',
      },
      ref,
    ]),
  );

  Future<void> rebase(String onto) => _mutate(() => _run(['rebase', onto]));

  /// Runs an interactive rebase of `base..HEAD` using [plan].
  Future<void> rebaseInteractive(String? base, RebasePlan plan) =>
      _mutate(() async {
        final dir = Directory(p.join(await gitDir(), 'gutter-rebase'));
        if (dir.existsSync()) dir.deleteSync(recursive: true);
        dir.createSync(recursive: true);
        var n = 0;
        final todo = plan.buildTodo((message) {
          final f = File(p.join(dir.path, 'msg-${n++}.txt'));
          f.writeAsStringSync(message.endsWith('\n') ? message : '$message\n');
          return f.path;
        });
        final todoFile = File(p.join(dir.path, 'todo.txt'))
          ..writeAsStringSync(todo);
        await _run(
          [
            '-c',
            'rebase.missingCommitsCheck=ignore',
            '-c',
            'rebase.abbreviateCommands=false',
            '-c',
            'rebase.autoSquash=false',
            'rebase',
            '-i',
            base ?? '--root',
          ],
          env: {'GIT_SEQUENCE_EDITOR': 'cp ${shellQuote(todoFile.path)}'},
        );
      });

  /// Removes temp files from a finished interactive rebase.
  Future<void> cleanupRebaseFiles() async {
    final dir = Directory(p.join(await gitDir(), 'gutter-rebase'));
    if (dir.existsSync() && await operation() != RepoOperation.rebase) {
      dir.deleteSync(recursive: true);
    }
  }

  Future<void> cherryPick(Commit c) => _mutate(
    () => _run([
      'cherry-pick',
      if (c.isMerge) ...['-m', '1'],
      c.sha,
    ]),
  );

  /// Cherry-picks [commits] (oldest first) in one sequence; on a conflict
  /// git stops and the rest follow `cherry-pick --continue`.
  Future<void> cherryPickAll(List<Commit> commits) => _mutate(
    () => _run([
      'cherry-pick',
      if (commits.any((c) => c.isMerge)) ...['-m', '1'],
      for (final c in commits) c.sha,
    ]),
  );

  Future<void> revert(Commit c) => _mutate(
    () => _run([
      'revert',
      '--no-edit',
      if (c.isMerge) ...['-m', '1'],
      c.sha,
    ]),
  );

  Future<void> reset(String sha, ResetMode mode) =>
      _mutate(() => _run(['reset', '--${mode.name}', sha]));

  Future<void> continueOperation(RepoOperation op) =>
      _mutate(() => _run([op.command, '--continue']));

  Future<void> abortOperation(RepoOperation op) =>
      _mutate(() => _run([op.command, '--abort']));

  Future<void> skipOperation(RepoOperation op) =>
      _mutate(() => _run([op.command, '--skip']));

  /// Resolves a conflicted file with one side and stages it.
  Future<void> resolveWith(String filePath, {required bool ours}) =>
      _mutate(() async {
        await _run(['checkout', ours ? '--ours' : '--theirs', '--', filePath]);
        await _run(['add', '--', filePath]);
      });

  Future<void> markResolved(List<String> paths) =>
      _mutate(() => _run(['add', '--', ...paths]));

  // ----------------------------------------------------------------- stash

  Future<void> stashPush({String? message, bool includeUntracked = true}) =>
      _mutate(
        () => _run([
          'stash',
          'push',
          if (includeUntracked) '--include-untracked',
          if (message != null && message.trim().isNotEmpty) ...['-m', message],
        ]),
      );

  Future<void> stashApply(int index) =>
      _mutate(() => _run(['stash', 'apply', '--index', 'stash@{$index}']));

  Future<void> stashPop(int index) =>
      _mutate(() => _run(['stash', 'pop', '--index', 'stash@{$index}']));

  Future<void> stashDrop(int index) =>
      _mutate(() => _run(['stash', 'drop', 'stash@{$index}']));

  // --------------------------------------------------------------- network

  Future<void> fetch({String? remote, bool prune = true}) => _net([
    // Keep the commit-graph cache current so history loads stay fast.
    '-c',
    'fetch.writeCommitGraph=true',
    'fetch',
    if (remote == null) '--all' else remote,
    if (prune) '--prune',
    '--tags',
    '--quiet',
  ]);

  Future<void> pull(PullMode mode) => _net([
    'pull',
    switch (mode) {
      PullMode.ffOnly => '--ff-only',
      PullMode.merge => '--no-rebase',
      PullMode.rebase => '--rebase',
    },
  ]);

  /// Whether a failed push was rejected because the remote branch has
  /// commits the local one doesn't (a force push would overwrite them).
  /// Not true for a stale force-with-lease, which needs a fetch instead.
  static bool isNonFastForwardRejection(Object error) {
    if (error is! GitException) return false;
    final err = error.stderr;
    return err.contains('[rejected]') &&
        (err.contains('(non-fast-forward)') || err.contains('(fetch first)'));
  }

  /// Pushes [branch] (default: current). Sets upstream on [remote] when the
  /// branch has none.
  Future<void> push({
    required String branch,
    String? remote,
    String? remoteBranch,
    bool setUpstream = false,
    bool forceWithLease = false,
  }) => _net([
    'push',
    if (forceWithLease) '--force-with-lease',
    if (setUpstream) '--set-upstream',
    remote ?? 'origin',
    'refs/heads/$branch:refs/heads/${remoteBranch ?? branch}',
  ]);
}
