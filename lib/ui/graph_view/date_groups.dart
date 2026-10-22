import '../../git/models.dart';

/// How old a commit is, in the steps the graph marks with separators.
enum DateGroup {
  today('Today'),
  yesterday('Yesterday'),
  lastWeek('Last week'),
  lastMonth('Last month'),
  lastYear('Last year'),
  older('Older');

  const DateGroup(this.label);
  final String label;

  /// The group of [date], by calendar days before [now].
  static DateGroup of(DateTime date, DateTime now) {
    DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
    // Rounded: a day across a DST change is 23 or 25 hours.
    final days = (day(now).difference(day(date)).inHours / 24).round();
    if (days <= 0) return today;
    if (days == 1) return yesterday;
    if (days < 7) return lastWeek;
    if (days < 31) return lastMonth;
    if (days < 366) return lastYear;
    return older;
  }
}

/// The rows that end a [DateGroup] in [commits] (the graph's rows; null for
/// the WIP row), mapped to that group: a separator goes under each.
///
/// Commits are grouped by commit date, which the graph is sorted by, so the
/// groups follow the rows. A commit out of order (a clock off, a parent
/// newer than its child) stays in the group above. Stashes ([isStash]) sit
/// with the commit they were made on and are skipped.
Map<int, DateGroup> dateSeparators(
  List<Commit?> commits,
  DateTime now, {
  bool Function(int row)? isStash,
}) {
  final out = <int, DateGroup>{};
  DateGroup? current;
  int? last; // the last commit row in [current]
  for (var row = 0; row < commits.length; row++) {
    final c = commits[row];
    if (c == null || (isStash?.call(row) ?? false)) continue;
    final g = DateGroup.of(c.commitDate, now);
    if (current != null && g.index > current.index) out[last!] = current;
    if (current == null || g.index > current.index) current = g;
    last = row;
  }
  return out;
}
