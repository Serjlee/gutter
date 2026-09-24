import 'dart:math';

import 'package:gutter/git/models.dart';

/// Generates a plausible branchy history of [count] commits in display order
/// (children before parents), for tests and benchmarks.
List<Commit> syntheticHistory(int count, Random rnd) {
  final created = <Commit>[];
  final heads = <String>[];
  var id = 0;
  String next() => (id++).toRadixString(16).padLeft(40, '0');

  Commit make(List<String> parents) {
    final c = Commit(
      sha: next(),
      parents: parents,
      authorName: 'Dev ${rnd.nextInt(20)}',
      authorEmail: 'dev@example.com',
      authorTime: 1600000000 + created.length * 60,
      subject: 'commit ${created.length}',
    );
    created.add(c);
    return c;
  }

  heads.add(make(const []).sha);
  while (created.length < count) {
    final roll = rnd.nextDouble();
    if (roll < 0.08 && heads.length < 12) {
      // New branch off a recent commit.
      final from = created[max(0, created.length - 1 - rnd.nextInt(20))].sha;
      heads.add(make([from]).sha);
    } else if (roll < 0.14 && heads.length > 1) {
      // Merge a random branch into the main line.
      final i = 1 + rnd.nextInt(heads.length - 1);
      final m = make([heads[0], heads[i]]);
      heads[0] = m.sha;
      if (rnd.nextBool()) {
        heads.removeAt(i);
      }
    } else {
      final i = rnd.nextInt(heads.length);
      heads[i] = make([heads[i]]).sha;
    }
  }
  return created.reversed.toList();
}
