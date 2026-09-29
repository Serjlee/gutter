import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/git/conflict.dart';
import 'package:gutter/git/models.dart';

import '../support/temp_repo.dart';

void main() {
  group('ConflictedText', () {
    const text =
        'a\n'
        '<<<<<<< HEAD\n'
        'mine\n'
        '=======\n'
        'theirs\n'
        '>>>>>>> feature\n'
        'b\n'
        '<<<<<<< HEAD\n'
        'x\n'
        '||||||| base\n'
        'original\n'
        '=======\n'
        'y\n'
        'y2\n'
        '>>>>>>> feature\n'
        'c';

    test('splits text and conflicts, with labels and the base', () {
      final t = ConflictedText.parse(text);
      expect(t.segments, hasLength(5));
      final c = t.conflicts;
      expect(c, hasLength(2));
      expect(c[0].current, ['mine\n']);
      expect(c[0].incoming, ['theirs\n']);
      expect(c[0].base, isNull);
      expect(c[0].currentLabel, 'HEAD');
      expect(c[0].incomingLabel, 'feature');
      expect(c[1].base, ['original\n']);
      expect(c[1].incoming, ['y\n', 'y2\n']);
      expect(ConflictedText.hasMarkers(text), isTrue);
    });

    test('resolves one conflict at a time', () {
      final t = ConflictedText.parse(text);
      final once = t.resolve(0, ConflictChoice.incoming);
      expect(once, startsWith('a\ntheirs\nb\n<<<<<<< HEAD\n'));
      final both = ConflictedText.parse(once).resolve(0, ConflictChoice.both);
      expect(both, 'a\ntheirs\nb\nx\ny\ny2\nc');
      expect(ConflictedText.hasMarkers(both), isFalse);
      expect(
        t.resolve(1, ConflictChoice.current),
        endsWith('>>>>>>> feature\nb\nx\nc'),
      );
    });

    test('broken or unrelated markers stay text', () {
      const broken = '<<<<<<< HEAD\nno end\n=======\nstill none\n';
      expect(ConflictedText.parse(broken).conflicts, isEmpty);
      expect(ConflictedText.hasMarkers(broken), isFalse);
      expect(ConflictedText.hasMarkers('a\n=======\nb\n'), isFalse);
    });

    test('keeps CRLF line endings', () {
      const crlf = 'a\r\n<<<<<<< HEAD\r\nm\r\n=======\r\nt\r\n>>>>>>> x\r\n';
      final t = ConflictedText.parse(crlf);
      expect(t.conflicts.single.current, ['m\r\n']);
      expect(t.resolve(0, ConflictChoice.incoming), 'a\r\nt\r\n');
    });
  });

  group('Repository conflicts', () {
    late TempRepo t;
    setUp(() async {
      t = await TempRepo.create();
      t.commit('init', {'a.txt': 'one\n', 'gone.txt': 'x\n'});
      t.git(['checkout', '-q', '-b', 'feature']);
      t.commit('theirs', {'a.txt': 'theirs\n', 'gone.txt': 'changed\n'});
      t.git(['checkout', '-q', 'main']);
      t.write('a.txt', 'mine\n');
      t.git(['rm', '-q', 'gone.txt']);
      t.commit('mine');
    });
    tearDown(() => t.dispose());

    Future<void> mergeFeature() async {
      await expectLater(t.repo.merge('feature'), throwsA(anything));
      expect(await t.repo.operation(), RepoOperation.merge);
    }

    test('names the sides and prepares the message', () async {
      await mergeFeature();
      final sides = await t.repo.conflictSides(RepoOperation.merge);
      expect(sides.current, 'main');
      expect(sides.incoming, 'feature');
      expect(sides.description, 'Merging feature into main');
      expect(
        await t.repo.preparedMessage(),
        startsWith("Merge branch 'feature'"),
      );
      final text = (await t.repo.readWorkingText('a.txt'))!;
      expect(ConflictedText.parse(text).conflicts.single.incoming, [
        'theirs\n',
      ]);
    });

    test('a side that deleted the file resolves by deleting it', () async {
      await mergeFeature();
      final status = await t.repo.status();
      expect(
        status.conflicted.map((e) => '${e.conflictCode} ${e.path}'),
        containsAll(['UU a.txt', 'DU gone.txt']),
      );
      await t.repo.resolveWith('gone.txt', ours: true); // we deleted it
      expect((await t.repo.status()).conflicted.map((e) => e.path), ['a.txt']);
      expect(t.git(['ls-files', 'gone.txt']).trim(), isEmpty);

      await t.repo.writeWorkingText('a.txt', 'merged\n');
      await t.repo.markResolved(['a.txt']);
      await t.repo.continueOperation(RepoOperation.merge);
      expect(await t.repo.operation(), RepoOperation.none);
      expect(t.read('a.txt'), 'merged\n');
    });

    test('cherry-pick sides: the picked commit', () async {
      final sha = t.git(['rev-parse', '--short', 'feature']).trim();
      final picked = Commit(
        sha: t.git(['rev-parse', 'feature']).trim(),
        parents: [
          t.git(['rev-parse', 'feature^']).trim(),
        ],
        authorName: 'Test User',
        authorEmail: 'test@example.com',
        authorTime: 0,
        subject: 'theirs',
      );
      await expectLater(t.repo.cherryPick(picked), throwsA(anything));
      final sides = await t.repo.conflictSides(RepoOperation.cherryPick);
      expect(sides.current, 'main');
      expect(sides.incoming, sha);
      expect(sides.incomingDetail, '$sha theirs');
      expect(sides.description, 'Cherry-picking $sha theirs onto main');
    });

    test('rebase sides: onto and the commit being replayed', () async {
      t.git(['checkout', '-q', 'feature']);
      await expectLater(t.repo.rebase('main'), throwsA(anything));
      final sides = await t.repo.conflictSides(RepoOperation.rebase);
      expect(sides.current, 'main');
      expect(sides.incoming, 'feature');
      expect(sides.incomingDetail, endsWith(' theirs'));
      expect(sides.description, 'Rebasing feature onto main');
    });
  });
}
