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
/// parents).
///
/// Most of a graph is vertical lines passing through rows, so those are
/// stored as runs (lane, color, first row, last row) with a block index for
/// fast lookup, while the few bends are stored per row. Memory is O(commits)
/// regardless of how wide the graph gets, and everything lives in flat
/// typed arrays that are cheap to move between isolates.
class GraphLayout {
  GraphLayout._({
    required this.nodeLane,
    required this.nodeColor,
    required this.edgeOffsets,
    required this.edges,
    required this.runs,
    required this.blockOffsets,
    required this.blockRuns,
    required this.maxLanes,
    required this.rowLanes,
  });

  static const blockShift = 6; // 64 rows per index block

  /// Set on the color of edges drawn dashed: the line from a pseudo-row
  /// (WIP, stash) to the commit it's based on. Mask it off with
  /// [colorMask] to get the color index.
  static const dashedBit = 1 << 24;
  static const colorMask = dashedBit - 1;

  /// Lane (column) of each row's node.
  final Int32List nodeLane;

  /// Color index of each row's node.
  final Int32List nodeColor;

  /// Bent edges between row r and r+1 are `edges[edgeOffsets[r]*4 ..
  /// edgeOffsets[r+1]*4]`, each as (fromLane, toLane, color, kind). Edge
  /// and run colors may carry [dashedBit].
  final Int32List edgeOffsets;
  final Int32List edges;

  /// Straight edges as runs of (lane, color, firstRow, lastRow): the lane has
  /// a vertical line from row r to r+1 for every r in [firstRow, lastRow].
  final Int32List runs;

  /// Runs intersecting block b are `blockRuns[blockOffsets[b] ..
  /// blockOffsets[b+1]]` (indexes into [runs] / 4).
  final Int32List blockOffsets;
  final Int32List blockRuns;

  /// Widest row (number of lanes).
  final int maxLanes;

  /// Number of lanes in use at each row.
  final Int32List rowLanes;

  int get rowCount => nodeLane.length;

  static final empty = GraphLayout._(
    nodeLane: Int32List(0),
    nodeColor: Int32List(0),
    edgeOffsets: Int32List(1),
    edges: Int32List(0),
    runs: Int32List(0),
    blockOffsets: Int32List(1),
    blockRuns: Int32List(0),
    maxLanes: 0,
    rowLanes: Int32List(0),
  );

  /// Calls [f] for every straight edge from row [r] to row r+1.
  void forEachStraight(int r, void Function(int lane, int color) f) {
    if (r < 0 || r >= rowCount) return;
    final b = r >> blockShift;
    for (var i = blockOffsets[b]; i < blockOffsets[b + 1]; i++) {
      final k = blockRuns[i] * 4;
      if (runs[k + 2] <= r && r <= runs[k + 3]) f(runs[k], runs[k + 1]);
    }
  }

  /// All edges from row [r] to r+1 as (from, to, color, kind); for tests
  /// and debugging (painting uses the direct accessors).
  List<List<int>> edgesAt(int r) {
    final out = <List<int>>[];
    forEachStraight(r, (lane, color) {
      out.add([lane, lane, color, EdgeKind.straight]);
    });
    for (var e = edgeOffsets[r]; e < edgeOffsets[r + 1]; e++) {
      out.add([
        edges[e * 4],
        edges[e * 4 + 1],
        edges[e * 4 + 2],
        edges[e * 4 + 3],
      ]);
    }
    return out;
  }

  static GraphLayout compute(List<Commit> commits) => computeFromParents(
    commits.length,
    (i) => commits[i].sha,
    (i) => commits[i].parents,
  );

  /// Lays out [n] rows. Rows where [isDashed] holds are pseudo-commits
  /// (WIP, stashes): the line to their first parent is dashed and never
  /// takes over a branch's lane.
  static GraphLayout computeFromParents(
    int n,
    String Function(int) shaOf,
    List<String> Function(int) parentsOf, {
    bool Function(int)? isDashed,
  }) {
    final nodeLane = Int32List(n);
    final nodeColor = Int32List(n);
    final rowLanes = Int32List(n);
    final edgeOffsets = Int32List(n + 1);
    final edges = _IntBuffer(64);
    final runs = _IntBuffer(n * 4 + 16);

    // Per lane: the commit it leads to, its color and its open run.
    final lanes = <String?>[];
    final laneColor = <int>[];
    final laneDashed = <bool>[];
    final runStart = <int>[]; // -1: no open run
    // Commit sha -> lanes expecting it (usually one).
    final expect = <String, List<int>>{};
    var nextColor = 0;
    var maxLanes = 0;

    int colorOf(int lane) =>
        laneDashed[lane] ? laneColor[lane] | dashedBit : laneColor[lane];

    void closeRun(int lane, int lastRow) {
      final s = runStart[lane];
      if (s >= 0 && lastRow >= s) {
        runs.add4(lane, colorOf(lane), s, lastRow);
      }
      runStart[lane] = -1;
    }

    void setLane(int lane, String? target) {
      final old = lanes[lane];
      if (old != null) {
        final l = expect[old]!;
        l.remove(lane);
        if (l.isEmpty) expect.remove(old);
      }
      lanes[lane] = target;
      if (target != null) (expect[target] ??= <int>[]).add(lane);
    }

    int freeSlot() {
      final i = lanes.indexOf(null);
      if (i >= 0) {
        laneDashed[i] = false;
        return i;
      }
      lanes.add(null);
      laneColor.add(0);
      laneDashed.add(false);
      runStart.add(-1);
      return lanes.length - 1;
    }

    // The lane a commit is placed in: the leftmost of the lanes leading to
    // it, preferring real branch lanes over dashed pseudo-commit lines.
    int leftmost(List<int> ls) {
      var m = -1;
      for (final l in ls) {
        if (laneDashed[l]) continue;
        if (m < 0 || l < m) m = l;
      }
      if (m >= 0) return m;
      m = ls.first;
      for (final l in ls) {
        if (l < m) m = l;
      }
      return m;
    }

    final newLanes = <int>[];
    final mergeTargets = <int>[];

    for (var r = 0; r < n; r++) {
      final sha = shaOf(r);
      edgeOffsets[r] = edges.length >> 2;

      // 1. Place the node: leftmost lane expecting it; others converge (their
      //    runs were closed while drawing the bend on the row above).
      var col = -1;
      final waiting = expect[sha];
      if (waiting != null) {
        col = leftmost(waiting);
        for (final l in List<int>.of(waiting)) {
          if (l != col) setLane(l, null);
        }
      }
      int color;
      if (col < 0) {
        col = freeSlot();
        color = nextColor++;
        laneColor[col] = color;
      } else {
        color = laneColor[col];
        if (laneDashed[col]) {
          // Only dashed lines lead here: they end at this node and the lane
          // continues solid below it.
          closeRun(col, r - 1);
          laneDashed[col] = false;
        }
      }
      nodeLane[r] = col;
      nodeColor[r] = color;

      // 2. Parents.
      final parents = parentsOf(r);
      newLanes.clear();
      mergeTargets.clear();
      if (parents.isEmpty) {
        closeRun(col, r - 1);
        setLane(col, null);
      } else {
        // The node's lane continues to the first parent, keeping its run.
        setLane(col, parents[0]);
        if (isDashed != null && isDashed(r)) {
          closeRun(col, r - 1);
          laneDashed[col] = true;
        }
        if (runStart[col] < 0) runStart[col] = r;
        for (var pi = 1; pi < parents.length; pi++) {
          final p = parents[pi];
          final existing = expect[p];
          int k;
          if (existing == null) {
            k = freeSlot();
            setLane(k, p);
            laneColor[k] = nextColor++;
            runStart[k] = r + 1; // row r has the bend out of the node
            newLanes.add(k);
          } else {
            k = leftmost(existing);
          }
          if (k != col && !mergeTargets.contains(k)) mergeTargets.add(k);
        }
      }

      // 3. Bends towards the next row.
      final nextSha = r + 1 < n ? shaOf(r + 1) : null;
      var nextCol = -1;
      final nextWaiting = nextSha == null ? null : expect[nextSha];
      if (nextWaiting != null) {
        nextCol = leftmost(nextWaiting);
        for (final l in nextWaiting) {
          if (l == nextCol || newLanes.contains(l)) continue;
          // Lane l converges into the next node: its straight run ends here.
          closeRun(l, r - 1);
          edges.add4(l, nextCol, colorOf(l), EdgeKind.intoNode);
        }
      }
      for (final k in mergeTargets) {
        final to = (lanes[k] == nextSha && k != nextCol) ? nextCol : k;
        edges.add4(col, to, laneColor[k], EdgeKind.fromNode);
      }

      // 4. Trim trailing empty lanes.
      while (lanes.isNotEmpty && lanes.last == null) {
        lanes.removeLast();
        laneColor.removeLast();
        laneDashed.removeLast();
        runStart.removeLast();
      }
      if (lanes.length > maxLanes) maxLanes = lanes.length;
      rowLanes[r] = lanes.length > col + 1 ? lanes.length : col + 1;
    }
    edgeOffsets[n] = edges.length >> 2;
    // Lines to parents that were not loaded run off the bottom.
    for (var l = 0; l < lanes.length; l++) {
      closeRun(l, n - 1);
    }

    // Block index over the runs.
    final runData = runs.toList();
    final runCount = runData.length >> 2;
    final blocks = n == 0 ? 0 : ((n - 1) >> blockShift) + 1;
    final blockOffsets = Int32List(blocks + 1);
    for (var i = 0; i < runCount; i++) {
      final a = runData[i * 4 + 2] >> blockShift;
      final b = runData[i * 4 + 3] >> blockShift;
      for (var k = a; k <= b; k++) {
        blockOffsets[k + 1]++;
      }
    }
    for (var k = 0; k < blocks; k++) {
      blockOffsets[k + 1] += blockOffsets[k];
    }
    final blockRuns = Int32List(blockOffsets[blocks]);
    final fill = Int32List.fromList(blockOffsets);
    for (var i = 0; i < runCount; i++) {
      final a = runData[i * 4 + 2] >> blockShift;
      final b = runData[i * 4 + 3] >> blockShift;
      for (var k = a; k <= b; k++) {
        blockRuns[fill[k]++] = i;
      }
    }

    return GraphLayout._(
      nodeLane: nodeLane,
      nodeColor: nodeColor,
      edgeOffsets: edgeOffsets,
      edges: edges.toList(),
      runs: runData,
      blockOffsets: blockOffsets,
      blockRuns: blockRuns,
      maxLanes: maxLanes,
      rowLanes: rowLanes,
    );
  }
}

/// Growable Int32 buffer.
class _IntBuffer {
  _IntBuffer(int capacity) : _data = Int32List(capacity < 16 ? 16 : capacity);

  Int32List _data;
  int length = 0;

  void add4(int a, int b, int c, int d) {
    if (length + 4 > _data.length) {
      final grown = Int32List(_data.length * 2);
      grown.setRange(0, length, _data);
      _data = grown;
    }
    _data[length++] = a;
    _data[length++] = b;
    _data[length++] = c;
    _data[length++] = d;
  }

  Int32List toList() =>
      Int32List.fromList(Int32List.sublistView(_data, 0, length));
}
