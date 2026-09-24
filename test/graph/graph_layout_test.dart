import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gutter/git/models.dart';
import 'package:gutter/graph/graph_layout.dart';

import '../../tool/synthetic_history.dart';

Commit c(String sha, [List<String> parents = const []]) => Commit(
      sha: sha,
      parents: parents,
      authorName: 'a',
      authorEmail: 'a@a',
      authorTime: 0,
      subject: sha,
    );

List<List<int>> edgesOf(GraphLayout l, int r) => [
      for (var e = l.edgeOffsets[r]; e < l.edgeOffsets[r + 1]; e++)
        [l.edges[e * 4], l.edges[e * 4 + 1], l.edges[e * 4 + 3]],
    ];

/// Structural invariants: no line starts from nowhere or ends in nowhere.
void checkInvariants(List<Commit> commits, GraphLayout l) {
  final index = {for (var i = 0; i < commits.length; i++) commits[i].sha: i};
  for (var r = 0; r < l.rowCount; r++) {
    final out = edgesOf(l, r);
    for (final e in out) {
      final from = e[0], to = e[1];
      if (r > 0) {
        final incoming = edgesOf(l, r - 1).map((x) => x[1]).toSet();
        expect(from == l.nodeLane[r] || incoming.contains(from), isTrue,
            reason: 'row $r edge $e starts from nowhere');
      } else {
        expect(from, l.nodeLane[0]);
      }
      if (r + 1 < l.rowCount) {
        final nextFrom = edgesOf(l, r + 1).map((x) => x[0]).toSet();
        expect(to == l.nodeLane[r + 1] || nextFrom.contains(to), isTrue,
            reason: 'row $r edge $e ends in nowhere');
      }
    }
    // Every loaded parent is reachable: the node has an outgoing edge per
    // distinct parent lane.
    final hasLoadedParent =
        commits[r].parents.any((p) => index.containsKey(p));
    if (hasLoadedParent && r + 1 < l.rowCount) {
      expect(out.any((e) => e[0] == l.nodeLane[r]), isTrue,
          reason: 'row $r has parents but no edge out of its node');
    }
    // Nodes never share a lane with a pass-through line.
    final straight = out.where((e) => e[2] == EdgeKind.straight && e[0] != l.nodeLane[r]);
    if (r > 0) {
      final incomingNotNode = edgesOf(l, r - 1)
          .where((e) => e[1] == l.nodeLane[r])
          .toList();
      for (final s in straight) {
        expect(s[0] == l.nodeLane[r] && incomingNotNode.isEmpty, isFalse);
      }
    }
  }
}

void main() {
  test('linear history is a single lane', () {
    final commits = [c('d', ['c']), c('c', ['b']), c('b', ['a']), c('a')];
    final l = GraphLayout.compute(commits);
    expect(l.nodeLane, [0, 0, 0, 0]);
    expect(l.maxLanes, 1);
    expect(edgesOf(l, 0), [
      [0, 0, EdgeKind.straight]
    ]);
    expect(edgesOf(l, 3), isEmpty, reason: 'root commit has no parents');
    checkInvariants(commits, l);
  });

  test('merge opens a lane which converges at the fork point', () {
    final commits = [
      c('m', ['a', 'b']),
      c('a', ['base']),
      c('b', ['base']),
      c('base'),
    ];
    final l = GraphLayout.compute(commits);
    expect(l.nodeLane, [0, 0, 1, 0]);
    expect(edgesOf(l, 0), [
      [0, 0, EdgeKind.straight],
      [0, 1, EdgeKind.fromNode],
    ]);
    expect(edgesOf(l, 1), [
      [0, 0, EdgeKind.straight],
      [1, 1, EdgeKind.straight],
    ]);
    expect(edgesOf(l, 2), [
      [0, 0, EdgeKind.straight],
      [1, 0, EdgeKind.intoNode],
    ]);
    expect(l.nodeColor[0], l.nodeColor[1]);
    expect(l.nodeColor[2], isNot(l.nodeColor[0]));
    checkInvariants(commits, l);
  });

  test('two branch tips sharing a parent', () {
    final commits = [c('x', ['base']), c('y', ['base']), c('base')];
    final l = GraphLayout.compute(commits);
    expect(l.nodeLane, [0, 1, 0]);
    expect(edgesOf(l, 1), [
      [0, 0, EdgeKind.straight],
      [1, 0, EdgeKind.intoNode],
    ]);
    checkInvariants(commits, l);
  });

  test('merge whose second parent is the next row', () {
    final commits = [c('m', ['a', 'b']), c('b', ['a']), c('a')];
    final l = GraphLayout.compute(commits);
    expect(l.nodeLane, [0, 1, 0]);
    checkInvariants(commits, l);
  });

  test('octopus merge', () {
    final commits = [
      c('m', ['a', 'b', 'c']),
      c('c', ['base']),
      c('b', ['base']),
      c('a', ['base']),
      c('base'),
    ];
    final l = GraphLayout.compute(commits);
    expect(l.maxLanes, 3);
    expect(l.nodeLane[4], 0);
    checkInvariants(commits, l);
  });

  test('criss-cross merges', () {
    final commits = [
      c('m1', ['a2', 'b2']),
      c('m2', ['b2', 'a2']),
      c('a2', ['a1']),
      c('b2', ['b1']),
      c('a1', ['r']),
      c('b1', ['r']),
      c('r'),
    ];
    final l = GraphLayout.compute(commits);
    checkInvariants(commits, l);
  });

  test('truncated history: parents outside the loaded set', () {
    final commits = [c('b', ['a']), c('x', ['missing'])];
    final l = GraphLayout.compute(commits);
    expect(l.nodeLane, [0, 1]);
    checkInvariants(commits, l);
  });

  test('lanes are freed and reused', () {
    final commits = [
      c('m', ['a', 'f']),
      c('f', ['a']),
      c('a', ['x']),
      c('t', ['x']), // new tip after the side branch closed
      c('x'),
    ];
    final l = GraphLayout.compute(commits);
    expect(l.nodeLane[3], 1, reason: 'reuses the lane freed by f');
    expect(l.maxLanes, 2);
    checkInvariants(commits, l);
  });

  test('random histories satisfy invariants', () {
    for (var seed = 0; seed < 30; seed++) {
      final commits = syntheticHistory(400, Random(seed));
      final l = GraphLayout.compute(commits);
      expect(l.rowCount, commits.length);
      checkInvariants(commits, l);
    }
  });
}
