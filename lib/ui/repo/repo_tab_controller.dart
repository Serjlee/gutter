import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../../app/app_controller.dart';
import '../../git/git_runner.dart';
import '../../git/models.dart';
import '../../git/parsers/diff_parser.dart';
import '../../git/parsers/log_parser.dart';
import '../../git/patch_builder.dart';
import '../../git/repository.dart';
import '../../graph/graph_layout.dart';
import 'auto_fetch.dart';

/// Sha used for the pseudo "work in progress" row.
const wipSha = '__WIP__';

/// Commits plus their graph layout. When [hasWip] the first row is the WIP
/// pseudo-commit.
class GraphData {
  GraphData(
    this.commits,
    this.layout, {
    required this.hasWip,
    this.truncated = false,
  });

  static final empty = GraphData(const [], GraphLayout.empty, hasWip: false);

  final List<Commit> commits;
  final GraphLayout layout;
  final bool hasWip;

  /// More history exists than was loaded.
  final bool truncated;

  int get rowCount => layout.rowCount;

  /// The commit at [row], or null for the WIP row.
  Commit? commitAt(int row) {
    if (hasWip) return row == 0 ? null : commits[row - 1];
    return commits[row];
  }

  Map<String, int>? _rows;

  /// Row index of a commit sha.
  int? rowOf(String sha) {
    if (sha == wipSha) return hasWip ? 0 : null;
    _rows ??= {
      for (var i = 0; i < commits.length; i++)
        commits[i].sha: i + (hasWip ? 1 : 0),
    };
    return _rows![sha];
  }
}

/// What the diff area shows.
sealed class DiffTarget {
  const DiffTarget();
  String get path;
}

class CommitFileTarget extends DiffTarget {
  const CommitFileTarget(this.commit, this.file);
  final Commit commit;
  final FileChange file;
  @override
  String get path => file.path;
}

class WorkingFileTarget extends DiffTarget {
  const WorkingFileTarget(this.entry, {required this.staged});
  final StatusEntry entry;
  final bool staged;
  @override
  String get path => entry.path;
}

/// State of one repository tab.
class RepoTabController extends ChangeNotifier {
  RepoTabController(this.repo, this.app);

  final Repository repo;
  final AppController app;

  GraphData graph = GraphData.empty;
  List<GitRef> refs = const [];
  Map<String, List<GitRef>> refsBySha = const {};
  WorkingTreeStatus status = WorkingTreeStatus.empty;
  List<StashEntry> stashes = const [];
  List<RemoteInfo> remotes = const [];
  RepoOperation operation = RepoOperation.none;
  String? rebaseProgress;
  String? headSha;

  bool loading = true;
  String? loadError;
  bool loadingLog = false;
  int maxCommits = 0;

  /// Label of the operation currently running (for the toolbar spinner).
  String? busy;

  // Selection.
  String? selectedSha; // wipSha for the WIP row
  CommitDetails? details;
  List<FileChange> commitFiles = const [];
  bool detailsLoading = false;

  DiffTarget? diffTarget;
  FileDiff? diff;
  bool diffLoading = false;
  String? diffError;

  // Commit composer.
  final commitMessage = TextEditingController();
  bool amend = false;

  /// Collapsed folders of the staging tree, as `section:path` keys.
  final collapsedDirs = <String>{};

  void toggleDir(String key) {
    if (!collapsedDirs.remove(key)) collapsedDirs.add(key);
    _notify();
  }

  // Search.
  String search = '';
  List<int> searchHits = const [];
  Set<int> searchHitSet = const {};

  // Fetch.
  DateTime? lastFetch;
  String? fetchError;
  bool fetching = false;

  bool _active = false;
  bool _disposed = false;
  Timer? _pollTimer;
  Timer? _fetchTimer;
  Timer? _watchDebounce;
  final _watchers = <StreamSubscription<FileSystemEvent>>[];
  String _refsSignature = '';
  Future<void>? _refreshing;
  bool _refreshQueued = false;
  int _selectToken = 0;
  int _diffToken = 0;

  /// Requests the graph to scroll to a row (consumed by the view).
  final scrollToRow = ValueNotifier<int?>(null);

  String get name => repo.name;
  String? get currentBranch => status.branch.head;
  bool get isDirty => !status.isClean;

  GitRef? get headRef {
    for (final r in refs) {
      if (r.isHead) return r;
    }
    return null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // --------------------------------------------------------------- loading

  Future<void> load() async {
    maxCommits = app.settings.maxCommits;
    loading = true;
    _notify();
    try {
      await refresh(forceLog: true);
      loadError = null;
      unawaited(_loadRemotes());
      unawaited(_startWatching());
      unawaited(_ensureCommitGraph());
    } catch (e) {
      loadError = e is GitException ? e.message : e.toString();
    } finally {
      loading = false;
      _notify();
    }
    _scheduleTimers();
  }

  Future<void> _ensureCommitGraph() async {
    try {
      if (graph.commits.length < 2000) return;
      await repo.ensureCommitGraph();
    } catch (_) {
      // Only an optimization.
    }
  }

  Future<void> _loadRemotes() async {
    try {
      remotes = await repo.remotes();
      _notify();
      _fetchSoonIfDue(); // first fetch once we know there are remotes
    } catch (_) {}
  }

  /// Re-reads refs, status, stashes and operation state; reloads history
  /// when refs moved. Concurrent calls coalesce.
  Future<void> refresh({bool forceLog = false}) async {
    if (_refreshing != null) {
      _refreshQueued = true;
      if (forceLog) _refsSignature = '';
      return _refreshing;
    }
    final f = _doRefresh(forceLog);
    _refreshing = f;
    try {
      await f;
    } finally {
      _refreshing = null;
    }
    if (_refreshQueued && !_disposed) {
      _refreshQueued = false;
      await refresh();
    }
  }

  Future<void> _doRefresh(bool forceLog) async {
    final results = await Future.wait([
      repo.refs(),
      repo.status(),
      repo.stashes(),
      repo.operation(),
      repo.headSha(),
    ]);
    if (_disposed) return;
    final newRefs = results[0] as List<GitRef>;
    final newStatus = results[1] as WorkingTreeStatus;
    stashes = results[2] as List<StashEntry>;
    operation = results[3] as RepoOperation;
    headSha = results[4] as String?;
    rebaseProgress = operation == RepoOperation.rebase
        ? await repo.rebaseProgress()
        : null;
    if (operation == RepoOperation.none) {
      unawaited(repo.cleanupRebaseFiles().catchError((_) {}));
    }

    final sig = StringBuffer(headSha ?? '')..write('|');
    for (final r in newRefs) {
      sig
        ..write(r.fullName)
        ..write(r.sha);
    }
    final signature = sig.toString();
    final refsChanged = signature != _refsSignature;
    final dirtyChanged = newStatus.isClean == graph.hasWip;

    refs = newRefs;
    status = newStatus;
    final bySha = <String, List<GitRef>>{};
    for (final r in refs) {
      if (r.isRemoteHead) continue;
      (bySha[r.sha] ??= []).add(r);
    }
    refsBySha = bySha;

    if (forceLog || refsChanged) {
      _refsSignature = signature;
      await _reloadLog();
    } else if (dirtyChanged) {
      await _relayout();
    }
    if (_disposed) return;

    // Keep the WIP selection / diff in sync with the working tree.
    if (selectedSha == wipSha && !graph.hasWip && diffTarget == null) {
      selectedSha = null;
    }
    final t = diffTarget;
    if (t is WorkingFileTarget) {
      final e = status.entries.where((e) => e.path == t.entry.path).firstOrNull;
      final stillThere = e != null && (t.staged ? e.hasStaged : e.hasUnstaged);
      if (!stillThere) {
        closeDiff(notify: false);
      } else {
        diffTarget = WorkingFileTarget(e, staged: t.staged);
        unawaited(_loadDiff(quiet: true));
      }
    }
    if (selectedSha != null &&
        selectedSha != wipSha &&
        graph.rowOf(selectedSha!) == null) {
      selectedSha = null;
      details = null;
      commitFiles = const [];
    }
    _updateSearchHits();
    _notify();
  }

  Future<void> _reloadLog() async {
    loadingLog = true;
    _notify();
    try {
      final bytes = await repo.logBytes(maxCount: maxCommits);
      final wipParent = status.isClean ? null : headSha;
      final max = maxCommits;
      graph = await Isolate.run(() => _buildGraph(bytes, wipParent, max));
    } finally {
      loadingLog = false;
    }
  }

  Future<void> _relayout() async {
    final commits = graph.commits;
    final wipParent = status.isClean ? null : headSha;
    final truncated = graph.truncated;
    if (commits.length < 5000) {
      graph = _layoutGraph(commits, wipParent, truncated);
    } else {
      graph = await Isolate.run(
        () => _layoutGraph(commits, wipParent, truncated),
      );
    }
  }

  Future<void> loadMore() async {
    if (!graph.truncated || loadingLog) return;
    maxCommits += app.settings.maxCommits;
    await _reloadLog();
    _notify();
  }

  // ----------------------------------------------------------- lifecycle

  void setActive(bool active) {
    if (_active == active) return;
    _active = active;
    if (active && !loading) {
      unawaited(refresh());
      _fetchSoonIfDue();
    }
    _scheduleTimers();
  }

  void onAppFocused() {
    if (!_active) return; // background tabs catch up when activated
    if (!loading) unawaited(refresh());
    _fetchSoonIfDue();
  }

  /// Fetches shortly if the active tab's auto-fetch is overdue.
  void _fetchSoonIfDue() {
    if (!_fetchDue()) return;
    Timer(const Duration(milliseconds: 300), () {
      if (!_disposed && _fetchDue()) unawaited(fetch(auto: true));
    });
  }

  bool _fetchDue() => isAutoFetchDue(
    now: DateTime.now(),
    active: _active,
    lastFetch: lastFetch,
    intervalMinutes: app.settings.fetchIntervalMinutes,
    focused: app.focused.value,
    hasRemotes: remotes.isNotEmpty,
    fetching: fetching,
  );

  /// Status polling and auto-fetch only run for the active tab.
  void _scheduleTimers() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _fetchTimer?.cancel();
    _fetchTimer = null;
    if (!_active || _disposed) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (app.focused.value && busy == null && _refreshing == null) {
        unawaited(refresh().catchError((_) {}));
      }
    });
    _fetchTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!_disposed && _fetchDue()) unawaited(fetch(auto: true));
    });
  }

  Future<void> _startWatching() async {
    try {
      final gitDir = await repo.gitDir();
      void onEvent(FileSystemEvent e) {
        final rel = p.relative(e.path, from: gitDir);
        if (rel.endsWith('.lock') ||
            rel.startsWith('logs') ||
            rel.startsWith('objects') ||
            rel.startsWith('gutter-rebase') ||
            rel == 'FETCH_HEAD') {
          return;
        }
        _watchDebounce?.cancel();
        _watchDebounce = Timer(const Duration(milliseconds: 250), () {
          if (!_disposed && busy == null) {
            unawaited(refresh().catchError((_) {}));
          }
        });
      }

      _watchers.add(Directory(gitDir).watch().listen(onEvent, onError: (_) {}));
      final refsDir = Directory(p.join(gitDir, 'refs'));
      if (refsDir.existsSync()) {
        _watchers.add(
          refsDir.watch(recursive: true).listen(onEvent, onError: (_) {}),
        );
      }
    } catch (_) {
      // Watching is an optimization; polling still keeps us fresh.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _fetchTimer?.cancel();
    _watchDebounce?.cancel();
    for (final w in _watchers) {
      unawaited(w.cancel());
    }
    commitMessage.dispose();
    scrollToRow.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ selection

  Future<void> select(String sha) async {
    if (selectedSha == sha && (sha == wipSha || details?.sha == sha)) return;
    selectedSha = sha;
    closeDiff(notify: false);
    final token = ++_selectToken;
    if (sha == wipSha) {
      details = null;
      commitFiles = const [];
      _notify();
      return;
    }
    detailsLoading = true;
    _notify();
    final row = graph.rowOf(sha);
    final commit = row == null ? null : graph.commitAt(row);
    try {
      final d = await repo.commitDetails(sha);
      final files = commit == null
          ? <FileChange>[]
          : await repo.commitFiles(commit);
      if (token != _selectToken) return;
      details = d;
      commitFiles = files;
    } catch (e) {
      if (token != _selectToken) return;
      details = null;
      commitFiles = const [];
      _reportError(e);
    } finally {
      if (token == _selectToken) {
        detailsLoading = false;
        _notify();
      }
    }
  }

  void selectRelative(int delta) {
    if (graph.rowCount == 0) return;
    final cur = selectedSha == null ? -1 : (graph.rowOf(selectedSha!) ?? -1);
    final next = (cur + delta).clamp(0, graph.rowCount - 1);
    final c = graph.commitAt(next);
    unawaited(select(c?.sha ?? wipSha));
    scrollToRow.value = next;
  }

  void jumpToHead() {
    final h = headSha;
    if (h == null) return;
    final row = graph.rowOf(h);
    if (row == null) return;
    unawaited(select(h));
    scrollToRow.value = row;
  }

  void jumpToSha(String sha) {
    final row = graph.rowOf(sha);
    if (row == null) {
      app.notify(
        'Commit ${sha.substring(0, min(7, sha.length))} is not loaded',
      );
      return;
    }
    unawaited(select(sha));
    scrollToRow.value = row;
  }

  void openCommitFile(Commit commit, FileChange file) {
    diffTarget = CommitFileTarget(commit, file);
    unawaited(_loadDiff());
  }

  void openWorkingFile(StatusEntry entry, {required bool staged}) {
    if (selectedSha != wipSha) {
      selectedSha = wipSha;
      details = null;
      commitFiles = const [];
    }
    diffTarget = WorkingFileTarget(entry, staged: staged);
    unawaited(_loadDiff());
  }

  void closeDiff({bool notify = true}) {
    diffTarget = null;
    diff = null;
    diffError = null;
    diffLoading = false;
    _diffToken++;
    if (notify) _notify();
  }

  Future<void> _loadDiff({bool quiet = false}) async {
    final target = diffTarget;
    if (target == null) return;
    final token = ++_diffToken;
    if (!quiet) {
      diffLoading = true;
      diff = null;
      diffError = null;
      _notify();
    }
    try {
      final FileDiff? d = switch (target) {
        final CommitFileTarget t => await repo.commitFileDiff(t.commit, t.file),
        final WorkingFileTarget t => await repo.workingDiff(
          t.entry,
          staged: t.staged,
        ),
      };
      if (token != _diffToken) return;
      // Keep the same object when nothing changed so line selections in
      // the view survive background refreshes.
      if (!quiet || _diffSignature(d) != _diffSignature(diff)) diff = d;
      diffError = null;
    } catch (e) {
      if (token != _diffToken) return;
      diffError = e is GitException ? e.message : e.toString();
    } finally {
      if (token == _diffToken) {
        diffLoading = false;
        _notify();
      }
    }
  }

  /// File bytes for the preview: at the commit, or the working tree file.
  Future<Uint8List?> previewBytes() async {
    final t = diffTarget;
    switch (t) {
      case CommitFileTarget(:final commit, :final file):
        if (file.kind == ChangeKind.deleted) {
          return commit.parents.isEmpty
              ? null
              : repo.fileContent(
                  commit.parents.first,
                  file.oldPath ?? file.path,
                );
        }
        return repo.fileContent(commit.sha, file.path);
      case WorkingFileTarget(:final entry, :final staged):
        return staged
            ? repo.fileContent('', entry.path) // ":path" = index
            : repo.fileContent(null, entry.path);
      case null:
        return null;
    }
  }

  // --------------------------------------------------------------- search

  void setSearch(String q) {
    search = q;
    _updateSearchHits();
    _notify();
  }

  void _updateSearchHits() {
    final q = search.trim().toLowerCase();
    if (q.isEmpty) {
      searchHits = const [];
      searchHitSet = const {};
      return;
    }
    final hits = <int>[];
    final off = graph.hasWip ? 1 : 0;
    for (var i = 0; i < graph.commits.length; i++) {
      final c = graph.commits[i];
      if (c.subject.toLowerCase().contains(q) ||
          c.sha.startsWith(q) ||
          c.authorName.toLowerCase().contains(q) ||
          c.authorEmail.toLowerCase().contains(q)) {
        hits.add(i + off);
      }
    }
    searchHits = hits;
    searchHitSet = hits.toSet();
  }

  void searchStep(int delta) {
    if (searchHits.isEmpty) return;
    final cur = selectedSha == null ? -1 : (graph.rowOf(selectedSha!) ?? -1);
    int target;
    if (delta > 0) {
      target = searchHits.firstWhere(
        (r) => r > cur,
        orElse: () => searchHits.first,
      );
    } else {
      target = searchHits.lastWhere(
        (r) => r < cur,
        orElse: () => searchHits.last,
      );
    }
    final c = graph.commitAt(target);
    if (c != null) unawaited(select(c.sha));
    scrollToRow.value = target;
  }

  // ------------------------------------------------------------- commands

  void _reportError(Object e) {
    final msg = e is GitException ? e.message : e.toString();
    app.notify(msg, error: true);
  }

  /// Runs a git command with busy indication, error reporting and a refresh.
  Future<bool> run(
    String label,
    Future<void> Function() action, {
    String? success,
  }) async {
    busy = label;
    _notify();
    var ok = true;
    try {
      await action();
      if (success != null) app.notify(success);
    } catch (e) {
      ok = false;
      _reportError(e);
    } finally {
      busy = null;
      try {
        await refresh();
      } catch (_) {}
      _notify();
    }
    return ok;
  }

  Future<void> fetch({bool auto = false}) async {
    if (fetching) return;
    fetching = true;
    _notify();
    try {
      await repo.fetch();
      fetchError = null;
    } catch (e) {
      fetchError = e is GitException ? e.message : e.toString();
      if (!auto) _reportError(e);
    } finally {
      lastFetch = DateTime.now();
      fetching = false;
      if (!_disposed) {
        try {
          await refresh();
        } catch (_) {}
        _notify();
      }
    }
  }

  Future<void> pull(PullMode mode) => run('Pull', () => repo.pull(mode));

  Future<void> push({bool force = false}) async {
    final branch = currentBranch;
    if (branch == null) {
      app.notify('Cannot push: HEAD is detached', error: true);
      return;
    }
    final upstream = status.branch.upstream;
    String? remote;
    String? remoteBranch;
    if (upstream != null) {
      final i = upstream.indexOf('/');
      remote = upstream.substring(0, i);
      remoteBranch = upstream.substring(i + 1);
    } else {
      remote = remotes.any((r) => r.name == 'origin')
          ? 'origin'
          : (remotes.isEmpty ? null : remotes.first.name);
      if (remote == null) {
        app.notify('No remote configured', error: true);
        return;
      }
    }
    await run(
      force ? 'Force push' : 'Push',
      () => repo.push(
        branch: branch,
        remote: remote,
        remoteBranch: remoteBranch,
        setUpstream: upstream == null,
        forceWithLease: force,
      ),
      success: 'Pushed $branch to $remote',
    );
  }

  // Staging.

  Future<void> stageEntries(List<StatusEntry> entries) =>
      run('Stage', () => repo.stage(entries.map((e) => e.path).toList()));

  Future<void> unstageEntries(List<StatusEntry> entries) => run(
    'Unstage',
    () => repo.unstage([
      for (final e in entries) ...[e.path, ?e.oldPath],
    ]),
  );

  Future<void> discardEntries(List<StatusEntry> entries) =>
      run('Discard', () => repo.discard(entries));

  /// Applies the selected hunks/lines of the open working diff:
  /// stage (unstaged diff), unstage (staged diff) or discard (unstaged diff).
  Future<void> applySelection(
    Map<int, Set<int>?> selection, {
    bool discard = false,
  }) async {
    final t = diffTarget;
    final d = diff;
    if (t is! WorkingFileTarget || d == null) return;
    await run(discard ? 'Discard' : (t.staged ? 'Unstage' : 'Stage'), () async {
      var fileDiff = d;
      if (!t.staged && t.entry.isUntracked) {
        if (discard) {
          throw GitException(
            const [],
            1,
            'Use "Discard file" to delete an untracked file.',
          );
        }
        // Stage part of a new file: mark intent-to-add, then diff again.
        await repo.intentToAdd(t.entry.path);
        final tracked = StatusEntry(
          path: t.entry.path,
          index: ChangeKind.added,
          worktree: ChangeKind.modified,
        );
        fileDiff = await repo.workingDiff(tracked, staged: false) ?? d;
      }
      if (t.staged) {
        final patch = PatchBuilder.build(
          fileDiff,
          selection: selection,
          reverse: true,
        );
        if (patch == null) return;
        await repo.applyPatch(patch, cached: true, reverse: true);
      } else if (discard) {
        final patch = PatchBuilder.build(
          fileDiff,
          selection: selection,
          reverse: true,
        );
        if (patch == null) return;
        await repo.applyPatch(patch, cached: false, reverse: true);
      } else {
        final patch = PatchBuilder.build(fileDiff, selection: selection);
        if (patch == null) return;
        await repo.applyPatch(patch, cached: true);
      }
    });
  }

  Future<bool> commit() async {
    final msg = commitMessage.text.trim();
    if (msg.isEmpty) {
      app.notify('Enter a commit message', error: true);
      return false;
    }
    if (!amend && status.staged.isEmpty) {
      app.notify('Nothing staged to commit', error: true);
      return false;
    }
    final ok = await run(
      amend ? 'Amend' : 'Commit',
      () => repo.commit(msg, amend: amend),
    );
    if (ok) {
      commitMessage.clear();
      amend = false;
      _notify();
    }
    return ok;
  }

  Future<void> setAmend(bool value) async {
    amend = value;
    if (value && commitMessage.text.trim().isEmpty) {
      try {
        commitMessage.text = await repo.lastCommitMessage();
      } catch (_) {}
    }
    _notify();
  }
}

int _diffSignature(FileDiff? d) {
  if (d == null) return 0;
  return Object.hashAll([
    d.path,
    d.isBinary,
    for (final h in d.hunks) ...[
      h.header,
      for (final l in h.lines) Object.hash(l.type, l.text),
    ],
  ]);
}

GraphData _buildGraph(Uint8List bytes, String? wipParent, int maxCount) {
  final commits = parseLog(bytes);
  return _layoutGraph(commits, wipParent, commits.length >= maxCount);
}

GraphData _layoutGraph(
  List<Commit> commits,
  String? wipParent,
  bool truncated,
) {
  final hasWip = wipParent != null;
  final off = hasWip ? 1 : 0;
  final layout = GraphLayout.computeFromParents(
    commits.length + off,
    (i) => hasWip && i == 0 ? wipSha : commits[i - off].sha,
    (i) => hasWip && i == 0 ? [wipParent] : commits[i - off].parents,
  );
  return GraphData(commits, layout, hasWip: hasWip, truncated: truncated);
}
