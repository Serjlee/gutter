import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'update_checker.dart';

enum InstallKind {
  /// Gutter.app on macOS.
  macApp,

  /// The folder of the Linux tarball.
  linuxBundle,

  /// A Flatpak: it updates from Gutter's Flatpak repository, running
  /// `flatpak update` on the host (as a software center would).
  flatpak,

  /// Installed on Windows with the installer (it left its uninstaller next
  /// to gutter.exe): the new installer runs silently once Gutter quits.
  windowsInstaller,

  /// The folder of the Windows zip: swapped for the new one, as the Linux
  /// tarball's.
  windowsFolder,

  /// Can't update itself; see [Installation.reason].
  unsupported,
}

/// Where and how this copy of Gutter is installed, and so how it updates.
class Installation {
  const Installation(this.kind, {this.path = '', this.reason});

  final InstallKind kind;

  /// The .app bundle (macOS) or the folder holding the `gutter` executable
  /// (Linux, Windows).
  final String path;

  /// Why it can't update itself, when it can't.
  final String? reason;

  bool get canSelfUpdate => kind != InstallKind.unsupported;

  bool get isWindows =>
      kind == InstallKind.windowsInstaller || kind == InstallKind.windowsFolder;

  static final _macZip = RegExp(r'^Gutter-macos-.*\.zip$');
  static final _linuxTarball = RegExp(r'^gutter-linux-x64-.*\.tar\.gz$');
  static final _flatpak = RegExp(r'^gutter-linux-x64-.*\.flatpak$');
  static final _windowsSetup = RegExp(r'^Gutter-windows-x64-.*-setup\.exe$');
  static final _windowsZip = RegExp(r'^Gutter-windows-x64-.*\.zip$');

  /// The file of [release] for this installation.
  ReleaseAsset? assetIn(ReleaseInfo release) => switch (kind) {
    InstallKind.macApp => release.asset(_macZip.hasMatch),
    InstallKind.linuxBundle => release.asset(_linuxTarball.hasMatch),
    InstallKind.flatpak => release.asset(_flatpak.hasMatch),
    InstallKind.windowsInstaller => release.asset(_windowsSetup.hasMatch),
    InstallKind.windowsFolder => release.asset(_windowsZip.hasMatch),
    InstallKind.unsupported => null,
  };

  /// Looks at the running executable (overridable for tests).
  static Installation detect({
    String? executable,
    bool? macOS,
    bool? linux,
    bool? flatpak,
    bool? windows,
  }) {
    final exe = executable ?? Platform.resolvedExecutable;
    if (flatpak ?? (Platform.isLinux && File('/.flatpak-info').existsSync())) {
      return const Installation(InstallKind.flatpak);
    }
    if (macOS ?? Platform.isMacOS) {
      // …/Gutter.app/Contents/MacOS/gutter
      final app = p.dirname(p.dirname(p.dirname(exe)));
      if (!app.endsWith('.app')) {
        return const Installation(
          InstallKind.unsupported,
          reason: 'Gutter isn\'t running from an app bundle.',
        );
      }
      if (app.contains('/AppTranslocation/')) {
        return Installation(
          InstallKind.unsupported,
          path: app,
          reason:
              'macOS runs Gutter from a temporary read-only copy, because it '
              'still has the download quarantine flag. Move Gutter.app to '
              'Applications and clear the flag (see the release notes); then '
              'it can update itself.',
        );
      }
      return _writable(app, InstallKind.macApp);
    }
    if (windows ?? Platform.isWindows) {
      final dir = p.dirname(exe);
      if (!Directory(p.join(dir, 'data', 'flutter_assets')).existsSync()) {
        return const Installation(
          InstallKind.unsupported,
          reason: 'Gutter isn\'t running from its install folder.',
        );
      }
      if (File(p.join(dir, 'unins000.exe')).existsSync()) {
        return Installation(InstallKind.windowsInstaller, path: dir);
      }
      return _writable(dir, InstallKind.windowsFolder);
    }
    if (linux ?? Platform.isLinux) {
      final dir = p.dirname(exe);
      if (!Directory(p.join(dir, 'data', 'flutter_assets')).existsSync()) {
        return const Installation(
          InstallKind.unsupported,
          reason: 'Gutter isn\'t running from its release folder.',
        );
      }
      return _writable(dir, InstallKind.linuxBundle);
    }
    return const Installation(
      InstallKind.unsupported,
      reason: 'Updating isn\'t supported on this system.',
    );
  }

  /// [kind] at [path], if its folder lets us put the new version there.
  static Installation _writable(String path, InstallKind kind) {
    try {
      Directory(p.dirname(path)).createTempSync('.gutter-').deleteSync();
      return Installation(kind, path: path);
    } on FileSystemException {
      return Installation(
        InstallKind.unsupported,
        path: path,
        reason:
            'Gutter can\'t write to ${p.dirname(path)}, so it can\'t replace '
            'itself there.',
      );
    }
  }
}

class UpdateException implements Exception {
  UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

enum UpdateStage { idle, downloading, unpacking, ready, scheduled, failed }

/// Runs a command on the host, outside the Flatpak sandbox.
typedef HostRunner = Future<ProcessResult> Function(List<String> command);

/// Starts a command on the host that outlives Gutter.
typedef HostStarter = Future<void> Function(List<String> command);

/// Starts a process that outlives Gutter (the install helper).
typedef DetachedStarter = Future<void> Function(
  String executable,
  List<String> arguments,
);

/// Downloads a release, checks it against the release's SHA256SUMS, unpacks
/// it next to the installed copy, and swaps it in once Gutter quits. A
/// Flatpak updates with flatpak instead.
class Updater extends ChangeNotifier {
  Updater({
    this._installation,
    HttpClient Function()? httpClient,
    HostRunner? runOnHost,
    HostStarter? startOnHost,
    DetachedStarter? startDetached,
    String? flatpakInfo,
  }) : _httpClient = httpClient ?? _defaultClient,
       _runOnHost = runOnHost ?? _defaultRunOnHost,
       _startOnHost = startOnHost ?? _defaultStartOnHost,
       _startDetached = startDetached ?? _defaultStartDetached,
       _flatpakInfo = flatpakInfo ?? '/.flatpak-info';

  final Installation? _installation;
  final HttpClient Function() _httpClient;
  final HostRunner _runOnHost;
  final HostStarter _startOnHost;
  final DetachedStarter _startDetached;
  final String _flatpakInfo;

  static Future<void> _defaultStartDetached(String exe, List<String> args) =>
      Process.start(exe, args, mode: ProcessStartMode.detached);

  static const flatpakApp = 'dev.gutter.gutter';

  // The host command ends with Gutter (--watch-bus).
  static Future<ProcessResult> _defaultRunOnHost(List<String> command) =>
      Process.run('flatpak-spawn', ['--host', '--watch-bus', ...command]);

  // flatpak-spawn waits for [command]: it has to return quickly, or it keeps
  // the sandbox alive after Gutter quits.
  static Future<void> _defaultStartOnHost(List<String> command) =>
      Process.start('flatpak-spawn', [
        '--host',
        ...command,
      ], mode: ProcessStartMode.detached);

  late final Installation installation = _installation ?? Installation.detect();

  UpdateStage stage = UpdateStage.idle;

  /// The release being downloaded, or ready.
  ReleaseInfo? release;

  /// Download progress (0–1), when the size is known.
  double? progress;
  String? error;

  String? _work;
  String? _staged;

  bool get busy =>
      stage == UpdateStage.downloading || stage == UpdateStage.unpacking;

  static HttpClient _defaultClient() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..findProxy = HttpClient.findProxyFromEnvironment
    ..userAgent = 'gutter-updater';

  /// Gets [r] ready to install.
  Future<void> prepare(ReleaseInfo r) async {
    if (busy) return;
    if (release?.tag == r.tag &&
        (stage == UpdateStage.ready || stage == UpdateStage.scheduled)) {
      return;
    }
    if (installation.kind == InstallKind.flatpak) return _updateFlatpak(r);
    release = r;
    error = null;
    progress = null;
    _set(UpdateStage.downloading);
    // Next to the installed copy (so the swap is a rename), except for the
    // installer, which puts Gutter in place itself.
    final work = installation.kind == InstallKind.windowsInstaller
        ? p.join(Directory.systemTemp.path, 'gutter-update')
        : p.join(p.dirname(installation.path), '.gutter-update');
    try {
      if (!installation.canSelfUpdate) {
        throw UpdateException(installation.reason ?? 'Can\'t update.');
      }
      final asset =
          installation.assetIn(r) ??
          (throw UpdateException('${r.tag} has no download for this system.'));
      final sums =
          r.asset((n) => n == 'SHA256SUMS') ??
          (throw UpdateException(
            '${r.tag} has no checksums (SHA256SUMS) to check the download '
            'against.',
          ));
      final dir = Directory(work);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);
      _work = work;

      final file = File(p.join(work, asset.name));
      await _download(asset.url, file, size: asset.size);
      final expected = parseSha256Sums(
        utf8.decode(await _get(sums.url)),
      )[asset.name];
      if (expected == null) {
        throw UpdateException('SHA256SUMS doesn\'t list ${asset.name}.');
      }
      final actual = (await sha256.bind(file.openRead()).first).toString();
      if (actual != expected.toLowerCase()) {
        throw UpdateException(
          'The download doesn\'t match its checksum. Try again.',
        );
      }

      if (installation.kind == InstallKind.windowsInstaller) {
        _staged = file.path; // the new installer
        _set(UpdateStage.ready);
        return;
      }
      _set(UpdateStage.unpacking);
      final out = Directory(p.join(work, 'new'))..createSync();
      _staged = await _unpack(file, out);
      file.deleteSync();
      _set(UpdateStage.ready);
    } catch (e) {
      error = e is UpdateException
          ? e.message
          : e is SocketException || e is HttpException
          ? 'Download failed: ${e is HttpException ? e.message : e}'
          : e.toString();
      _cleanUp(work);
      _set(UpdateStage.failed);
    }
  }

  /// Updates the Flatpak from its remote, on the host. It's ready when the
  /// installed version differs from the running one (also when a software
  /// center already updated it).
  Future<void> _updateFlatpak(ReleaseInfo r) async {
    release = r;
    error = null;
    progress = null;
    _set(UpdateStage.downloading);
    try {
      final update = await _runOnHost([
        'flatpak',
        'update',
        '-y',
        '--noninteractive',
        flatpakApp,
      ]);
      if (update.exitCode != 0) {
        final out = '${update.stderr}'.trim();
        throw UpdateException(
          'flatpak update failed: '
          '${out.isEmpty ? 'exit code ${update.exitCode}' : out.split('\n').last}',
        );
      }
      final info = await _runOnHost([
        'flatpak',
        'info',
        '--show-commit',
        flatpakApp,
      ]);
      final installed = '${info.stdout}'.trim();
      if (installed.isEmpty || installed == runningFlatpakCommit()) {
        throw UpdateException(
          'Flatpak found nothing newer yet: the repository may still be '
          'publishing ${r.tag}, so try again in a few minutes. Installed '
          'from an older downloaded .flatpak file? Install the new one from '
          'the release page once: from then on, Gutter updates itself.',
        );
      }
      _set(UpdateStage.ready);
    } catch (e) {
      error = e is UpdateException ? e.message : e.toString();
      _set(UpdateStage.failed);
    }
  }

  /// The commit of the running Flatpak, from its /.flatpak-info.
  String? runningFlatpakCommit() {
    try {
      return RegExp(
        r'^app-commit=(\w+)',
        multiLine: true,
      ).firstMatch(File(_flatpakInfo).readAsStringSync())?.group(1);
    } on FileSystemException {
      return null;
    }
  }

  /// Unpacks [archive] into [out]; returns the new app bundle or folder.
  Future<String> _unpack(File archive, Directory out) async {
    Future<void> run(String exe, List<String> args) async {
      final r = await Process.run(exe, args);
      if (r.exitCode != 0) {
        throw UpdateException(
          'Couldn\'t unpack the update: ${'${r.stderr}'.trim()}',
        );
      }
    }

    if (installation.kind == InstallKind.macApp) {
      await run('ditto', ['-x', '-k', archive.path, out.path]);
      final app = out
          .listSync()
          .whereType<Directory>()
          .where((d) => d.path.endsWith('.app'))
          .firstOrNull;
      if (app == null) throw UpdateException('The download has no app.');
      await run('codesign', ['--verify', '--deep', '--strict', app.path]);
      return app.path;
    }
    // Windows 10 and 11 come with a tar that reads zips too.
    final windows = installation.kind == InstallKind.windowsFolder;
    await run('tar', [windows ? '-xf' : 'xzf', archive.path, '-C', out.path]);
    final exe = windows ? 'gutter.exe' : 'gutter';
    final dir = out
        .listSync()
        .whereType<Directory>()
        .where((d) => File(p.join(d.path, exe)).existsSync())
        .firstOrNull;
    if (dir == null) throw UpdateException('The download has no Gutter.');
    return dir.path;
  }

  /// Starts the helper that swaps the update in once Gutter (or [waitFor])
  /// exits; with [relaunch], it then starts the new version. For "restart
  /// now", quit right after.
  Future<void> install({required bool relaunch, int? waitFor}) async {
    if (stage != UpdateStage.ready) return;
    if (installation.kind == InstallKind.flatpak) {
      // Already installed: the next start runs it.
      if (relaunch) await _startOnHost(['sh', '-c', flatpakRelaunchScript]);
      _set(UpdateStage.scheduled);
      return;
    }
    final gutterPid = '${waitFor ?? pid}';
    final again = relaunch ? '1' : '0';
    if (installation.isWindows) {
      final setup = installation.kind == InstallKind.windowsInstaller;
      final script = File(p.join(_work!, 'install.ps1'))
        ..writeAsStringSync(setup ? windowsSetupScript : windowsSwapScript);
      await _startDetached('powershell.exe', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-File',
        script.path,
        gutterPid,
        if (setup) ...[
          _staged!,
          again,
          p.join(installation.path, 'gutter.exe'),
        ] else ...[
          installation.path,
          _staged!,
          again,
        ],
        _work!,
      ]);
      _set(UpdateStage.scheduled);
      return;
    }
    final script = File(p.join(_work!, 'install.sh'))
      ..writeAsStringSync(installScript);
    await _startDetached('/bin/sh', [
      script.path,
      gutterPid,
      installation.path,
      _staged!,
      again,
      _work!,
    ]);
    _set(UpdateStage.scheduled);
  }

  Future<void> _download(String url, File to, {int size = 0}) async {
    final client = _httpClient();
    try {
      final res = await _open(client, url);
      final total = res.contentLength > 0 ? res.contentLength : size;
      final sink = to.openWrite();
      var got = 0;
      var last = DateTime.now();
      try {
        await for (final chunk in res) {
          sink.add(chunk);
          got += chunk.length;
          final now = DateTime.now();
          if (total > 0 && now.difference(last).inMilliseconds > 100) {
            last = now;
            progress = got / total;
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }
      progress = 1;
    } finally {
      client.close(force: true);
    }
  }

  Future<List<int>> _get(String url) async {
    final client = _httpClient();
    try {
      final res = await _open(client, url);
      final out = BytesBuilder(copy: false);
      await res.forEach(out.add);
      return out.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  Future<HttpClientResponse> _open(HttpClient client, String url) async {
    final res = await (await client.getUrl(Uri.parse(url))).close();
    if (res.statusCode != 200) {
      await res.drain<void>();
      throw HttpException('the server returned ${res.statusCode}');
    }
    return res;
  }

  void _cleanUp(String work) {
    try {
      final d = Directory(work);
      if (d.existsSync()) d.deleteSync(recursive: true);
    } catch (_) {}
    _work = null;
    _staged = null;
  }

  void _set(UpdateStage s) {
    stage = s;
    notifyListeners();
  }
}

/// `sha256sum` output: file name → hex digest.
Map<String, String> parseSha256Sums(String text) => {
  for (final m in RegExp(
    r'^([0-9a-fA-F]{64}) [ *](.+)$',
    multiLine: true,
  ).allMatches(text))
    m.group(2)!.trim(): m.group(1)!,
};

/// On the host: waits (up to 10 s) for Gutter's Flatpak to quit, then
/// starts it again. It runs in the background so that flatpak-spawn, which
/// waits for it inside the sandbox (and so keeps the sandbox alive), returns
/// right away.
@visibleForTesting
const flatpakRelaunchScript = r'''
(
  for i in $(seq 50); do
    flatpak ps --columns=application | grep -qx dev.gutter.gutter || break
    sleep 0.2
  done
  exec flatpak run dev.gutter.gutter
) </dev/null >/dev/null 2>&1 &
''';

/// Waits for Gutter (pid $1) to quit, puts the new version ($3) in place of
/// the current one ($2), and with $4 = 1 starts it. $5 is the work folder,
/// next to $2 (so the moves are renames), removed at the end.
@visibleForTesting
const installScript = r'''#!/bin/sh
pid=$1 current=$2 new=$3 relaunch=$4 work=$5
while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
previous="$work/previous"
rm -rf "$previous"
if mv "$current" "$previous"; then
  if mv "$new" "$current"; then
    rm -rf "$previous"
  else
    mv "$previous" "$current"
  fi
fi
if [ "$(uname)" = Darwin ]; then
  xattr -dr com.apple.quarantine "$current" 2>/dev/null
fi
if [ "$relaunch" = 1 ]; then
  if [ "$(uname)" = Darwin ]; then
    open "$current"
  else
    "$current/gutter" >/dev/null 2>&1 &
  fi
fi
rm -rf "$work"
''';

/// Windows: waits for Gutter (pid GutterPid) to quit, puts the new folder
/// (New) in place of the current one (Current), back again if that fails,
/// and with Relaunch = 1 starts it. Moves are retried: a virus scanner can
/// hold the new files for a moment. Work, next to Current (so the moves
/// are renames), is removed at the end. Windows PowerShell 5.1 syntax.
@visibleForTesting
const windowsSwapScript = r'''
param([int]$GutterPid, [string]$Current, [string]$New, [string]$Relaunch,
  [string]$Work)
while (Get-Process -Id $GutterPid -ErrorAction SilentlyContinue) {
  Start-Sleep -Milliseconds 200
}
function Move-Retrying([string]$From, [string]$To) {
  for ($i = 0; $i -lt 25; $i++) {
    try {
      Move-Item -LiteralPath $From -Destination $To -ErrorAction Stop
      return $true
    } catch {
      Start-Sleep -Milliseconds 200
    }
  }
  return $false
}
$previous = Join-Path $Work 'previous'
if (Test-Path -LiteralPath $previous) {
  Remove-Item -LiteralPath $previous -Recurse -Force
}
if (Move-Retrying $Current $previous) {
  if (Move-Retrying $New $Current) {
    Remove-Item -LiteralPath $previous -Recurse -Force -ErrorAction SilentlyContinue
  } else {
    Move-Retrying $previous $Current | Out-Null
  }
}
if ($Relaunch -eq '1') {
  Start-Process -FilePath (Join-Path $Current 'gutter.exe')
}
Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
''';

/// Windows: waits for Gutter (pid GutterPid) to quit, runs the new
/// installer (Setup) silently, and with Relaunch = 1 starts Gutter (Exe)
/// again. Work, holding the installer, is removed at the end.
@visibleForTesting
const windowsSetupScript = r'''
param([int]$GutterPid, [string]$Setup, [string]$Relaunch, [string]$Exe,
  [string]$Work)
while (Get-Process -Id $GutterPid -ErrorAction SilentlyContinue) {
  Start-Sleep -Milliseconds 200
}
Start-Process -FilePath $Setup -Wait `
  -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'
if ($Relaunch -eq '1') {
  Start-Process -FilePath $Exe
}
Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
''';
