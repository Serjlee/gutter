import 'dart:io';

import 'package:gutter/git/repository.dart';
import 'package:path/path.dart' as p;

/// A throwaway repository for integration tests.
class TempRepo {
  TempRepo._(this.dir);

  final Directory dir;
  String get path => dir.path;
  late final Repository repo = Repository(path);
  int _clock = 1700000000;

  static Future<TempRepo> create({String branch = 'main'}) async {
    final dir = await Directory.systemTemp.createTemp('gutter_test_');
    final t = TempRepo._(Directory(dir.resolveSymbolicLinksSync()));
    t.git(['init', '-q', '-b', branch]);
    t.git(['config', 'user.name', 'Test User']);
    t.git(['config', 'user.email', 'test@example.com']);
    t.git(['config', 'commit.gpgsign', 'false']);
    return t;
  }

  Map<String, String> get _env => {
        'GIT_AUTHOR_DATE': '$_clock +0000',
        'GIT_COMMITTER_DATE': '$_clock +0000',
        'GIT_CONFIG_NOSYSTEM': '1',
        'HOME': dir.path,
      };

  String git(List<String> args, {String? cwd}) {
    final r = Process.runSync('git', args,
        workingDirectory: cwd ?? path, environment: _env);
    if (r.exitCode != 0) {
      throw StateError('git ${args.join(' ')} failed: ${r.stderr}');
    }
    return r.stdout as String;
  }

  void write(String file, String content) {
    final f = File(p.join(path, file));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  String read(String file) => File(p.join(path, file)).readAsStringSync();

  /// Writes [files] and commits them; returns the new sha.
  String commit(String message, [Map<String, String> files = const {}]) {
    files.forEach(write);
    _clock += 60;
    git(['add', '-A']);
    git(['commit', '-q', '--allow-empty', '-m', message]);
    return git(['rev-parse', 'HEAD']).trim();
  }

  List<String> subjects([String rev = 'HEAD']) =>
      git(['log', '--format=%s', rev]).trim().split('\n');

  void dispose() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}
