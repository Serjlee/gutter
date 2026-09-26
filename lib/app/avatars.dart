import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// `owner/name` of a GitHub repository from a remote URL (https, ssh or
/// scp-like), or null for other hosts.
String? githubRepoOf(String url) {
  final m = RegExp(
    r'^(?:https?://(?:[^@/]+@)?|ssh://(?:[^@/]+@)?|git://|[^@/:]+@)'
    r'github\.com[:/]([^/\s]+)/([^/\s]+?)(?:\.git)?/?$',
    caseSensitive: false,
  ).firstMatch(url.trim());
  return m == null ? null : '${m.group(1)}/${m.group(2)}';
}

/// The avatar of a GitHub "noreply" address (`123+login@users.noreply…` or
/// `login@users.noreply…`), which names its account.
String? noreplyAvatarUrl(String email) {
  final m = RegExp(
    r'^(?:(\d+)\+)?([^@]+)@users\.noreply\.github\.com$',
    caseSensitive: false,
  ).firstMatch(email.trim());
  if (m == null) return null;
  final id = m.group(1);
  return id != null
      ? 'https://avatars.githubusercontent.com/u/$id?v=4'
      : 'https://github.com/${m.group(2)}.png';
}

/// Where GitHub's avatar server looks a picture up by commit email: the
/// account's picture for an email verified on an account, else a fixed
/// placeholder.
String emailAvatarUrl(String email) => Uri.https(
  'avatars.githubusercontent.com',
  '/u/e',
  {'email': email},
).toString();

/// Fetches an image's bytes, or null.
typedef BytesGet = Future<Uint8List?> Function(Uri url);

/// GitHub profile pictures for commit authors, fetched from GitHub's avatar
/// server by commit email (no API calls), as rows come into view. Authors
/// without a GitHub account keep their generated initials; so does
/// everyone while offline.
class AvatarService extends ChangeNotifier {
  AvatarService({this.cacheFile, BytesGet? getBytes, this.enabled = true})
    : _getBytes = getBytes ?? _defaultGetBytes {
    _loadCache();
  }

  final File? cacheFile;
  final BytesGet _getBytes;
  bool enabled;

  /// Pixel size requested (the largest avatar shown is 32 logical px, at
  /// 2x). The server's placeholder for unknown emails ignores it, which is
  /// how it's told apart.
  static const size = 64;

  /// Emails without an account are asked about again after this long.
  static const retryAfter = Duration(days: 7);

  static const maxConcurrent = 4;

  /// Emails (lowercase) known to have no account, and when that was found.
  final _none = <String, DateTime>{};
  final _images = <String, ui.Image>{};
  final _queued = <String>{};
  final _queue = Queue<String>();
  final _failed = <String>{};
  int _running = 0;
  Timer? _saveTimer;

  void setEnabled(bool value) {
    enabled = value;
    notifyListeners();
  }

  /// The picture for [email], once loaded; starts loading it. Null while
  /// loading and for authors without one.
  ui.Image? imageFor(String email) {
    if (!enabled) return null;
    final key = email.trim().toLowerCase();
    if (key.isEmpty) return null;
    final image = _images[key];
    if (image != null) return image;
    final none = _none[key];
    if (none != null && DateTime.now().difference(none) < retryAfter) {
      return null;
    }
    if (!_failed.contains(key) && _queued.add(key)) {
      _queue.add(key);
      _pump();
    }
    return null;
  }

  /// Whether [email] is known to have no GitHub picture.
  @visibleForTesting
  bool hasNone(String email) => _none.containsKey(email.toLowerCase());

  void _pump() {
    while (_running < maxConcurrent && _queue.isNotEmpty) {
      final key = _queue.removeFirst();
      _running++;
      unawaited(
        _fetch(key).whenComplete(() {
          _running--;
          _queued.remove(key);
          _pump();
        }),
      );
    }
  }

  Future<void> _fetch(String email) async {
    final base = Uri.parse(noreplyAvatarUrl(email) ?? emailAvatarUrl(email));
    // avatars.githubusercontent.com takes `s`, github.com/<login>.png
    // `size`.
    final url = base.replace(
      queryParameters: {
        ...base.queryParameters,
        base.host == 'github.com' ? 'size' : 's': '$size',
      },
    );
    try {
      final bytes = await _getBytes(url);
      if (bytes == null) {
        _failed.add(email);
        return;
      }
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      if (image.width != size || image.height != size) {
        // The placeholder: no account uses this email.
        image.dispose();
        _none[email] = DateTime.now();
        _scheduleSave();
        return;
      }
      _images[email] = image;
      if (_none.remove(email) != null) _scheduleSave();
      notifyListeners();
    } catch (_) {
      _failed.add(email); // offline or unreadable: initials this session
    }
  }

  void _loadCache() {
    final f = cacheFile;
    if (f == null || !f.existsSync()) return;
    try {
      final j = jsonDecode(f.readAsStringSync());
      final none = j is Map ? j['none'] : null;
      if (none is! Map) return;
      for (final e in none.entries) {
        if (e.key is String && e.value is int) {
          _none[e.key as String] = DateTime.fromMillisecondsSinceEpoch(
            e.value as int,
          );
        }
      }
    } catch (_) {}
  }

  void _scheduleSave() {
    if (cacheFile == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), save);
  }

  void save() {
    final f = cacheFile;
    if (f == null) return;
    try {
      f.writeAsStringSync(
        jsonEncode({
          'none': {
            for (final e in _none.entries)
              e.key: e.value.millisecondsSinceEpoch,
          },
        }),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      save();
    }
    super.dispose();
  }
}

Future<Uint8List?> _defaultGetBytes(Uri url) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..userAgent = 'gutter-avatars';
  try {
    final req = await client.getUrl(url);
    final res = await req.close().timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return null;
    final b = BytesBuilder(copy: false);
    await res.forEach(b.add);
    return b.takeBytes();
  } finally {
    client.close(force: true);
  }
}
