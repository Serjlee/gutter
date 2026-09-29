import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/update_checker.dart';
import 'package:gutter/app/updater.dart';
import 'package:path/path.dart' as p;

/// A Linux release folder whose `gutter` prints [label] (and, run, writes
/// it to [marker]).
void _bundle(String dir, String label, {String? marker}) {
  Directory(p.join(dir, 'data', 'flutter_assets')).createSync(recursive: true);
  final exe = File(p.join(dir, 'gutter'))
    ..writeAsStringSync(
      '#!/bin/sh\necho $label${marker == null ? '' : ' > $marker'}\n',
    );
  Process.runSync('chmod', ['+x', exe.path]);
}

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  late Directory root;
  late HttpServer server;
  late Map<String, List<int>> files;
  late String installed;
  late String marker;

  ReleaseInfo release({bool sums = true}) => ReleaseInfo(
    tag: 'v0.2.0',
    url: 'https://example.com/release',
    publishedAt: null,
    assets: [
      for (final name in files.keys)
        if (sums || name != 'SHA256SUMS')
          ReleaseAsset(
            name: name,
            url: 'http://127.0.0.1:${server.port}/$name',
          ),
    ],
  );

  Updater updater() => Updater(
    installation: Installation.detect(
      executable: p.join(installed, 'gutter'),
      macOS: false,
      linux: true,
      flatpak: false,
    ),
    httpClient: HttpClient.new,
  );

  setUp(() async {
    root = Directory.systemTemp.createTempSync('gutter_update_');
    installed = p.join(root.path, 'opt', 'Gutter');
    marker = p.join(root.path, 'launched');
    _bundle(installed, 'old');
    // The release: a tarball of the new folder, and its checksum.
    final src = p.join(root.path, 'src');
    _bundle(p.join(src, 'gutter-linux-x64-0.2.0'), 'new', marker: marker);
    final tarball = p.join(root.path, 'gutter-linux-x64-0.2.0.tar.gz');
    Process.runSync('tar', [
      'czf',
      tarball,
      '-C',
      src,
      'gutter-linux-x64-0.2.0',
    ]);
    final bytes = File(tarball).readAsBytesSync();
    files = {
      'gutter-linux-x64-0.2.0.tar.gz': bytes,
      'Gutter-macos-0.2.0.zip': [1, 2, 3],
      'SHA256SUMS':
          '${sha256.convert(bytes)}  gutter-linux-x64-0.2.0.tar.gz\n'
                  '${sha256.convert([1, 2, 3])}  Gutter-macos-0.2.0.zip\n'
              .codeUnits,
    };
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final body = files[req.uri.pathSegments.last];
      req.response.statusCode = body == null ? 404 : 200;
      if (body != null) req.response.add(body);
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    root.deleteSync(recursive: true);
  });

  test('downloads, checks, swaps in and restarts the new version', () async {
    final u = updater();
    expect(u.installation.kind, InstallKind.linuxBundle);
    await u.prepare(release());
    expect(u.error, isNull);
    expect(u.stage, UpdateStage.ready);
    // Nothing changes until Gutter quits.
    final gutter = await Process.start('sleep', ['0.5']);
    await u.install(relaunch: true, waitFor: gutter.pid);
    expect(u.stage, UpdateStage.scheduled);
    expect(Process.runSync(p.join(installed, 'gutter'), []).stdout, 'old\n');
    await gutter.exitCode;
    await _until(() => File(marker).existsSync());
    expect(File(marker).readAsStringSync(), 'new\n');
    await _until(
      () => !Directory(p.join(root.path, 'opt', '.gutter-update')).existsSync(),
    );
    expect(Directory(p.join(root.path, 'opt')).listSync().map((e) => e.path), [
      installed,
    ]);
  });

  test('install on quit: no restart', () async {
    final u = updater();
    await u.prepare(release());
    final gutter = await Process.start('sleep', ['0.2']);
    await u.install(relaunch: false, waitFor: gutter.pid);
    await _until(
      () => !Directory(p.join(root.path, 'opt', '.gutter-update')).existsSync(),
    );
    expect(File(marker).existsSync(), isFalse); // not started
    expect(
      File(p.join(installed, 'gutter')).readAsStringSync(),
      contains('new'),
    );
  });

  test('a download that doesn\'t match its checksum is dropped', () async {
    files['SHA256SUMS'] =
        '${'0' * 64}  gutter-linux-x64-0.2.0.tar.gz\n'.codeUnits;
    final u = updater();
    await u.prepare(release());
    expect(u.stage, UpdateStage.failed);
    expect(u.error, contains('checksum'));
    expect(Directory(p.join(root.path, 'opt')).listSync(), hasLength(1));

    final v = updater();
    await v.prepare(release(sums: false));
    expect(v.stage, UpdateStage.failed);
    expect(v.error, contains('SHA256SUMS'));
  });

  test('knows how it was installed', () {
    final mac = Installation.detect(
      executable: p.join(root.path, 'Gutter.app', 'Contents', 'MacOS', 'x'),
      macOS: true,
      flatpak: false,
    );
    expect(mac.kind, InstallKind.macApp);
    expect(mac.path, p.join(root.path, 'Gutter.app'));
    expect(mac.assetIn(release())!.name, 'Gutter-macos-0.2.0.zip');

    final translocated = Installation.detect(
      executable:
          '/private/var/folders/x/AppTranslocation/1/d/Gutter.app/'
          'Contents/MacOS/gutter',
      macOS: true,
      flatpak: false,
    );
    expect(translocated.kind, InstallKind.unsupported);
    expect(translocated.reason, contains('quarantine'));

    expect(Installation.detect(flatpak: true).kind, InstallKind.flatpak);
    expect(
      Installation.detect(
        executable: p.join(root.path, 'somewhere', 'gutter'),
        macOS: false,
        linux: true,
        flatpak: false,
      ).kind,
      InstallKind.unsupported, // not a release folder
    );
  });

  test('reads sha256sum output', () {
    expect(parseSha256Sums('${'a' * 64}  x.zip\n${'B' * 64} *y z.tar.gz\n'), {
      'x.zip': 'a' * 64,
      'y z.tar.gz': 'B' * 64,
    });
  });
}
