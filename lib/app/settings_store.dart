import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'tab_groups.dart';

/// Persistent app settings and session state, stored as JSON.
class Settings {
  List<String> openTabs = [];
  int activeTab = -1; // -1: home tab

  /// The group of each of [openTabs] (a [TabGroup.id], '' for none).
  List<String> openTabGroups = [];
  List<TabGroup> tabGroups = [];
  List<String> scanRoots = [];
  List<String> knownRepos = [];
  List<String> recentRepos = [];
  double zoom = 1.0;
  int fetchIntervalMinutes = 5;

  /// Commits loaded at first and per "load more" (0: all).
  int maxCommits = 20000;
  String? gitPath;
  double sidebarWidth = 240;

  /// Whether the repository view's left sidebar is shown.
  bool sidebarOpen = true;
  double detailsWidth = 380;
  Map<String, double> columnWidths = {};

  /// The interactive rebase editor's size, as last resized.
  double rebaseWidth = 960;
  double rebaseHeight = 620;

  /// The share of its width the commit list takes.
  double rebaseSplit = 0.6;

  /// The share of the height the message takes above the changed files.
  double rebaseMessageSplit = 1 / 3;
  bool diffSplit = false;

  /// Wrap long lines in the unified diff (the split one always wraps).
  bool diffWrap = false;

  /// Show working-tree files as a folder tree instead of a flat list.
  bool fileTree = false;

  /// Syntax highlighting in diffs and file previews (costs CPU on big files).
  bool syntaxHighlight = true;

  /// Show GitHub profile pictures for commit authors of GitHub repositories.
  bool githubAvatars = true;

  /// Fetch replaces local tags that moved on the remote, without asking.
  bool forceTagFetch = false;

  /// A release the user chose to skip (its tag): not offered again.
  String? skippedUpdate;

  /// 'system' (follow the OS), 'light' or 'dark'.
  String themeMode = 'system';

  Map<String, Object?> toJson() => {
    'openTabs': openTabs,
    'activeTab': activeTab,
    'openTabGroups': openTabGroups,
    'tabGroups': [for (final g in tabGroups) g.toJson()],
    'scanRoots': scanRoots,
    'knownRepos': knownRepos,
    'recentRepos': recentRepos,
    'zoom': zoom,
    'fetchIntervalMinutes': fetchIntervalMinutes,
    'maxCommits': maxCommits,
    'gitPath': gitPath,
    'sidebarWidth': sidebarWidth,
    'sidebarOpen': sidebarOpen,
    'detailsWidth': detailsWidth,
    'columnWidths': columnWidths,
    'rebaseWidth': rebaseWidth,
    'rebaseHeight': rebaseHeight,
    'rebaseSplit': rebaseSplit,
    'rebaseMessageSplit': rebaseMessageSplit,
    'diffSplit': diffSplit,
    'diffWrap': diffWrap,
    'fileTree': fileTree,
    // A new key: the old one ("syntaxHighlight") saved the former default,
    // off, for everyone.
    'syntaxHighlighting': syntaxHighlight,
    'githubAvatars': githubAvatars,
    'forceTagFetch': forceTagFetch,
    'skippedUpdate': skippedUpdate,
    'themeMode': themeMode,
  };

  static Settings fromJson(Map<String, Object?> j) {
    List<String> strings(Object? v) =>
        v is List ? v.whereType<String>().toList() : <String>[];
    double num_(Object? v, double d) => v is num ? v.toDouble() : d;
    final s = Settings()
      ..openTabs = strings(j['openTabs'])
      ..activeTab = (j['activeTab'] as num?)?.toInt() ?? -1
      ..openTabGroups = strings(j['openTabGroups'])
      ..tabGroups = [
        if (j['tabGroups'] case final List l)
          for (final g in l) ?TabGroup.fromJson(g),
      ]
      ..scanRoots = strings(j['scanRoots'])
      ..knownRepos = strings(j['knownRepos'])
      ..recentRepos = strings(j['recentRepos'])
      ..zoom = num_(j['zoom'], 1.0)
      ..fetchIntervalMinutes = (j['fetchIntervalMinutes'] as num?)?.toInt() ?? 5
      ..maxCommits = (j['maxCommits'] as num?)?.toInt() ?? 20000
      ..gitPath = j['gitPath'] as String?
      ..sidebarWidth = num_(j['sidebarWidth'], 240)
      ..sidebarOpen = j['sidebarOpen'] != false
      ..detailsWidth = num_(j['detailsWidth'], 380)
      ..rebaseWidth = num_(j['rebaseWidth'], 960)
      ..rebaseHeight = num_(j['rebaseHeight'], 620)
      ..rebaseSplit = num_(j['rebaseSplit'], 0.6)
      ..rebaseMessageSplit = num_(j['rebaseMessageSplit'], 1 / 3)
      ..diffSplit = j['diffSplit'] == true
      ..diffWrap = j['diffWrap'] == true
      ..fileTree = j['fileTree'] == true
      ..syntaxHighlight = j['syntaxHighlighting'] != false
      ..githubAvatars = j['githubAvatars'] != false
      ..forceTagFetch = j['forceTagFetch'] == true
      ..skippedUpdate = j['skippedUpdate'] as String?
      ..themeMode = switch (j['themeMode']) {
        'light' => 'light',
        'dark' => 'dark',
        _ => 'system',
      };
    final cw = j['columnWidths'];
    if (cw is Map) {
      for (final e in cw.entries) {
        if (e.key is String && e.value is num) {
          s.columnWidths[e.key as String] = (e.value as num).toDouble();
        }
      }
    }
    return s;
  }
}

class SettingsStore {
  SettingsStore(this.file);

  final File file;
  Timer? _debounce;

  static Future<SettingsStore> open(String dir) async {
    await Directory(dir).create(recursive: true);
    return SettingsStore(File(p.join(dir, 'settings.json')));
  }

  Settings load() {
    try {
      if (file.existsSync()) {
        final j = jsonDecode(file.readAsStringSync());
        if (j is Map<String, Object?>) return Settings.fromJson(j);
      }
    } catch (_) {
      // Corrupt settings: start fresh.
    }
    return Settings();
  }

  /// Saves soon (debounced).
  void save(Settings s) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => saveNow(s));
  }

  void saveNow(Settings s) {
    _debounce?.cancel();
    try {
      final tmp = File('${file.path}.tmp');
      tmp.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(s.toJson()),
      );
      tmp.renameSync(file.path);
    } catch (_) {
      // Best effort.
    }
  }
}
