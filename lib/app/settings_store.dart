import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Persistent app settings and session state, stored as JSON.
class Settings {
  List<String> openTabs = [];
  int activeTab = -1; // -1: home tab
  List<String> scanRoots = [];
  List<String> knownRepos = [];
  List<String> recentRepos = [];
  double zoom = 1.0;
  int fetchIntervalMinutes = 5;

  /// Commits loaded at first and per "load more" (0: all).
  int maxCommits = 20000;
  String? gitPath;
  double sidebarWidth = 240;
  double detailsWidth = 380;
  Map<String, double> columnWidths = {};
  bool diffSplit = false;

  /// Show working-tree files as a folder tree instead of a flat list.
  bool fileTree = false;

  /// Syntax highlighting in diffs and file previews (costs CPU on big files).
  bool syntaxHighlight = false;

  /// Show GitHub profile pictures for commit authors of GitHub repositories.
  bool githubAvatars = true;

  Map<String, Object?> toJson() => {
    'openTabs': openTabs,
    'activeTab': activeTab,
    'scanRoots': scanRoots,
    'knownRepos': knownRepos,
    'recentRepos': recentRepos,
    'zoom': zoom,
    'fetchIntervalMinutes': fetchIntervalMinutes,
    'maxCommits': maxCommits,
    'gitPath': gitPath,
    'sidebarWidth': sidebarWidth,
    'detailsWidth': detailsWidth,
    'columnWidths': columnWidths,
    'diffSplit': diffSplit,
    'fileTree': fileTree,
    'syntaxHighlight': syntaxHighlight,
    'githubAvatars': githubAvatars,
  };

  static Settings fromJson(Map<String, Object?> j) {
    List<String> strings(Object? v) =>
        v is List ? v.whereType<String>().toList() : <String>[];
    double num_(Object? v, double d) => v is num ? v.toDouble() : d;
    final s = Settings()
      ..openTabs = strings(j['openTabs'])
      ..activeTab = (j['activeTab'] as num?)?.toInt() ?? -1
      ..scanRoots = strings(j['scanRoots'])
      ..knownRepos = strings(j['knownRepos'])
      ..recentRepos = strings(j['recentRepos'])
      ..zoom = num_(j['zoom'], 1.0)
      ..fetchIntervalMinutes = (j['fetchIntervalMinutes'] as num?)?.toInt() ?? 5
      ..maxCommits = (j['maxCommits'] as num?)?.toInt() ?? 20000
      ..gitPath = j['gitPath'] as String?
      ..sidebarWidth = num_(j['sidebarWidth'], 240)
      ..detailsWidth = num_(j['detailsWidth'], 380)
      ..diffSplit = j['diffSplit'] == true
      ..fileTree = j['fileTree'] == true
      ..syntaxHighlight = j['syntaxHighlight'] == true
      ..githubAvatars = j['githubAvatars'] != false;
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
