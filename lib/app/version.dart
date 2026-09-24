/// Build identity, embedded at build time:
///
///   flutter build macos --dart-define=GUTTER_VERSION=0.1.0 \
///     --dart-define=GUTTER_COMMIT=$(git rev-parse --short HEAD)
///
/// Release builds from CI set both; local builds usually have neither.
class AppVersion {
  const AppVersion({this.version = '', this.commit = ''});

  static const current = AppVersion(
    version: String.fromEnvironment('GUTTER_VERSION'),
    commit: String.fromEnvironment('GUTTER_COMMIT'),
  );

  /// Semantic version without a leading `v` (e.g. `0.1.0`), or empty.
  final String version;

  /// Short commit sha, or empty.
  final String commit;

  bool get isRelease => version.isNotEmpty;

  /// `v0.1.0 (abc1234)`, `v0.1.0`, `dev abc1234`, or `unknown version`.
  String get label {
    if (version.isNotEmpty) {
      return commit.isEmpty ? 'v$version' : 'v$version ($commit)';
    }
    if (commit.isNotEmpty) return 'dev $commit';
    return 'unknown version';
  }
}

/// Compares dotted numeric versions (`v1.2.10` > `1.2.9`), ignoring a leading
/// `v` and any `-suffix`/`+build`. Returns <0, 0 or >0.
int compareVersions(String a, String b) {
  List<int> parse(String v) {
    var s = v.trim();
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
    s = s.split(RegExp(r'[-+]')).first;
    return [for (final p in s.split('.')) int.tryParse(p) ?? 0];
  }

  final x = parse(a), y = parse(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}
