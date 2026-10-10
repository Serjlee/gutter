import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../git/git_errors.dart';
import '../git/git_runner.dart';
import '../git/repository.dart';
import '../scan/repo_scanner.dart';
import '../ui/repo/repo_tab_controller.dart';
import 'avatars.dart';
import 'settings_store.dart';
import 'tab_groups.dart';
import 'theme.dart';
import 'update_checker.dart';
import 'updater.dart';
import 'zoom.dart';

/// Top-level app state: settings, open tabs, window focus, repo discovery.
class AppController extends ChangeNotifier {
  AppController(
    this.store,
    this.settings, {
    UpdateChecker? updates,
    Updater? updater,
    AvatarService? avatars,
  }) : updates = updates ?? UpdateChecker(),
       updater = updater ?? Updater(),
       avatars =
           avatars ??
           AvatarService(
             cacheFile: store == null
                 ? null
                 : File(p.join(store.file.parent.path, 'avatars.json')),
             enabled: settings.githubAvatars,
           ) {
    git = GitRunner(gitPath: settings.gitPath);
  }

  /// Latest-release lookup shown on the home tab.
  final UpdateChecker updates;

  /// Downloads and installs a new release.
  final Updater updater;

  /// GitHub profile pictures of commit authors.
  final AvatarService avatars;

  final SettingsStore? store;
  final Settings settings;
  late GitRunner git;

  /// Open repositories, in tab strip order. A group's tabs are always
  /// next to each other.
  final tabs = <RepoTabController>[];

  /// The groups of [tabs]; a group without tabs is dropped.
  final groups = <TabGroup>[];

  /// Counts changes of the tabs' order and groups (and groups' names,
  /// colors, collapsed state). Only the tab strip shows those: it listens
  /// to this, and the rest of the app isn't rebuilt for them (which, with
  /// a big repository open, takes longer than a frame). Opening, closing
  /// and showing tabs notify the controller itself, as before.
  final tabLayout = ValueNotifier<int>(0);

  /// `git --version`, once git ran ([checkGit]).
  String? gitVersion;

  /// Why git doesn't run (missing, or macOS's stub without the command line
  /// tools), once checked; null while it's fine or unknown.
  String? gitProblem;

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

  /// Shows or hides the repository views' sidebar (for every tab). Doesn't
  /// notify: the view that asks redraws itself, as rebuilding the whole app
  /// for it would cost more than a frame with a big repository open.
  void toggleSidebar() {
    settings.sidebarOpen = !settings.sidebarOpen;
    save();
  }

  void notify(String text, {bool error = false, bool warning = false}) =>
      _messages.add(AppMessage(text, error: error, warning: warning));

  /// Reports a failure readably ("Pull failed: …"). The toast offers the
  /// full output: [onDetails] shows it (e.g. in a tab's output panel),
  /// else a dialog does.
  void notifyError(Object e, {String? action, VoidCallback? onDetails}) {
    final summary = summarizeGitError(e);
    _messages.add(
      AppMessage(
        action == null ? summary : '$action failed: $summary',
        error: true,
        details: gitErrorDetails(e),
        onDetails: onDetails,
      ),
    );
  }

  /// Reopens the tabs (and their groups) from the last session. Only the
  /// active one loads now; the others when first shown.
  Future<void> restoreSession() async {
    final paths = List<String>.from(settings.openTabs);
    final groupIds = settings.openTabGroups;
    final saved = {for (final g in settings.tabGroups) g.id: g};
    final activePath =
        settings.activeTab >= 0 && settings.activeTab < paths.length
        ? paths[settings.activeTab]
        : null;
    // Checking that they're still repositories: a few at a time.
    final roots = <String?>[];
    for (var i = 0; i < paths.length; i += 8) {
      roots.addAll(
        await Future.wait([
          for (final path in paths.skip(i).take(8))
            Repository.probe(path, runner: git).then((r) => r.root),
        ]),
      );
    }
    RepoTabController? active;
    for (var i = 0; i < paths.length; i++) {
      final root = roots[i];
      if (root == null || tabs.any((t) => t.repo.path == root)) continue;
      final tab = RepoTabController(Repository(root, runner: git), this);
      tabs.add(tab);
      final group = i < groupIds.length ? saved[groupIds[i]] : null;
      if (group != null) {
        if (!groups.contains(group)) groups.add(group);
        tab.group = group;
      }
      if (paths[i] == activePath) active = tab;
    }
    _normalize();
    activate(active == null ? -1 : tabs.indexOf(active));
  }

  /// Opens [path] (any directory inside a repo) in a tab, or activates the
  /// existing tab. Returns false if it isn't a repository. A tab opened
  /// without [activate] loads when first shown.
  Future<bool> openRepo(String path, {bool activate = true}) async {
    final (:root, :error) = await Repository.probe(path, runner: git);
    if (root == null) {
      notify(
        error == null || error == 'Not a git repository'
            ? 'Not a git repository: $path'
            : 'Couldn\'t open $path: $error',
        error: true,
      );
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

  /// Shows tab [index] (-1: home), loading it if it hasn't yet, and
  /// expanding its group if collapsed.
  void activate(int index) {
    if (index >= tabs.length) index = tabs.length - 1;
    activeIndex = index;
    final active = activeTab;
    if (active?.group case final g? when g.collapsed) g.collapsed = false;
    for (var i = 0; i < tabs.length; i++) {
      tabs[i].setActive(i == index);
    }
    if (active != null) unawaited(active.ensureLoaded());
    _persistTabs();
    notifyListeners();
  }

  void closeTab(int index) {
    if (index < 0 || index >= tabs.length) return;
    closeTabs([tabs[index]]);
  }

  /// Closes [closing]. If the active tab is among them, the nearest
  /// remaining shown tab takes over (to the left first), else home.
  void closeTabs(Iterable<RepoTabController> closing) {
    final set = closing.toSet();
    if (set.isEmpty) return;
    var next = activeTab;
    if (next != null && set.contains(next)) {
      next = _nearestShown(activeIndex, (t) => !set.contains(t));
    }
    tabs.removeWhere(set.contains);
    for (final t in set) {
      t.dispose();
    }
    _normalize();
    if (next == activeTab && next != null) {
      activeIndex = tabs.indexOf(next);
      _layoutChanged();
      notifyListeners();
    } else {
      activate(next == null ? -1 : tabs.indexOf(next));
    }
  }

  /// The tab nearest to [index] that [ok] accepts and isn't hidden in a
  /// collapsed group: to the left first.
  RepoTabController? _nearestShown(
    int index,
    bool Function(RepoTabController) ok,
  ) {
    bool fits(RepoTabController t) => ok(t) && !isHidden(t);
    for (var i = index - 1; i >= 0; i--) {
      if (fits(tabs[i])) return tabs[i];
    }
    for (var i = index + 1; i < tabs.length; i++) {
      if (fits(tabs[i])) return tabs[i];
    }
    return null;
  }

  /// Whether [tab] is folded away in a collapsed group.
  bool isHidden(RepoTabController tab) => tab.group?.collapsed ?? false;

  /// The tabs of [group], in order.
  List<RepoTabController> tabsIn(TabGroup group) =>
      tabs.where((t) => t.group == group).toList();

  /// Moves [tab] to [index] (counted before the move) and into [group]
  /// (none: out of groups). Dropped inside another group's tabs without
  /// joining it, it lands after them.
  void placeTab(RepoTabController tab, int index, {TabGroup? group}) {
    final from = tabs.indexOf(tab);
    if (from < 0) return;
    final active = activeTab;
    tabs.removeAt(from);
    if (from < index) index--;
    tabs.insert(index.clamp(0, tabs.length), tab);
    activeIndex = active == null ? -1 : tabs.indexOf(active);
    tab.group = group;
    _layoutChanged();
  }

  /// Moves [group]'s tabs together to [index] (counted before the move).
  void moveGroup(TabGroup group, int index) {
    final members = tabsIn(group);
    if (members.isEmpty) return;
    final before = tabs
        .take(index.clamp(0, tabs.length))
        .where(members.contains);
    final at = index - before.length;
    final active = activeTab;
    tabs.removeWhere(members.contains);
    tabs.insertAll(at.clamp(0, tabs.length), members);
    activeIndex = active == null ? -1 : tabs.indexOf(active);
    _layoutChanged();
  }

  /// Puts [members] in a new group, gathered where the first of them is.
  TabGroup createGroup(List<RepoTabController> members, {String name = ''}) {
    final used = {for (final g in groups) g.color};
    var color = 0;
    while (used.contains(color) && color < groupColorNames.length - 1) {
      color++;
    }
    if (used.contains(color)) color = groups.length % groupColorNames.length;
    final group = TabGroup(id: _newGroupId(), name: name, color: color);
    groups.add(group);
    final ordered = tabs.where(members.contains).toList();
    final first = ordered.first;
    final rest = <RepoTabController>[];
    for (final t in tabs) {
      if (t == first) {
        rest.addAll(ordered);
      } else if (!ordered.contains(t)) {
        rest.add(t);
      }
    }
    final active = activeTab;
    tabs
      ..clear()
      ..addAll(rest);
    activeIndex = active == null ? -1 : tabs.indexOf(active);
    for (final t in ordered) {
      t.group = group;
    }
    _layoutChanged();
    return group;
  }

  var _groupSerial = 0;
  String _newGroupId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '-${_groupSerial++}';

  /// Moves [tab] to the end of [group].
  void addToGroup(RepoTabController tab, TabGroup group) {
    final last = tabs.lastIndexWhere((t) => t.group == group && t != tab);
    placeTab(tab, last < 0 ? tabs.length : last + 1, group: group);
  }

  /// Takes [tab] out of its group, placing it right after the group.
  void removeFromGroup(RepoTabController tab) {
    final group = tab.group;
    if (group == null) return;
    final last = tabs.lastIndexWhere((t) => t.group == group);
    placeTab(tab, last + 1);
  }

  /// Leaves [group]'s tabs where they are, ungrouped.
  void ungroup(TabGroup group) {
    for (final t in tabsIn(group)) {
      t.group = null;
    }
    _layoutChanged();
  }

  void closeGroup(TabGroup group) => closeTabs(tabsIn(group));

  void renameGroup(TabGroup group, String name) {
    group.name = name.trim();
    _layoutChanged();
  }

  void setGroupColor(TabGroup group, int color) {
    group.color = color;
    _layoutChanged();
  }

  /// Collapses or expands [group]. Collapsing the active tab's group shows
  /// the nearest tab outside it (to the right first), else home.
  void setGroupCollapsed(TabGroup group, bool collapsed) {
    group.collapsed = collapsed;
    final active = activeTab;
    if (collapsed && active?.group == group) {
      final last = tabs.lastIndexWhere((t) => t.group == group);
      RepoTabController? next;
      for (var i = last + 1; i < tabs.length && next == null; i++) {
        if (!isHidden(tabs[i])) next = tabs[i];
      }
      next ??= _nearestShown(last, (t) => t.group != group);
      activate(next == null ? -1 : tabs.indexOf(next));
      return;
    }
    _layoutChanged();
  }

  /// Ctrl+Tab: the next shown tab (home included), skipping collapsed
  /// groups.
  void nextTab(int delta) {
    final order = [
      -1,
      for (var i = 0; i < tabs.length; i++)
        if (!isHidden(tabs[i])) i,
    ];
    var cur = order.indexOf(activeIndex);
    if (cur < 0) cur = 0;
    final n = order.length;
    activate(order[((cur + delta) % n + n) % n]);
  }

  /// Gathers each group's tabs where its first tab is, and drops groups
  /// without tabs.
  void _normalize() {
    final active = activeTab;
    final seen = <TabGroup>{};
    final out = <RepoTabController>[];
    for (final t in tabs) {
      final g = t.group;
      if (g == null) {
        out.add(t);
      } else if (seen.add(g)) {
        out.addAll(tabs.where((x) => x.group == g));
      }
    }
    tabs
      ..clear()
      ..addAll(out);
    activeIndex = active == null ? -1 : tabs.indexOf(active);
    groups.removeWhere((g) => !seen.contains(g));
    for (final g in seen) {
      if (!groups.contains(g)) groups.add(g);
    }
  }

  /// A change of order or groups: redraws the tab strip only.
  void _layoutChanged() {
    // The active tab stays shown, even moved into a collapsed group.
    if (activeTab?.group case final g? when g.collapsed) g.collapsed = false;
    _normalize();
    _persistTabs();
    tabLayout.value++;
  }

  void _persistTabs() {
    settings.openTabs = tabs.map((t) => t.repo.path).toList();
    settings.openTabGroups = tabs.map((t) => t.group?.id ?? '').toList();
    settings.tabGroups = List.of(groups);
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
      // Back from installing it, perhaps.
      if (gitProblem != null) unawaited(checkGit());
    }
  }

  /// Whether git runs: [gitVersion], or [gitProblem]. Unless its path is
  /// set, git is looked for again first (it may have been installed since).
  Future<void> checkGit() async {
    if (settings.gitPath == null) git.gitPath = GitRunner.resolveGitPath();
    try {
      final r = await git.run(
        ['--version'],
        cwd: Directory.systemTemp.path,
        allowFailure: true,
      );
      if (r.ok && r.stdout.startsWith('git version')) {
        gitVersion = r.stdout.trim();
        gitProblem = null;
      } else {
        gitVersion = null;
        gitProblem = explainGitFailure(r.stderr, gitPath: git.gitPath);
      }
    } on ProcessException {
      gitVersion = null;
      gitProblem = settings.gitPath == null
          ? 'Gutter can\'t find git.'
          : 'Gutter can\'t run ${git.gitPath}, the git set in the settings.';
    }
    notifyListeners();
  }

  // ------------------------------------------------------------- settings

  void setFetchInterval(int minutes) {
    settings.fetchIntervalMinutes = minutes;
    save();
    notifyListeners();
  }

  void setGithubAvatars(bool value) {
    settings.githubAvatars = value;
    avatars.setEnabled(value);
    save();
    notifyListeners();
  }

  void setSyntaxHighlight(bool value) {
    settings.syntaxHighlight = value;
    save();
    notifyListeners();
  }

  void setForceTagFetch(bool value) {
    settings.forceTagFetch = value;
    save();
    notifyListeners();
  }

  /// 'system', 'light' or 'dark'.
  void setThemeMode(String mode) {
    settings.themeMode = mode;
    save();
    notifyListeners();
  }

  /// The palette for [settings.themeMode], given the OS's [platform]
  /// brightness.
  AppPalette paletteFor(Brightness platform) => switch (settings.themeMode) {
    'light' => AppPalette.light,
    'dark' => AppPalette.dark,
    _ => platform == Brightness.light ? AppPalette.light : AppPalette.dark,
  };

  void setDiffWrap(bool value) {
    settings.diffWrap = value;
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

  final _updatesOffered = <String>{};

  /// Whether to offer the newer release now: once per release per run,
  /// and never a skipped one.
  bool takeUpdateOffer() {
    final latest = updates.latest;
    if (latest == null || !updates.updateAvailable) return false;
    if (latest.tag == settings.skippedUpdate) return false;
    return _updatesOffered.add(latest.tag);
  }

  void skipUpdate(String tag) {
    settings.skippedUpdate = tag;
    save();
  }

  /// Quits, for the updater to swap in the new version and restart.
  Never quitForUpdate() {
    store?.saveNow(settings);
    exit(0);
  }

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
    unawaited(checkGit());
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
    updater.dispose();
    avatars.dispose();
    tabLayout.dispose();
    _messages.close();
    super.dispose();
  }
}

class AppMessage {
  AppMessage(
    this.text, {
    this.error = false,
    this.warning = false,
    this.details,
    this.onDetails,
  });
  final String text;
  final bool error;

  /// Needs attention, but isn't a failure (e.g. stopped on conflicts).
  final bool warning;

  /// The full error output, shown by a "Details" button.
  final String? details;

  /// Shows the details some other way than a dialog.
  final VoidCallback? onDetails;
}
