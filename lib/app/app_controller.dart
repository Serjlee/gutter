import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../git/git_runner.dart';
import '../git/repository.dart';
import '../scan/repo_scanner.dart';
import '../ui/repo/repo_tab_controller.dart';
import 'settings_store.dart';
import 'update_checker.dart';
import 'zoom.dart';

/// Top-level app state: settings, open tabs, window focus, repo discovery.
class AppController extends ChangeNotifier {
  AppController(this.store, this.settings, {UpdateChecker? updates})
    : updates = updates ?? UpdateChecker() {
    git = GitRunner(gitPath: settings.gitPath);
  }

  /// Latest-release lookup shown on the home tab.
  final UpdateChecker updates;

  final SettingsStore? store;
  final Settings settings;
  late GitRunner git;

  final tabs = <RepoTabController>[];

  /// Index into [tabs], or -1 for the home tab.
  int activeIndex = -1;

  /// Whether the app window has focus. Auto-fetch pauses while unfocused.
  final focused = ValueNotifier<bool>(true);

  /// Active directory scans, by root.
  final scanning = <String, RepoScan>{};

  /// User-facing messages (errors, confirmations) for snackbars.
  final _messages = StreamController<AppMessage>.broadcast();
  Stream<AppMessage> get messages => _messages.stream;

  RepoTabController? get activeTab =>
      activeIndex >= 0 && activeIndex < tabs.length ? tabs[activeIndex] : null;

  void save() => store?.save(settings);

  void notify(String text, {bool error = false}) =>
      _messages.add(AppMessage(text, error: error));

  /// Reopens the tabs from the last session.
  Future<void> restoreSession() async {
    final paths = List<String>.from(settings.openTabs);
    final active = settings.activeTab;
    for (final path in paths) {
      await openRepo(path, activate: false, persist: false);
    }
    if (active >= 0 && active < tabs.length) {
      activate(active);
    } else {
      activate(-1);
    }
  }

  /// Opens [path] (any directory inside a repo) in a tab, or activates the
  /// existing tab. Returns false if it isn't a repository.
  Future<bool> openRepo(
    String path, {
    bool activate = true,
    bool persist = true,
  }) async {
    final (:root, :error) = await Repository.probe(path, runner: git);
    if (root == null) {
      if (persist) {
        notify(
          error == null || error == 'Not a git repository'
              ? 'Not a git repository: $path'
              : 'Couldn\'t open $path: $error',
          error: true,
        );
      }
      return false;
    }
    final existing = tabs.indexWhere((t) => t.repo.path == root);
    if (existing >= 0) {
      if (activate) this.activate(existing);
      return true;
    }
    final tab = RepoTabController(Repository(root, runner: git), this);
    tabs.add(tab);
    _rememberRecent(root);
    if (!settings.knownRepos.contains(root)) {
      settings.knownRepos.add(root);
    }
    if (activate) {
      this.activate(tabs.length - 1);
    } else {
      _persistTabs();
      notifyListeners();
    }
    unawaited(tab.load());
    return true;
  }

  void _rememberRecent(String root) {
    settings.recentRepos
      ..remove(root)
      ..insert(0, root);
    if (settings.recentRepos.length > 20) {
      settings.recentRepos.removeRange(20, settings.recentRepos.length);
    }
  }

  void activate(int index) {
    if (index >= tabs.length) index = tabs.length - 1;
    activeIndex = index;
    for (var i = 0; i < tabs.length; i++) {
      tabs[i].setActive(i == index);
    }
    _persistTabs();
    notifyListeners();
  }

  void closeTab(int index) {
    if (index < 0 || index >= tabs.length) return;
    final tab = tabs.removeAt(index);
    tab.dispose();
    if (activeIndex == index) {
      activate(tabs.isEmpty ? -1 : (index > 0 ? index - 1 : 0));
    } else {
      if (activeIndex > index) activeIndex--;
      _persistTabs();
      notifyListeners();
    }
  }

  void moveTab(int from, int to) {
    if (from == to) return;
    final active = activeTab;
    final tab = tabs.removeAt(from);
    tabs.insert(to.clamp(0, tabs.length), tab);
    activeIndex = active == null ? -1 : tabs.indexOf(active);
    _persistTabs();
    notifyListeners();
  }

  void nextTab(int delta) {
    final count = tabs.length + 1; // + home
    final cur = activeIndex + 1;
    activate(((cur + delta) % count + count) % count - 1);
  }

  void _persistTabs() {
    settings.openTabs = tabs.map((t) => t.repo.path).toList();
    settings.activeTab = activeIndex;
    save();
  }

  // ------------------------------------------------------------------ zoom

  double get zoom => settings.zoom;

  void setZoom(double z) {
    final v = clampZoom(z);
    if (v == settings.zoom) return;
    settings.zoom = v;
    save();
    notifyListeners();
  }

  void zoomIn() => setZoom(zoom + zoomStep);
  void zoomOut() => setZoom(zoom - zoomStep);
  void zoomReset() => setZoom(1.0);

  // ---------------------------------------------------------------- focus

  void setFocused(bool value) {
    if (focused.value == value) return;
    focused.value = value;
    if (value) {
      for (final t in tabs) {
        t.onAppFocused();
      }
    }
  }

  // ------------------------------------------------------------- settings

  void setFetchInterval(int minutes) {
    settings.fetchIntervalMinutes = minutes;
    save();
    notifyListeners();
  }

  void setSyntaxHighlight(bool value) {
    settings.syntaxHighlight = value;
    save();
    notifyListeners();
  }

  void setFileTree(bool value) {
    settings.fileTree = value;
    save();
    notifyListeners();
  }

  /// Starts periodic update checks.
  void startUpdateChecks() => updates.start();

  void setMaxCommits(int n) {
    settings.maxCommits = n;
    save();
    notifyListeners();
  }

  void setGitPath(String? path) {
    settings.gitPath = (path == null || path.trim().isEmpty) ? null : path;
    git.gitPath = settings.gitPath ?? GitRunner.resolveGitPath();
    save();
    notifyListeners();
  }

  // --------------------------------------------------------------- scanning

  Future<void> addScanRoot(String root) async {
    root = p.normalize(root);
    if (!settings.scanRoots.contains(root)) {
      settings.scanRoots.add(root);
      save();
    }
    await scan(root);
  }

  void removeScanRoot(String root) {
    scanning.remove(root)?.cancel();
    settings.scanRoots.remove(root);
    settings.knownRepos.removeWhere((r) => p.isWithin(root, r) || r == root);
    save();
    notifyListeners();
  }

  Future<void> scan(String root) async {
    scanning.remove(root)?.cancel();
    final scan = await RepoScan.start(root);
    scanning[root] = scan;
    notifyListeners();
    final found = <String>{};
    var pending = 0;
    await for (final repo in scan.results) {
      found.add(repo);
      if (!settings.knownRepos.contains(repo)) {
        settings.knownRepos.add(repo);
        if (++pending >= 25) {
          pending = 0;
          notifyListeners();
        }
      }
    }
    // Forget repos under this root that no longer exist.
    settings.knownRepos.removeWhere(
      (r) => (p.isWithin(root, r) || r == root) && !found.contains(r),
    );
    if (scanning[root] == scan) scanning.remove(root);
    save();
    notifyListeners();
  }

  Future<void> rescanAll() async {
    await Future.wait(settings.scanRoots.map(scan));
  }

  void forgetRepo(String path) {
    settings.knownRepos.remove(path);
    settings.recentRepos.remove(path);
    save();
    notifyListeners();
  }

  @override
  void dispose() {
    for (final t in tabs) {
      t.dispose();
    }
    for (final s in scanning.values) {
      s.cancel();
    }
    store?.saveNow(settings);
    updates.dispose();
    _messages.close();
    super.dispose();
  }
}

class AppMessage {
  AppMessage(this.text, {this.error = false});
  final String text;
  final bool error;
}
