// Benchmarks graph layout: `dart run tool/bench_layout.dart [count]`.
// ignore_for_file: avoid_print
import 'dart:math';

import 'package:gutter/graph/graph_layout.dart';

import 'synthetic_history.dart';

void main(List<String> args) {
  final count = args.isEmpty ? 200000 : int.parse(args.first);
  final commits = syntheticHistory(count, Random(42));
  // Warm up the JIT.
  GraphLayout.compute(commits.sublist(0, min(20000, commits.length)));
  final sw = Stopwatch()..start();
  final layout = GraphLayout.compute(commits);
  sw.stop();
  print(
    'layout of $count commits: ${sw.elapsedMilliseconds} ms, '
    'max lanes ${layout.maxLanes}, edges ${layout.edges.length ~/ 4}',
  );
}
