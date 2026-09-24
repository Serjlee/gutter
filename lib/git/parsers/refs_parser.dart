import '../models.dart';

const refsFormat = '%(refname)%00%(objectname)%00%(*objectname)%00'
    '%(upstream)%00%(upstream:track,nobracket)%00%(HEAD)%00%(contents:subject)';

/// Parses `git for-each-ref --format=[refsFormat]` output.
List<GitRef> parseRefs(String text) {
  final refs = <GitRef>[];
  for (final line in text.split('\n')) {
    if (line.isEmpty) continue;
    final f = line.split('\x00');
    if (f.length < 7) continue;
    final peeled = f[2];
    final track = f[4];
    var ahead = 0, behind = 0;
    final am = RegExp(r'ahead (\d+)').firstMatch(track);
    final bm = RegExp(r'behind (\d+)').firstMatch(track);
    if (am != null) ahead = int.parse(am.group(1)!);
    if (bm != null) behind = int.parse(bm.group(1)!);
    refs.add(GitRef(
      fullName: f[0],
      sha: peeled.isNotEmpty ? peeled : f[1],
      upstream: f[3].isEmpty ? null : f[3],
      ahead: ahead,
      behind: behind,
      upstreamGone: track == 'gone',
      isHead: f[5] == '*',
      subject: f[6],
    ));
  }
  return refs;
}
