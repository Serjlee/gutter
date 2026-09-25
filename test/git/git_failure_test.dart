import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/git/git_runner.dart';
import 'package:gutter/git/repository.dart';

void main() {
  String explain(String stderr) =>
      explainGitFailure(stderr, gitPath: '/usr/bin/git');

  test('explains why git failed in a folder', () {
    expect(
      explain(
        'fatal: not a git repository (or any of the parent directories): .git',
      ),
      'Not a git repository',
    );
    // macOS's git stub without the command line tools.
    expect(
      explain(
        'xcrun: error: invalid active developer path '
        '(/Library/Developer/CommandLineTools), missing xcrun at: '
        '/Library/Developer/CommandLineTools/usr/bin/xcrun',
      ),
      contains('xcode-select --install'),
    );
    // A folder macOS privacy protection won't let git read.
    expect(
      explain(
        "fatal: cannot change to '/Users/x/Documents/app': "
        'Operation not permitted',
      ),
      contains('Privacy & Security'),
    );
    expect(
      explain("fatal: detected dubious ownership in repository at '/r'"),
      contains('safe.directory'),
    );
    expect(explain('\nfatal: something else\nmore\n'), 'fatal: something else');
  });

  test('probe reports a folder that is not a repository', () async {
    final dir = await Directory.systemTemp.createTemp('gutter_plain_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final r = await Repository.probe(dir.path);
    expect(r.root, isNull);
    expect(r.error, 'Not a git repository');
  });

  test('probe reports a git that cannot run', () async {
    final r = await Repository.probe(
      Directory.systemTemp.path,
      runner: GitRunner(gitPath: '/nonexistent/git'),
    );
    expect(r.root, isNull);
    expect(r.error, contains("Couldn't run git at /nonexistent/git"));
  });
}
