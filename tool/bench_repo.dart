// Times history loading for a real repository:
//   dart run tool/bench_repo.dart <repo> [maxCommits]
// ignore_for_file: avoid_print
import 'package:gutter/git/parsers/log_parser.dart';
import 'package:gutter/git/repository.dart';
import 'package:gutter/graph/graph_layout.dart';

Future<void> main(List<String> args) async {
  final repo = Repository(args.first);
  final max = args.length > 1 ? int.parse(args[1]) : 100000;
  for (var round = 0; round < 3; round++) {
    final sw = Stopwatch()..start();
    final bytes = await repo.logBytes(maxCount: max);
    final tLog = sw.elapsedMilliseconds;
    final commits = parseLog(bytes);
    final tParse = sw.elapsedMilliseconds - tLog;
    final layout = GraphLayout.compute(commits);
    final tLayout = sw.elapsedMilliseconds - tLog - tParse;
    final refs = await repo.refs();
    final status = await repo.status();
    final tRest = sw.elapsedMilliseconds - tLog - tParse - tLayout;
    print(
      'round $round: ${commits.length} commits '
      '(${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB), '
      'git log ${tLog}ms, parse ${tParse}ms, layout ${tLayout}ms '
      '(${layout.maxLanes} lanes), refs+status ${tRest}ms '
      '(${refs.length} refs, ${status.entries.length} changes)',
    );
  }
}
