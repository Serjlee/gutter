import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/git/rebase_plan.dart';

void main() {
  List<RebaseStep> steps() => [
    for (final n in ['a', 'b', 'c', 'd'])
      RebaseStep(sha: n, subject: n, message: n),
  ];

  List<RebaseAction> actions(List<RebaseStep> s) => [
    for (final x in s) x.action,
  ];

  test('presetSquash folds consecutive commits into the oldest', () {
    final s = steps();
    expect(presetSquash(s, {'b', 'c', 'd'}), isTrue);
    expect(actions(s), [
      RebaseAction.pick,
      RebaseAction.pick,
      RebaseAction.squash,
      RebaseAction.squash,
    ]);
    // The plan squashes b, c and d into one commit.
    final groups = RebasePlan(s).groups();
    expect(groups.map((g) => g.head.sha), ['a', 'b']);
    expect(groups.last.defaultMessage(), 'b\n\nc\n\nd');
  });

  test('presetSquash refuses gaps, unknown commits and single commits', () {
    for (final shas in [
      {'a', 'c'},
      {'b', 'zzz'},
      {'c'},
    ]) {
      final s = steps();
      expect(presetSquash(s, shas), isFalse, reason: '$shas');
      expect(actions(s).toSet(), {RebaseAction.pick}, reason: '$shas');
    }
  });
}
