import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/git/git_runner.dart';

void main() {
  group('finding git', () {
    String resolve(
      Set<String> files, {
      Map<String, String> env = const {},
      bool windows = false,
      bool macOS = false,
    }) => GitRunner.resolveGitPath(
      environment: env,
      windows: windows,
      macOS: macOS,
      exists: files.contains,
    );

    test('on Windows: PATH first, then where Git for Windows installs', () {
      const env = {
        'PATH': r'C:\Windows\system32;C:\Tools',
        'ProgramFiles': r'C:\Program Files',
        'LOCALAPPDATA': r'C:\Users\me\AppData\Local',
      };
      const machine = r'C:\Program Files\Git\cmd\git.exe';
      const user = r'C:\Users\me\AppData\Local\Programs\Git\cmd\git.exe';
      expect(
        resolve({r'C:\Tools\git.exe', machine}, env: env, windows: true),
        r'C:\Tools\git.exe',
      );
      // Installed after Gutter started: not on its PATH yet.
      expect(resolve({machine}, env: env, windows: true), machine);
      expect(resolve({user}, env: env, windows: true), user);
      // Not installed: plain git.exe, which fails to run.
      expect(resolve({}, env: env, windows: true), 'git.exe');
    });

    test('on macOS, Homebrew\'s git before /usr/bin\'s stub', () {
      const env = {'PATH': '/usr/bin:/bin'};
      expect(
        resolve(
          {'/usr/bin/git', '/opt/homebrew/bin/git'},
          env: env,
          macOS: true,
        ),
        '/opt/homebrew/bin/git',
      );
      expect(resolve({'/usr/bin/git'}, env: env), '/usr/bin/git');
      expect(resolve({}, env: env), 'git');
    });
  });
}
