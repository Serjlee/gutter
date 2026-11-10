import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/app/open_with.dart';
import 'package:path/path.dart' as p;

void main() {
  test('a .desktop file: its entry, not other groups', () {
    final e = parseDesktopEntry('''
[Desktop Entry]
Type=Application
Name=Sublime Text
Name[it]=Testo Sublime
Exec=subl %F
# a comment
[Desktop Action new-window]
Name=New Window
Exec=subl --new-window
''')!;
    expect(e.name, 'Sublime Text');
    expect(e.exec, 'subl %F');
    expect(e.hidden, isFalse);
    expect(e.opensFiles, isTrue);
    expect(
      parseDesktopEntry('[Desktop Entry]\nName=X\nExec=x\nNoDisplay=true')!
          .hidden,
      isTrue,
    );
    expect(
      parseDesktopEntry('[Desktop Entry]\nType=Link\nName=X\nExec=x')!.hidden,
      isTrue,
    );
    expect(parseDesktopEntry('[Desktop Entry]\nName=X')?.exec, isNull);
  });

  test('a .desktop command line, opening a folder', () {
    const repo = '/work/my repo';
    expect(execArgs('subl %F', repo), ['subl', repo]);
    expect(execArgs('code --new-window %U %i %c', repo), [
      'code',
      '--new-window',
      repo,
    ]);
    // No file code: the folder comes last.
    expect(execArgs('gedit', repo), ['gedit', repo]);
    expect(execArgs(r'"/opt/My App/app" --title "a \"b\"" 100%%', repo), [
      '/opt/My App/app',
      '--title',
      'a "b"',
      '100%',
      repo,
    ]);
    // Flatpak's: the folder between its markers.
    expect(
      execArgs(
        '/usr/bin/flatpak run --file-forwarding org.gnome.gedit @@ %U @@',
        repo,
      ),
      [
        '/usr/bin/flatpak',
        'run',
        '--file-forwarding',
        'org.gnome.gedit',
        '@@',
        repo,
        '@@',
      ],
    );
  });

  test('installed apps: on Linux, those whose .desktop opens files, the '
      'user\'s first', () async {
    final root = await Directory.systemTemp.createTemp('gutter_apps_');
    addTearDown(() => root.deleteSync(recursive: true));
    void desktop(String dir, String id, String body) {
      final d = Directory(p.join(root.path, dir, 'applications'))
        ..createSync(recursive: true);
      File(p.join(d.path, '$id.desktop'))
          .writeAsStringSync('[Desktop Entry]\nType=Application\n$body\n');
    }

    desktop('system', 'editor', 'Name=Editor\nExec=editor %F');
    desktop('system', 'settings', 'Name=Settings\nExec=settings');
    desktop('system', 'hidden', 'Name=Hidden\nExec=hidden %f\nNoDisplay=true');
    desktop('system', 'vim', 'Name=Vim\nExec=vim %F\nTerminal=true');
    desktop('system', 'zed', 'Name=Zed\nExec=zed %U');
    // The user's own Zed shadows the system's.
    desktop('user', 'zed', 'Name=Zed (mine)\nExec=/opt/zed %U');

    final apps = await findInstalledApps(
      environment: {
        'HOME': root.path,
        'XDG_DATA_HOME': p.join(root.path, 'user'),
        'XDG_DATA_DIRS': p.join(root.path, 'system'),
      },
      linux: true,
      macOS: false,
    );
    expect([for (final a in apps) a.name], ['Editor', 'Zed (mine)']);
    expect(
      apps.last.id,
      '$desktopPrefix${p.join(root.path, 'user', 'applications', 'zed.desktop')}',
    );
    expect(openWithLabel(apps.first.id), 'Editor');

    // Opened with its own command line.
    final started = <String>[];
    final saved = startDetached;
    startDetached = (exe, args, _) async =>
        started.add([exe, ...args].join(' '));
    addTearDown(() => startDetached = saved);
    await openWith(apps.last.id, '/work/repo');
    expect(started.single, '/opt/zed /work/repo');
  });

  test('installed apps: on macOS, the app bundles', () async {
    final home = await Directory.systemTemp.createTemp('gutter_home_');
    addTearDown(() => home.deleteSync(recursive: true));
    Directory(p.join(home.path, 'Applications', 'Sublime Text.app'))
        .createSync(recursive: true);
    File(p.join(home.path, 'Applications', 'notes.txt')).createSync();
    final apps = await findInstalledApps(
      environment: {'HOME': home.path},
      macOS: true,
    );
    expect(apps.where((a) => a.name == 'Sublime Text'), hasLength(1));
    expect(apps.where((a) => a.name == 'notes'), isEmpty);
  });
}
