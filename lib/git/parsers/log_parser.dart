import 'dart:convert';
import 'dart:typed_data';

import '../models.dart';

/// Format passed to `git log --format=` producing NUL separated fields.
/// Records are terminated by `-z` (another NUL), so each commit is exactly
/// [logFieldCount] fields.
const logFormat = '%H%x00%P%x00%an%x00%ae%x00%at%x00%s';
const logFieldCount = 6;

/// Parses output of `git log -z --format=[logFormat]`.
List<Commit> parseLog(Uint8List bytes) {
  final text = utf8.decode(bytes, allowMalformed: true);
  return parseLogString(text);
}

List<Commit> parseLogString(String text) {
  final commits = <Commit>[];
  if (text.isEmpty) return commits;
  final fields = text.split('\x00');
  // -z terminates each record with NUL; last element is then empty.
  var i = 0;
  while (i + logFieldCount <= fields.length) {
    var sha = fields[i];
    // Records after the first may be preceded by a newline in some git
    // versions; be lenient.
    if (sha.startsWith('\n')) sha = sha.substring(1);
    if (sha.isEmpty) {
      i++;
      continue;
    }
    final parents = fields[i + 1];
    commits.add(
      Commit(
        sha: sha,
        parents: parents.isEmpty ? const [] : parents.split(' '),
        authorName: fields[i + 2],
        authorEmail: fields[i + 3],
        authorTime: int.tryParse(fields[i + 4]) ?? 0,
        subject: fields[i + 5],
      ),
    );
    i += logFieldCount;
  }
  return commits;
}

const detailsFormat =
    '%H%x00%P%x00%an%x00%ae%x00%at%x00%cn%x00%ce%x00%ct%x00%B';

CommitDetails parseCommitDetails(String text) {
  final f = text.split('\x00');
  if (f.length < 9) {
    throw FormatException('Unexpected commit details output', text);
  }
  return CommitDetails(
    sha: f[0].trim(),
    parents: f[1].isEmpty ? const [] : f[1].split(' '),
    authorName: f[2],
    authorEmail: f[3],
    authorTime: int.tryParse(f[4]) ?? 0,
    committerName: f[5],
    committerEmail: f[6],
    committerTime: int.tryParse(f[7]) ?? 0,
    message: f.sublist(8).join('\x00').trimRight(),
  );
}
