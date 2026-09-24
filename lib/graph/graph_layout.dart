import 'dart:typed_data';

import '../git/models.dart';

/// How an edge between two consecutive rows is drawn.
abstract final class EdgeKind {
  /// Vertical line in one lane.
  static const straight = 0;

  /// Leaves the node of the upper row and bends into another lane
  /// (merge parent / branch start).
  static const fromNode = 1;

  /// Comes down another lane and bends into the node of the lower row
  /// (branches converging on their fork point).
  static const intoNode = 2;
}

/// Lane assignment for a list of commits in display order (children before
/// parents). Data is kept in flat typed arrays so layouts of hundreds of
/// thousands of commits stay compact and cheap to send across isolates.
class GraphLayout {
  GraphLayout._({
    required this.nodeLane,
    required this.nodeColor,
    required this.edgeOffsets,
    required this.edges,
    required this.maxLanes,
    required this.rowLanes,
  });

  /// Lane (column) of each row's node.
  final Int32List nodeLane;

  /// Color index of each row's node.
  final Int32List nodeColor;

  /// Edges between row r and r+1 are `edges[edgeOffsets[r]*4 ..
  /// edgeOffsets[r+1]*4]`, each as (fromLane, toLane, color, kind).
  final Int32List edgeOffsets;
  final Int32List edges;

  /// Widest row (number of lanes).
  final int maxLanes;

  /// Number of lanes in use at each row (for sizing the message column).
  final Int32List rowLanes;

  int get rowCount => nodeLane.length;

  static final empty = GraphLayout._(
    nodeLane: Int32List(0),
    nodeColor: Int32List(0),
    edgeOffsets: Int32List(1),
    edges: Int32List(0),
    maxLanes: 0,
    rowLanes: Int32List(0),
  );

  /// Number of edges leaving row [r] towards row r+1.
  int edgeCount(int r) => edgeOffsets[r + 1] - edgeOffsets[r];

  static GraphLayout compute(List<Commit> commits) =>
      computeFromParents(commits.length, (i) => commits[i].sha,
          (i) => commits[i].parents);

  static GraphLayout computeFromParents(
    int n,
    String Function(int) shaOf,
    List<String> Function(int) parentsOf,
  ) {
    final nodeLane = Int32List(n);
    final nodeColor = Int32List(n);
    final rowLanes = Int32List(n);
    final edgeOffsets = Int32List(n + 1);
    var edges = Int32List(n * 8 + 16);
    var edgeLen = 0;

    void addEdge(int from, int to, int color, int kind) {
      if (edgeLen + 4 > edges.length) {
        final grown = Int32List(edges.length * 2);
        grown.setRange(0, edgeLen, edges);
        edges = grown;
      }
      edges[edgeLen++] = from;
      edges[edgeLen++] = to;
      edges[edgeLen++] = color;
      edges[edgeLen++] = kind;
    }

    final lanes = <String?>[];
    final laneColor = <int>[];
    var nextColor = 0;
    var maxLanes = 0;

    int freeSlot() {
      final i = lanes.indexOf(null);
      if (i >= 0) return i;
      lanes.add(null);
      laneColor.add(0);
      return lanes.length - 1;
    }

    // Scratch per row: lanes created for merge parents at this row, and all
    // lanes that receive an edge out of this row's node.
    final newLanes = <int>{};
    final mergeTargets = <int>[];

    for (var r = 0; r < n; r++) {
      final sha = shaOf(r);
      // Lanes expecting this commit.
      var col = -1;
      for (var i = 0; i < lanes.length; i++) {
        if (lanes[i] == sha) {
          if (col < 0) {
            col = i;
          } else {
            lanes[i] = null; // converged into col at this row
          }
        }
      }
      int color;
      if (col < 0) {
        col = freeSlot();
        color = nextColor++;
        laneColor[col] = color;
      } else {
        color = laneColor[col];
      }
      nodeLane[r] = col;
      nodeColor[r] = color;

      final parents = parentsOf(r);
      newLanes.clear();
      mergeTargets.clear();
      if (parents.isEmpty) {
        lanes[col] = null;
      } else {
        lanes[col] = parents[0];
        for (var pi = 1; pi < parents.length; pi++) {
          final p = parents[pi];
          var k = lanes.indexOf(p);
          if (k < 0) {
            k = freeSlot();
            lanes[k] = p;
            laneColor[k] = nextColor++;
            newLanes.add(k);
          }
          if (k != col && !mergeTargets.contains(k)) mergeTargets.add(k);
        }
      }

      // Trim trailing empty lanes.
      while (lanes.isNotEmpty && lanes.last == null) {
        lanes.removeLast();
        laneColor.removeLast();
      }
      if (lanes.length > maxLanes) maxLanes = lanes.length;
      rowLanes[r] = lanes.length > col + 1 ? lanes.length : col + 1;

      // Edges from this row to the next.
      edgeOffsets[r] = edgeLen >> 2;

      // For the last row this still emits lines for parents that were not
      // loaded, so they run off the bottom of the graph.
      {
        final nextSha = r + 1 < n ? shaOf(r + 1) : null;
        // The next node goes to the leftmost lane expecting it.
        final nextCol = nextSha == null ? -1 : lanes.indexOf(nextSha);
        for (var i = 0; i < lanes.length; i++) {
          final target = lanes[i];
          if (target == null || newLanes.contains(i)) continue;
          if (target == nextSha && i != nextCol) {
            addEdge(i, nextCol, laneColor[i], EdgeKind.intoNode);
          } else {
            addEdge(i, i, laneColor[i], EdgeKind.straight);
          }
        }
        for (final k in mergeTargets) {
          final target = lanes[k];
          final to = (target == nextSha && k != nextCol) ? nextCol : k;
          addEdge(col, to, laneColor[k], EdgeKind.fromNode);
        }
      }
    }
    edgeOffsets[n] = edgeLen >> 2;

    return GraphLayout._(
      nodeLane: nodeLane,
      nodeColor: nodeColor,
      edgeOffsets: edgeOffsets,
      edges: Int32List.fromList(edges.sublist(0, edgeLen)),
      maxLanes: maxLanes,
      rowLanes: rowLanes,
    );
  }
}
