import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'version.dart';

const releasesRepo = 'serjlee/gutter';

class ReleaseInfo {
  const ReleaseInfo({
    required this.tag,
    required this.url,
    required this.publishedAt,
  });

  final String tag;
  final String url;
  final DateTime? publishedAt;

  static ReleaseInfo? fromGitHubJson(Object? json) {
    if (json is! Map) return null;
    final tag = json['tag_name'];
    final url = json['html_url'];
    if (tag is! String || url is! String) return null;
    final published = json['published_at'];
    return ReleaseInfo(
      tag: tag,
      url: url,
      publishedAt: published is String ? DateTime.tryParse(published) : null,
    );
  }
}

/// Fetches the latest published release, or null if there is none.
typedef ReleaseFetcher = Future<ReleaseInfo?> Function();

/// Periodically looks up the latest GitHub release of Gutter. This is the
/// app's only network request of its own (git fetch/push aside); it can be
/// turned off in settings.
class UpdateChecker extends ChangeNotifier {
  UpdateChecker({
    this.current = AppVersion.current,
    ReleaseFetcher? fetcher,
    this.interval = const Duration(hours: 6),
  }) : _fetch = fetcher ?? fetchLatestGitHubRelease;

  final AppVersion current;
  final ReleaseFetcher _fetch;
  final Duration interval;

  ReleaseInfo? latest;
  DateTime? lastChecked;
  String? error;
  bool checking = false;
  Timer? _timer;
  bool _disposed = false;

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
      latest = await _fetch();
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

Future<ReleaseInfo?> fetchLatestGitHubRelease() async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..userAgent = 'gutter-update-check';
  try {
    final req = await client.getUrl(
      Uri.https('api.github.com', '/repos/$releasesRepo/releases/latest'),
    );
    req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    final res = await req.close().timeout(const Duration(seconds: 15));
    final body = await res.transform(utf8.decoder).join();
    // 404: no release published yet (or the repository is private).
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw HttpException('GitHub returned ${res.statusCode}');
    }
    return ReleaseInfo.fromGitHubJson(jsonDecode(body));
  } finally {
    client.close(force: true);
  }
}
