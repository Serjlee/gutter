import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/open_with.dart';
import 'package:gutter/app/user_env.dart';
import 'package:path/path.dart' as p;

void main() {
  test('the login shell\'s PATH, whatever else its rc files print', () async {
    final home = await Directory.systemTemp.createTemp('gutter_home_');
    addTearDown(() => home.deleteSync(recursive: true));
    // As installers do: added in .bashrc, which .profile reads.
    File(p.join(home.path, '.bashrc')).writeAsStringSync(
      'echo "Welcome back"\nexport PATH="\$HOME/.opencode/bin:\$PATH"\n',
    );
    File(p.join(home.path, '.profile'))
        .writeAsStringSync('. "\$HOME/.bashrc"\n');

    final path = await readLoginShellPath(
      shell: '/bin/bash',
      environment: {'HOME': home.path},
      flatpak: false,
    );
    expect(path, startsWith('${home.path}/.opencode/bin:'));
  });

  test('a shell that doesn\'t answer, or isn\'t known, is left be', () async {
    final home = await Directory.systemTemp.createTemp('gutter_home_');
    addTearDown(() => home.deleteSync(recursive: true));
    File(p.join(home.path, '.profile')).writeAsStringSync('sleep 10\n');
    expect(
      await readLoginShellPath(
        shell: '/bin/bash',
        environment: {'HOME': home.path},
        flatpak: false,
        timeout: const Duration(milliseconds: 300),
      ),
      isNull,
    );
    expect(await readLoginShellPath(shell: '/usr/bin/nu'), isNull);
    expect(
      parseShellPath('noise __GUTTER_PATH__/a:/b__GUTTER_PATH__'),
      '/a:/b',
    );
    expect(parseShellPath('no marks'), isNull);
  });

  test(
    'sandboxed, the host\'s apps run on the host, with the user\'s PATH',
    () {
      expect(
        sandboxPath('/usr/bin/subl', flatpak: true),
        '/run/host/usr/bin/subl',
      );
      expect(sandboxPath('/home/me/bin/x', flatpak: true), '/home/me/bin/x');
      expect(sandboxPath('/usr/bin/subl', flatpak: false), '/usr/bin/subl');
      final (spawn, spawnArgs) = startCommand(
        'subl',
        ['/work/r'],
        cwd: '/work/r',
        path: '/a:/b',
        flatpak: true,
      );
      expect(
        [spawn, ...spawnArgs],
        [
          'flatpak-spawn',
          '--host',
          '--directory=/work/r',
          '--env=PATH=/a:/b',
          'subl',
          '/work/r',
        ],
      );
      final (exe, args) = startCommand(
        'subl',
        ['/work/r'],
        cwd: '/work/r',
        path: '/a:/b',
        flatpak: false,
      );
      expect([exe, ...args], ['subl', '/work/r']);
    },
  );

  test('sandboxed, installed apps are the host\'s', () async {
    final home = await Directory.systemTemp.createTemp('gutter_home_');
    addTearDown(() => home.deleteSync(recursive: true));
    final d = Directory(p.join(home.path, '.local', 'share', 'applications'))
      ..createSync(recursive: true);
    File(p.join(d.path, 'zed.desktop')).writeAsStringSync(
      '[Desktop Entry]\nType=Application\nName=Zed\nExec=zed %U\n',
    );
    final apps = await findInstalledApps(
      // The sandbox's own data folder isn't where the host's apps are.
      environment: {
        'HOME': home.path,
        'XDG_DATA_HOME': p.join(home.path, '.var', 'app', 'x', 'data'),
      },
      linux: true,
      macOS: false,
      flatpak: true,
    );
    expect([for (final a in apps) a.name], contains('Zed'));
  });
}
