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

  group('error summaries', () {
    String summary(String stderr, {String stdout = ''}) =>
        summarizeGitError(GitException(['fetch'], 128, stderr, stdout: stdout));

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

    test('otherwise show git\'s own message, without the prefix', () {
      expect(summary('warning: x\nfatal: bad object abc\n'), 'Bad object abc');
      expect(summary('something odd\n'), 'Something odd');
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
