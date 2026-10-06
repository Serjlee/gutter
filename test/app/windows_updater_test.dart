import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/update_checker.dart';
import 'package:gutter/app/updater.dart';
import 'package:path/path.dart' as p;

/// A Windows Gutter folder: gutter.exe and its data, and the installer's
/// uninstaller when [installed].
String _folder(String root, {bool installed = false}) {
  final dir = p.join(root, 'Gutter');
  Directory(p.join(dir, 'data', 'flutter_assets')).createSync(recursive: true);
  File(p.join(dir, 'gutter.exe')).writeAsStringSync('old');
  if (installed) File(p.join(dir, 'unins000.exe')).writeAsStringSync('');
  return dir;
}

/// PowerShell, to run the install scripts (GitHub's runners have it).
final _pwsh = () {
  for (final exe in ['pwsh', 'powershell']) {
    try {
      if (Process.runSync(exe, ['-NoProfile', '-Command', 'exit 0']).exitCode ==
          0) {
        return exe;
      }
    } catch (_) {}
  }
  return null;
}();

/// A script standing in for an executable: writes its arguments to [out].
void _stub(String path, String out) {
  File(path).writeAsStringSync('#!/bin/sh\necho "\$@" > "$out"\n');
  Process.runSync('chmod', ['+x', path]);
}

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('gutter_win_'));
  tearDown(() => root.deleteSync(recursive: true));

  test('only an installed copy updates itself', () {
    final copied = _folder(p.join(root.path, 'copy'));
    final installed = _folder(p.join(root.path, 'inst'), installed: true);
    Installation detect(String dir) => Installation.detect(
      executable: p.join(dir, 'gutter.exe'),
      windows: true,
      flatpak: false,
    );
    expect(detect(installed).kind, InstallKind.windows);
    expect(detect(copied).kind, InstallKind.unsupported);
    expect(detect(copied).reason, contains('setup.exe'));

    final release = ReleaseInfo(
      tag: 'v0.2.0',
      url: '',
      publishedAt: null,
      assets: [
        for (final n in [
          'gutter-linux-x64-0.2.0.tar.gz',
          'Gutter-windows-x64-0.2.0-setup.exe',
        ])
          ReleaseAsset(name: n, url: n),
      ],
    );
    expect(
      detect(installed).assetIn(release)?.name,
      'Gutter-windows-x64-0.2.0-setup.exe',
    );
  });

  test(
    'the installer is downloaded, checked, and run after Gutter quits',
    () async {
      final dir = _folder(p.join(root.path, 'inst'), installed: true);
      final setup = utf8.encode('new installer');
      const name = 'Gutter-windows-x64-0.2.0-setup.exe';
      final files = {
        name: setup,
        'SHA256SUMS': utf8.encode('${sha256.convert(setup)}  $name\n'),
      };
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        final body = files[req.uri.pathSegments.last];
        req.response.statusCode = body == null ? 404 : 200;
        if (body != null) req.response.add(body);
        req.response.close();
      });
      addTearDown(() => server.close(force: true));

      final started = <(String, List<String>)>[];
      final u = Updater(
        installation: Installation(InstallKind.windows, path: dir),
        httpClient: HttpClient.new,
        startDetached: (exe, args) async => started.add((exe, args)),
      );
      await u.prepare(
        ReleaseInfo(
          tag: 'v0.2.0',
          url: '',
          publishedAt: null,
          assets: [
            for (final n in files.keys)
              ReleaseAsset(name: n, url: 'http://127.0.0.1:${server.port}/$n'),
          ],
        ),
      );
      expect(u.error, isNull);
      expect(u.stage, UpdateStage.ready);

      await u.install(relaunch: true, waitFor: 4242);
      expect(u.stage, UpdateStage.scheduled);
      final (exe, args) = started.single;
      expect(exe, 'powershell.exe');
      final script = args[args.indexOf('-File') + 1];
      expect(File(script).readAsStringSync(), windowsSetupScript);
      final work = p.dirname(script);
      expect(args.sublist(args.indexOf('-File') + 2), [
        '4242',
        p.join(work, name),
        '1',
        p.join(dir, 'gutter.exe'),
        work,
      ]);
      expect(File(p.join(work, name)).readAsBytesSync(), setup);
      Directory(work).deleteSync(recursive: true);
    },
  );

  group(
    'install script',
    skip: _pwsh == null
        ? 'no PowerShell'
        // Unix stand-ins for Gutter and the installer.
        : Platform.isWindows
        ? 'not on Windows'
        : null,
    () {
      /// Runs [script] with [args] once a stand-in for Gutter has quit.
      Future<void> run(
        String script,
        List<String> Function(int pid) args,
      ) async {
        final gutter = await Process.start('sleep', ['1']);
        final file = File(p.join(root.path, 'work', 'install.ps1'))
          ..createSync(recursive: true)
          ..writeAsStringSync(script);
        final r = await Process.run(_pwsh!, [
          '-NoProfile',
          '-File',
          file.path,
          ...args(gutter.pid),
        ]);
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        expect(await gutter.exitCode, 0); // it waited for Gutter
      }

      test('the installer runs silently, then Gutter restarts', () async {
        final work = p.join(root.path, 'work');
        Directory(work).createSync(recursive: true);
        final setup = p.join(work, 'setup.exe');
        final ran = p.join(root.path, 'setup-args');
        _stub(setup, ran);
        final exe = p.join(root.path, 'gutter.exe');
        final launched = p.join(root.path, 'launched');
        _stub(exe, launched);

        await run(windowsSetupScript, (pid) => ['$pid', setup, '1', exe, work]);
        expect(
          File(ran).readAsStringSync().trim(),
          '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART',
        );
        for (var i = 0; i < 50 && !File(launched).existsSync(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(File(launched).existsSync(), isTrue);
        expect(Directory(work).existsSync(), isFalse);
      });
    },
  );
}
