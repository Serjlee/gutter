import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/git/git_errors.dart';
import 'package:gutter/git/git_runner.dart';

import '../support/temp_repo.dart';

void main() {
  late TempRepo t;
  setUp(() async => t = await TempRepo.create());
  tearDown(() => t.dispose());

  test('logs every command, and links a failure to its entry', () async {
    t.commit('one', {'a.txt': 'a\n'});
    final log = t.repo.commands;
    await t.repo.headSha();
    await CommandLog.background(() => t.repo.status());
    expect(log.entries, hasLength(2));
    final head = log.entries.first;
    expect(head.args, contains('rev-parse'));
    expect(head.exitCode, 0);
    expect(head.background, isFalse);
    expect(head.duration, isNotNull);
    expect(log.entries.last.background, isTrue);

    final error = await t.repo
        .checkout('nope')
        .then<Object?>((_) => null, onError: (Object e) => e);
    expect(error, isA<GitException>());
    final entry = (error! as GitException).entry!;
    expect(log.entries.last, same(entry));
    expect(entry.failed, isTrue);
    expect(entry.running, isFalse);
    expect(entry.output, contains('nope'));
    expect(entry.commandLine, startsWith('git '));
  });

  test('a missing git is logged as not started', () async {
    final log = CommandLog();
    final runner = GitRunner(gitPath: '/nonexistent/git');
    await expectLater(
      runner.run(['status'], cwd: t.path, log: log),
      throwsA(isA<ProcessException>()),
    );
    expect(log.entries.single.startError, contains('/nonexistent/git'));
    expect(log.entries.single.failed, isTrue);
  });

  test('a full log drops background refreshes first', () async {
    final log = CommandLog(maxEntries: 3);
    GitLogEntry add(bool background) {
      final e = background
          ? _inBackground(() => log.start(['status'], cwd: '/'))
          : log.start(['commit'], cwd: '/');
      e.exitCode = 0;
      return e;
    }

    final user = add(false);
    add(true);
    add(true);
    final last = add(false);
    expect(log.entries, hasLength(3));
    expect(log.entries.first, same(user));
    expect(log.entries.last, same(last));
    expect(log.entries.where((e) => e.background), hasLength(1));
  });

  test('ssh never prompts, unless git has its own ssh setup', () async {
    final runner = GitRunner();
    expect(await runner.sshEnvironment(t.path), {
      'GIT_SSH_COMMAND': 'ssh -oBatchMode=yes',
    });
    t.git(['config', 'core.sshCommand', 'ssh -i /tmp/key']);
    expect(await runner.sshEnvironment(t.path), isEmpty);
  }, skip: Platform.environment.containsKey('GIT_SSH_COMMAND'));

  test('a fetch that runs into another git\'s lock tries again', () async {
    final upstream = await TempRepo.create();
    addTearDown(upstream.dispose);
    upstream.commit('one', {'a.txt': 'a\n'});
    t.git(['remote', 'add', 'origin', upstream.path]);
    t.git(['fetch', '-q', 'origin']);
    upstream.commit('two', {'a.txt': 'b\n'});
    // Held by "another git" until shortly after the first attempt.
    final lock = File('${t.path}/.git/refs/remotes/origin/main.lock')
      ..writeAsStringSync('');
    Timer(const Duration(milliseconds: 300), lock.deleteSync);
    await t.repo.fetch();
    final fetches = t.repo.commands.entries.where(
      (e) => e.args.contains('fetch'),
    );
    expect(fetches.map((e) => e.failed), [true, false]);
    expect(
      t.git(['rev-parse', 'origin/main']).trim(),
      upstream.git(['rev-parse', 'HEAD']).trim(),
    );
  });

  test('a failed background fetch says which remote failed', () async {
    t.commit('one', {'a.txt': 'a\n'});
    t.git(['remote', 'add', 'origin', t.path]);
    t.git(['remote', 'add', 'broken', '/nonexistent/repo.git']);
    final error = await CommandLog.background(() => t.repo.fetch())
        .then<Object?>((_) => null, onError: (Object e) => e);
    expect(error, isA<GitException>());
    expect((error! as GitException).args, isNot(contains('--quiet')));
    expect(summarizeGitError(error), startsWith('Couldn\'t fetch broken. '));
  });

  group('error summaries', () {
    String summary(String stderr, {String stdout = '', bool windows = false}) =>
        summarizeGitError(
          GitException(['fetch'], 128, stderr, stdout: stdout),
          windows: windows,
        );

    test('explain the usual suspects', () {
      expect(
        summary(
          "fatal: could not read Username for 'https://github.com': "
          'terminal prompts disabled',
        ),
        contains('credential helper'),
      );
      expect(
        summary(
          'git@github.com: Permission denied (publickey).\n'
          'fatal: Could not read from remote repository.\n\n'
          'Please make sure you have the correct access rights\n'
          'and the repository exists.',
        ),
        contains('ssh-add'),
      );
      expect(
        summary('Host key verification failed.\nfatal: Could not read'),
        contains('ssh -T'),
      );
      expect(
        summary(
          'ssh: Could not resolve hostname github.com: nodename nor servname '
          'provided, or not known',
        ),
        contains('network'),
      );
      expect(
        summary('ERROR: Repository not found.\nfatal: Could not read'),
        contains('wasn\'t found'),
      );
      expect(
        summary(
          ' ! [rejected]        main -> main (fetch first)\n'
          "error: failed to push some refs to 'origin'",
        ),
        contains('Pull first'),
      );
    });

    test('on Windows, point at what Git for Windows offers', () {
      expect(
        summary(
          "fatal: could not read Username for 'https://github.com': "
          'terminal prompts disabled',
          windows: true,
        ),
        contains('Git Credential Manager'),
      );
      final ssh = summary(
        'git@github.com: Permission denied (publickey).',
        windows: true,
      );
      expect(ssh, contains('OpenSSH Authentication Agent'));
      expect(ssh, contains('core.sshCommand'));
    });

    test('otherwise show git\'s own message, without the prefix', () {
      expect(summary('warning: x\nfatal: bad object abc\n'), 'Bad object abc');
      expect(summary('something odd\n'), 'Something odd');
    });

    test('a failed fetch --all names the remote', () {
      const stderr =
          'Fetching origin\nFetching broken\n'
          "fatal: '/nope.git' does not appear to be a git repository\n"
          'fatal: Could not read from remote repository.\n'
          'error: could not fetch broken\n';
      expect(
        summary(stderr),
        allOf(
          startsWith('Couldn\'t fetch broken. '),
          contains('wasn\'t found'),
        ),
      );
      expect(
        summary('Fetching a\nFetching b\nerror: could not fetch b\n'),
        'Couldn\'t fetch b.',
      );
    });

    test('lock contention is told apart', () {
      bool lock(String stderr) =>
          isLockContention(GitException(['fetch'], 1, stderr));
      expect(
        lock(
          "error: cannot lock ref 'refs/remotes/origin/main': is at 1a2b "
          'but expected 3c4d',
        ),
        isTrue,
      );
      expect(
        lock("fatal: Unable to create '/r/.git/shallow.lock': File exists."),
        isTrue,
      );
      expect(lock('fatal: Could not read from remote repository.'), isFalse);
    });

    test('details show the command, its output and exit code', () {
      final d = gitErrorDetails(
        GitException(['fetch', '--prune'], 128, 'fatal: nope\n'),
      )!;
      expect(d, startsWith('\$ git fetch --prune\nfatal: nope\n'));
      expect(d, endsWith('(exit code 128)'));
      expect(gitErrorDetails(StateError('x')), isNull);
    });
  });
}

T _inBackground<T>(T Function() body) {
  late T result;
  CommandLog.background(() async => result = body());
  return result;
}
