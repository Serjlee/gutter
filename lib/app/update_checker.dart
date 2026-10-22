import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'version.dart';

const releasesRepo = 'serjlee/gutter';

/// A file attached to a release.
class ReleaseAsset {
  const ReleaseAsset({required this.name, required this.url, this.size = 0});
  final String name;

  /// Direct download (github.com/…/releases/download/…), not the API.
  final String url;
  final int size;
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.tag,
    required this.url,
    required this.publishedAt,
    this.notes = '',
    this.assets = const [],
    this.prerelease = false,
  });

  final String tag;
  final String url;
  final DateTime? publishedAt;

  /// The release notes (Markdown).
  final String notes;
  final List<ReleaseAsset> assets;

  /// Marked as a pre-release (or a draft) on GitHub: never offered.
  final bool prerelease;

  /// The version without a leading `v`.
  String get version =>
      tag.startsWith('v') || tag.startsWith('V') ? tag.substring(1) : tag;

  ReleaseAsset? asset(bool Function(String name) test) =>
      assets.where((a) => test(a.name)).firstOrNull;

  static ReleaseInfo? fromGitHubJson(Object? json) {
    if (json is! Map) return null;
    final tag = json['tag_name'];
    final url = json['html_url'];
    if (tag is! String || url is! String) return null;
    final published = json['published_at'];
    final body = json['body'];
    final assets = json['assets'];
    return ReleaseInfo(
      tag: tag,
      url: url,
      publishedAt: published is String ? DateTime.tryParse(published) : null,
      notes: body is String ? body : '',
      prerelease: json['prerelease'] == true || json['draft'] == true,
      assets: [
        if (assets is List)
          for (final a in assets.whereType<Map>())
            if (a['name'] is String && a['browser_download_url'] is String)
              ReleaseAsset(
                name: a['name'] as String,
                url: a['browser_download_url'] as String,
                size: a['size'] is int ? a['size'] as int : 0,
              ),
      ],
    );
  }
}

/// The releases in a GitHub releases payload: a list, or a single release
/// (as `releases/latest` returns it). Pre-releases are left out.
List<ReleaseInfo> releasesFromGitHubJson(Object? json) => [
  for (final r in json is List ? json : [json])
    if (ReleaseInfo.fromGitHubJson(r) case final release?)
      if (!release.prerelease) release,
];

/// Fetches the published releases, in any order.
typedef ReleaseFetcher = Future<List<ReleaseInfo>> Function();

/// Periodically looks up the latest GitHub release of Gutter.
class UpdateChecker extends ChangeNotifier {
  UpdateChecker({
    this.current = AppVersion.current,
    ReleaseFetcher? fetcher,
    this.interval = const Duration(hours: 6),
  }) : _fetch = fetcher ?? fetchGitHubReleases;

  final AppVersion current;
  final ReleaseFetcher _fetch;
  final Duration interval;

  /// The published releases, newest first.
  List<ReleaseInfo> releases = const [];
  DateTime? lastChecked;
  String? error;
  bool checking = false;
  Timer? _timer;
  bool _disposed = false;

  ReleaseInfo? get latest => releases.firstOrNull;

  /// The releases newer than this build, newest first: what an update
  /// brings. Just the latest for builds without a version.
  List<ReleaseInfo> get newReleases => current.isRelease
      ? [
          for (final r in releases)
            if (compareVersions(r.tag, current.version) > 0) r,
        ]
      : [?latest];

  /// A newer release than this build exists. Builds without a version
  /// (local/dev builds) can't be compared, so this stays false for them.
  bool get updateAvailable {
    final l = latest;
    return l != null &&
        current.isRelease &&
        compareVersions(l.tag, current.version) > 0;
  }

  /// Checks now and then every [interval] (first check after [delay]).
  void start({Duration delay = const Duration(seconds: 5)}) {
    stop();
    _timer = Timer(delay, () {
      unawaited(check());
      _timer = Timer.periodic(interval, (_) => unawaited(check()));
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> check() async {
    if (checking || _disposed) return;
    checking = true;
    notifyListeners();
    try {
      releases = (await _fetch()).toList()
        ..sort((a, b) => compareVersions(b.tag, a.tag));
      error = null;
    } catch (e) {
      error = e is HttpException ? e.message : e.toString();
    } finally {
      checking = false;
      lastChecked = DateTime.now();
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}

/// The latest releases of Gutter on GitHub (enough to cover any version
/// still in use).
Future<List<ReleaseInfo>> fetchGitHubReleases() async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..findProxy = HttpClient.findProxyFromEnvironment
    ..userAgent = 'gutter-update-check';
  // GUTTER_UPDATE_URL: a stand-in for the GitHub API, to try updates.
  final override = Platform.environment['GUTTER_UPDATE_URL'];
  try {
    final req = await client.getUrl(
      override != null
          ? Uri.parse(override)
          : Uri.https('api.github.com', '/repos/$releasesRepo/releases', {
              'per_page': '50',
            }),
    );
    req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    final res = await req.close().timeout(const Duration(seconds: 15));
    final body = await res.transform(utf8.decoder).join();
    // 404: the repository is private (or gone).
    if (res.statusCode == 404) return const [];
    if (res.statusCode != 200) {
      throw HttpException('GitHub returned ${res.statusCode}');
    }
    return releasesFromGitHubJson(jsonDecode(body));
  } finally {
    client.close(force: true);
  }
}
