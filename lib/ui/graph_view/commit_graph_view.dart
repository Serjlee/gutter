import 'dart:async';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../git/models.dart';
import '../../git/rebase_plan.dart';
import '../../graph/graph_layout.dart';
import '../../graph/graph_painter.dart';
import '../dialogs/interactive_rebase_dialog.dart' show rebaseActionColor;
import '../repo/repo_actions.dart';
import '../repo/repo_tab_controller.dart';
import '../widgets/common.dart';
import 'date_groups.dart';
import 'scroll_marks.dart';

const _metrics = GraphMetrics();

/// Room the ref labels get in a compact graph, past its lanes.
const _labelRoom = 160.0;

/// The gap under the last row of a [DateGroup], holding its separator.
const _gap = 22.0;

/// Column widths (message column takes the remaining space).
class GraphColumns {
  GraphColumns(Map<String, double> saved)
    : refs = saved['refs'] ?? 190,
      graph = saved['graph'],
      author = saved['author'] ?? 140,
      // A new key: widths saved under "date" were for the full timestamp.
      age = saved['age'] ?? 64,
      sha = saved['sha'] ?? 70;

  double refs;
  double? graph; // null: auto from lane count
  double author;
  double age;
  double sha;

  /// Ref labels go in the graph column, right of the lanes, instead of a
  /// column of their own.
  bool compact = false;

  double graphWidth(int lanes) =>
      (graph ?? _metrics.widthFor(max(1, min(lanes, 12)))) +
      (compact ? _labelRoom : 0);

  /// Decides which columns fit in [width], keeping at least [minMessage]
  /// pixels for the message: the sha goes first, then the ref column
  /// shrinks, the author goes, the ref column shrinks more, and the age
  /// goes last (it's narrow, and says the most at a glance).
  FittedColumns fit(double width, double graphW, {double minMessage = 200}) {
    var refsW = compact ? 0.0 : refs;
    var showSha = true, showAge = true, showAuthor = true;
    double spare() =>
        width -
        minMessage -
        refsW -
        graphW -
        (showAuthor ? author : 0) -
        (showAge ? age : 0) -
        (showSha ? sha : 0);
    void shrinkRefs(double to) {
      if (spare() < 0 && refsW > to) refsW = max(to, refsW + spare());
    }

    if (spare() < 0) showSha = false;
    shrinkRefs(110);
    if (spare() < 0) showAuthor = false;
    shrinkRefs(80);
    if (spare() < 0) showAge = false;
    shrinkRefs(70);
    return FittedColumns(
      refs: refsW,
      graph: graphW,
      author: showAuthor ? author : null,
      age: showAge ? age : null,
      sha: showSha ? sha : null,
    );
  }

  Map<String, double> toJson() => {
    'refs': refs,
    'graph': ?graph,
    'author': author,
    'age': age,
    'sha': sha,
  };
}

/// Column widths actually used for the current view width; null columns
/// are hidden.
class FittedColumns {
  const FittedColumns({
    required this.refs,
    required this.graph,
    this.author,
    this.age,
    this.sha,
  });
  final double refs;
  final double graph;
  final double? author;
  final double? age;
  final double? sha;
}

class CommitGraphView extends StatefulWidget {
  const CommitGraphView({super.key, required this.tab});
  final RepoTabController tab;

  @override
  State<CommitGraphView> createState() => _CommitGraphViewState();
}

class _CommitGraphViewState extends State<CommitGraphView> {
  final _scroll = ScrollController();
  final _focus = FocusNode(debugLabel: 'graph');
  late GraphColumns _cols = GraphColumns(widget.tab.app.settings.columnWidths);

  /// Ages go stale: the rows are redrawn each minute.
  Timer? _clock;

  /// [dateSeparators] of [_separatorsOf] on [_separatorsDay], and their
  /// rows in order.
  Map<int, DateGroup> _separators = const {};
  List<int> _gaps = const [];
  GraphData? _separatorsOf;
  DateTime? _separatorsDay;

  RepoTabController get tab => widget.tab;

  Map<int, DateGroup> _separatorsFor(GraphData graph) {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    if (!identical(graph, _separatorsOf) || day != _separatorsDay) {
      _separators = dateSeparators(
        [for (var row = 0; row < graph.rowCount; row++) graph.commitAt(row)],
        now,
        isStash: (row) => graph.stashAt(row) != null,
      );
      _gaps = _separators.keys.toList()..sort();
      _separatorsOf = graph;
      _separatorsDay = day;
    }
    return _separators;
  }

  @override
  void initState() {
    super.initState();
    tab.scrollToRow.addListener(_onScrollRequest);
    tab.app.avatars.addListener(_onAvatars);
    _scroll.addListener(_onScroll);
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    // Keys go to the graph when it shows up (a tab opening, a diff
    // closing), so the arrow keys work straight away; unless a text field
    // has them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final typing = FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<EditableText>();
      if (mounted && typing == null) _focus.requestFocus();
    });
  }

  void _onAvatars() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(CommitGraphView old) {
    super.didUpdateWidget(old);
    if (old.tab != widget.tab) {
      old.tab.scrollToRow.removeListener(_onScrollRequest);
      widget.tab.scrollToRow.addListener(_onScrollRequest);
      _cols = GraphColumns(widget.tab.app.settings.columnWidths);
    }
  }

  @override
  void dispose() {
    tab.scrollToRow.removeListener(_onScrollRequest);
    tab.app.avatars.removeListener(_onAvatars);
    _clock?.cancel();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onScroll() {
    final pos = _scroll.position;
    if (tab.graph.truncated &&
        !tab.loadingLog &&
        pos.pixels > pos.maxScrollExtent - 600) {
      unawaited(tab.loadMore());
    }
  }

  void _onScrollRequest() {
    final row = tab.scrollToRow.value;
    if (row == null || !_scroll.hasClients) return;
    tab.scrollToRow.value = null;
    final h = _metrics.rowHeight;
    final pos = _scroll.position;
    final top = row * h + lowerBound(_gaps, row) * _gap;
    final viewport = pos.viewportDimension;
    if (top < pos.pixels) {
      _scroll.jumpTo(top);
    } else if (top + h > pos.pixels + viewport) {
      _scroll.jumpTo(min(pos.maxScrollExtent, top + h - viewport + h * 2));
    }
  }

  void _saveColumns() {
    tab.app.settings.columnWidths = _cols.toJson();
    tab.app.save();
  }

  void _resize(void Function() f) {
    setState(f);
  }

  @override
  Widget build(BuildContext context) {
    final graph = tab.graph;
    final compact = tab.app.settings.compactGraph;
    _cols.compact = compact;
    final graphW = _cols.graphWidth(graph.layout.maxLanes);
    final actions = RepoActions(context, tab);
    final separators = _separatorsFor(graph);
    return Focus(
      focusNode: _focus,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final k = event.logicalKey;
        if (k == LogicalKeyboardKey.arrowDown) {
          tab.selectRelative(1);
        } else if (k == LogicalKeyboardKey.arrowUp) {
          tab.selectRelative(-1);
        } else if (k == LogicalKeyboardKey.pageDown) {
          tab.selectRelative(20);
        } else if (k == LogicalKeyboardKey.pageUp) {
          tab.selectRelative(-20);
        } else if (k == LogicalKeyboardKey.home) {
          tab.selectRelative(-1 << 30);
        } else if (k == LogicalKeyboardKey.end) {
          tab.selectRelative(1 << 30);
        } else {
          return KeyEventResult.ignored;
        }
        return KeyEventResult.handled;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fitted = _cols.fit(constraints.maxWidth, graphW);
          return Column(
            children: [
              _Header(
                cols: _cols,
                fitted: fitted,
                onCompact: () => tab.app.setCompactGraph(!compact),
                onResize: _resize,
                onResizeEnd: _saveColumns,
                onResetGraph: () {
                  setState(() => _cols.graph = null);
                  _saveColumns();
                },
              ),
              Expanded(
                child: graph.rowCount == 0
                    ? Center(
                        child: tab.loading || tab.loadingLog
                            ? const CircularProgressIndicator()
                            : Text(
                                'No commits yet',
                                style: TextStyle(color: AppColors.textDim),
                              ),
                      )
                    : Stack(
                        children: [
                          Positioned.fill(
                            child: ListView.builder(
                              key: PageStorageKey('graph-${tab.repo.path}'),
                              controller: _scroll,
                              itemExtentBuilder: (row, _) =>
                                  _metrics.rowHeight +
                                  (separators.containsKey(row) ? _gap : 0),
                              itemCount:
                                  graph.rowCount + (graph.truncated ? 1 : 0),
                              itemBuilder: (context, row) {
                                if (row >= graph.rowCount) {
                                  return Center(
                                    child: tab.loadingLog
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : TextButton(
                                            onPressed: tab.loadMore,
                                            child: const Text(
                                              'Load more commits',
                                            ),
                                          ),
                                  );
                                }
                                final key = ValueKey(
                                  graph.commitAt(row)?.sha ?? wipSha,
                                );
                                Widget build() => _GraphRow(
                                  tab: tab,
                                  row: row,
                                  cols: fitted,
                                  actions: actions,
                                  onFocus: () => _focus.requestFocus(),
                                  separator: separators[row],
                                );
                                // A rebase being planned: rows show its
                                // changes as they're made.
                                final session = tab.rebaseSession.value;
                                return session == null
                                    ? KeyedSubtree(key: key, child: build())
                                    : ListenableBuilder(
                                        key: key,
                                        listenable: session,
                                        builder: (_, _) => build(),
                                      );
                              },
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            bottom: 0,
                            width: 8,
                            child: ScrollMarks(
                              rowCount:
                                  graph.rowCount + (graph.truncated ? 1 : 0),
                              rowHeight: _metrics.rowHeight,
                              head: tab.headSha == null
                                  ? null
                                  : graph.rowOf(tab.headSha!),
                              headColor: AppColors.accent,
                              gaps: _gaps,
                              gapHeight: _gap,
                              trunk: [
                                for (final e in tab.refsBySha.entries)
                                  if (e.value.any(isTrunkRef))
                                    ?graph.rowOf(e.key),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.cols,
    required this.fitted,
    required this.onResize,
    required this.onResizeEnd,
    required this.onResetGraph,
    required this.onCompact,
  });

  final GraphColumns cols;
  final FittedColumns fitted;

  /// Moves the ref labels into the graph column, or back out.
  final VoidCallback onCompact;
  final void Function(void Function()) onResize;
  final VoidCallback onResizeEnd;
  final VoidCallback onResetGraph;

  Widget _title(String t, double? width, {bool expand = false}) {
    final style = TextStyle(
      fontSize: 11,
      letterSpacing: 0.5,
      fontWeight: FontWeight.w600,
      color: AppColors.textDim,
    );
    // A title that doesn't fit is left out rather than cut to "GR…".
    final text = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: LayoutBuilder(
        builder: (context, c) {
          final needed = (TextPainter(
            text: TextSpan(text: t, style: style),
            textDirection: TextDirection.ltr,
            textScaler: MediaQuery.textScalerOf(context),
          )..layout()).width;
          return needed > c.maxWidth
              ? const SizedBox.shrink()
              : Text(t, maxLines: 1, softWrap: false, style: style);
        },
      ),
    );
    if (expand) return Expanded(child: text);
    return SizedBox(width: width, child: text);
  }

  /// The first column's title, after the compact toggle; [title] wraps
  /// the title alone.
  Widget _first(String t, double width, {Widget Function(Widget)? title}) =>
      SizedBox(
        width: width,
        child: Row(
          children: [
            const SizedBox(width: 2),
            SmallIconButton(
              key: const ValueKey('compact-graph'),
              icon: cols.compact ? Icons.last_page : Icons.first_page,
              size: 14,
              tooltip: cols.compact
                  ? 'Branch and tag labels in their own column'
                  : 'Compact: branch and tag labels next to the graph',
              onPressed: onCompact,
            ),
            Expanded(
              child: (title ?? (w) => w)(_title(t, null, expand: false)),
            ),
          ],
        ),
      );

  Widget _handle(void Function(double) onDrag) => ResizeHandle(
    onDrag: (dx) => onResize(() => onDrag(dx)),
    onEnd: onResizeEnd,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      decoration: BoxDecoration(
        color: AppColors.panelAlt,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (!cols.compact) ...[
            _first('BRANCH / TAG', fitted.refs - 5),
            _handle((dx) => cols.refs = max(60, fitted.refs + dx)),
          ],
          // A double click resets its width (the toggle isn't part of it).
          if (cols.compact)
            _first(
              'GRAPH',
              fitted.graph - 5,
              title: (w) =>
                  GestureDetector(onDoubleTap: onResetGraph, child: w),
            )
          else
            GestureDetector(
              onDoubleTap: onResetGraph,
              child: _title('GRAPH', fitted.graph - 5),
            ),
          // (Compact, the labels' room comes on top of the lanes'.)
          _handle(
            (dx) => cols.graph = max(
              30,
              fitted.graph - (cols.compact ? _labelRoom : 0) + dx,
            ),
          ),
          _title('COMMIT MESSAGE', null, expand: true),
          if (fitted.author != null) ...[
            _handle((dx) => cols.author = max(40, cols.author - dx)),
            _title('AUTHOR', fitted.author! - 5),
          ],
          if (fitted.age != null) ...[
            _handle((dx) => cols.age = max(40, cols.age - dx)),
            _title('AGE', fitted.age! - 5),
          ],
          if (fitted.sha != null) ...[
            _handle((dx) => cols.sha = max(40, cols.sha - dx)),
            _title('SHA', fitted.sha! - 5),
          ],
        ],
      ),
    );
  }
}

/// What a rebase being planned does to a commit ("squash", "drop"), or
/// "onto" on the one it goes onto.
class _RebaseBadge extends StatelessWidget {
  const _RebaseBadge(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}

/// The gap under the last row of a [DateGroup]: a line, labeled with it.
class _DateSeparator extends StatelessWidget {
  const _DateSeparator(this.group, {required this.left});
  final DateGroup group;

  /// Where the message column starts: the line leaves the graph clear.
  final double left;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: _gap,
    child: Row(
      children: [
        SizedBox(width: left),
        Expanded(child: Container(height: 1, color: AppColors.border)),
        Container(
          key: ValueKey('date-separator-${group.name}'),
          height: 16,
          margin: const EdgeInsets.only(left: 8, right: 16),
          padding: const EdgeInsets.symmetric(horizontal: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.panelAlt,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            group.label,
            style: TextStyle(fontSize: 11, height: 1, color: AppColors.textDim),
          ),
        ),
      ],
    ),
  );
}

/// Where a row's ref labels start in a compact graph: past the lanes in use
/// at the row, so they never cover a line.
double _labelsX(GraphLayout layout, int row) {
  final lanes = max(
    layout.rowLanes[row],
    row > 0 ? layout.rowLanes[row - 1] : 0,
  );
  return _metrics.widthFor(max(1, lanes)) - 2;
}

class _GraphRow extends StatefulWidget {
  const _GraphRow({
    required this.tab,
    required this.row,
    required this.cols,
    required this.actions,
    required this.onFocus,
    this.separator,
  });

  final RepoTabController tab;
  final int row;
  final FittedColumns cols;
  final RepoActions actions;
  final VoidCallback onFocus;

  /// The group this row is the last of: a gap follows, with a separator.
  final DateGroup? separator;

  @override
  State<_GraphRow> createState() => _GraphRowState();
}

class _GraphRowState extends State<_GraphRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    final graph = tab.graph;
    final row = widget.row;
    final commit = graph.commitAt(row);
    final stash = graph.stashAt(row);
    final sha = commit?.sha ?? wipSha;
    final selected = tab.isSelected(sha);
    final laneColor = AppColors.lane(graph.layout.nodeColor[row]);
    final isHit = tab.searchHitSet.contains(row);
    final query = tab.search.trim().toLowerCase();
    final gap = widget.separator == null ? 0.0 : _gap;
    final compact = tab.app.settings.compactGraph;
    final dimmed = tab.search.trim().isNotEmpty && !isHit;

    final isCommit = commit != null && stash == null;
    final headRow = isCommit && sha == tab.headSha;
    // A rebase being planned: its commits, and the one they go onto.
    final session = tab.rebaseSession.value;
    final step = isCommit ? session?.stepOf(sha) : null;
    final rebaseBase = isCommit && session != null && sha == session.base;
    final dropped = step?.action == RebaseAction.drop;
    final trunkRow =
        isCommit && (tab.refsBySha[sha] ?? const <GitRef>[]).any(isTrunkRef);

    Color? bg;
    if (selected && tab.multiSelection.isNotEmpty) {
      // Several commits: one color, so they read as one selection.
      bg = AppColors.selection;
    } else if (selected) {
      // The commit's lane color; lighter on a light background, where it
      // shows more.
      bg = laneColor.withValues(alpha: AppColors.current.isDark ? 0.22 : 0.14);
    } else if (_hover) {
      bg = AppColors.hover;
    } else if (isHit) {
      bg = AppColors.warning.withValues(alpha: 0.10);
    } else if (step != null) {
      bg = AppColors.accent.withValues(alpha: 0.07);
    }

    final refs = commit == null || stash != null
        ? const <GitRef>[]
        : (tab.refsBySha[sha] ?? const <GitRef>[]);
    final msgColor = dimmed ? AppColors.textFaint : AppColors.text;
    final dimColor = dimmed ? AppColors.textFaint : AppColors.textDim;

    final content = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          widget.onFocus();
          tab.setDetailsOpen(true);
          // Shift: select a range; Ctrl/Cmd: add or remove this commit.
          final kb = HardwareKeyboard.instance;
          if (kb.isShiftPressed) {
            tab.selectRange(sha);
          } else if (kb.isControlPressed || kb.isMetaPressed) {
            tab.toggleSelect(sha);
          } else {
            unawaited(tab.select(sha));
          }
        },
        onSecondaryTapUp: commit == null
            ? null
            : (d) {
                if (tab.multiSelection.contains(sha)) {
                  unawaited(
                    showContextMenu(
                      context,
                      d.globalPosition,
                      widget.actions.multiCommitMenu(),
                    ),
                  );
                  return;
                }
                unawaited(tab.select(sha));
                unawaited(
                  showContextMenu(
                    context,
                    d.globalPosition,
                    stash != null
                        ? widget.actions.stashMenu(stash)
                        : widget.actions.commitMenu(commit),
                  ),
                );
              },
        child: Container(
          color: bg,
          // The checked-out commit: painted over, so the row doesn't shift.
          foregroundDecoration: headRow
              ? BoxDecoration(
                  border: Border(left: BorderSide(color: laneColor, width: 3)),
                )
              : null,
          child: Row(
            children: [
              if (!compact)
                SizedBox(
                  width: widget.cols.refs,
                  child: commit == null
                      ? const SizedBox()
                      : Opacity(
                          // Faded with the rest of a row search passes over.
                          opacity: dimmed ? 0.35 : 1,
                          child: _RefPills(
                            refs: refs,
                            laneColor: laneColor,
                            actions: widget.actions,
                            headSha: tab.headSha,
                            isHeadCommit: sha == tab.headSha,
                          ),
                        ),
                ),
              SizedBox(
                width: widget.cols.graph,
                height: _metrics.rowHeight,
                // Down through the gap under it, if any, so the lanes go on.
                child: Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.none,
                  children: [
                    OverflowBox(
                      alignment: Alignment.topCenter,
                      minHeight: _metrics.rowHeight + gap,
                      maxHeight: _metrics.rowHeight + gap,
                      child: ClipRect(
                        child: CustomPaint(
                          painter: GraphRowPainter(
                            layout: graph.layout,
                            row: row,
                            metrics: _metrics,
                            style: commit == null
                                ? NodeStyle.wip
                                : stash != null
                                ? NodeStyle.stash
                                : (commit.isMerge
                                      ? NodeStyle.merge
                                      : NodeStyle.commit),
                            initials: commit?.initials ?? '',
                            avatar: commit == null || stash != null
                                ? null
                                : tab.avatarFor(commit.authorEmail),
                            isHead: commit != null && sha == tab.headSha,
                            trunk: trunkRow,
                            dimmed: dimmed,
                            hint: tab.app.settings.lineHint,
                          ),
                        ),
                      ),
                    ),
                    if (compact && commit != null && refs.isNotEmpty)
                      Positioned(
                        left: _labelsX(graph.layout, row),
                        width: max(
                          0.0,
                          widget.cols.graph - _labelsX(graph.layout, row) - 4,
                        ),
                        top: 0,
                        height: _metrics.rowHeight,
                        child: Opacity(
                          opacity: dimmed ? 0.35 : 1,
                          child: _RefPills(
                            refs: refs,
                            laneColor: laneColor,
                            actions: widget.actions,
                            headSha: tab.headSha,
                            isHeadCommit: sha == tab.headSha,
                            overGraph: true,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: commit == null
                      ? _WipSummary(tab: tab)
                      : Row(
                          children: [
                            if (step != null &&
                                step.action != RebaseAction.pick)
                              _RebaseBadge(
                                step.action.label.toLowerCase(),
                                rebaseActionColor(step.action),
                              ),
                            if (rebaseBase)
                              _RebaseBadge('onto', AppColors.accent),
                            Expanded(
                              child: Text.rich(
                                _marked(commit.subject, isHit ? query : ''),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: stash != null || dropped
                                      ? dimColor
                                      : msgColor,
                                  fontStyle: stash != null
                                      ? FontStyle.italic
                                      : null,
                                  fontWeight: headRow ? FontWeight.w700 : null,
                                  decoration: dropped
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              if (widget.cols.author != null)
                _cell(
                  commit?.authorName ?? '',
                  widget.cols.author!,
                  dimColor,
                  query: isHit ? query : '',
                ),
              if (widget.cols.age != null)
                commit == null
                    ? SizedBox(width: widget.cols.age)
                    : Tooltip(
                        message: _dates(commit),
                        waitDuration: const Duration(milliseconds: 500),
                        child: _cell(
                          shortAge(commit.date),
                          widget.cols.age!,
                          dimColor,
                        ),
                      ),
              if (widget.cols.sha != null)
                SizedBox(
                  width: widget.cols.sha,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text.rich(
                      _marked(
                        commit?.shortSha ?? '',
                        isHit && (commit?.sha.startsWith(query) ?? false)
                            ? query
                            : '',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: monoStyle(size: 12, color: dimColor),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    final group = widget.separator;
    if (group == null) return content;
    return Column(
      children: [
        SizedBox(height: _metrics.rowHeight, child: content),
        _DateSeparator(group, left: widget.cols.refs + widget.cols.graph),
      ],
    );
  }

  /// The full timestamp; both, when it was committed later than authored
  /// (rebased, cherry-picked).
  static String _dates(Commit c) => c.commitTime - c.authorTime < 60
      ? formatDateTime(c.date)
      : 'Authored ${formatDateTime(c.date)}\n'
            'Committed ${formatDateTime(c.commitDate)}';

  /// [text] with each occurrence of [query] (ignoring case) marked.
  static TextSpan _marked(String text, String query) {
    final lower = text.toLowerCase();
    // (Lowercasing may change lengths, as for "İ": then nothing's marked.)
    if (query.isEmpty || lower.length != text.length) {
      return TextSpan(text: text);
    }
    final mark = TextStyle(
      backgroundColor: AppColors.warning.withValues(alpha: 0.35),
    );
    final spans = <TextSpan>[];
    var at = 0;
    for (var i = lower.indexOf(query); i >= 0; i = lower.indexOf(query, at)) {
      if (i > at) spans.add(TextSpan(text: text.substring(at, i)));
      at = i + query.length;
      spans.add(TextSpan(text: text.substring(i, at), style: mark));
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return TextSpan(children: spans);
  }

  Widget _cell(String text, double width, Color color, {String query = ''}) =>
      SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text.rich(
            _marked(text, query),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: color),
          ),
        ),
      );
}

class _WipSummary extends StatelessWidget {
  const _WipSummary({required this.tab});
  final RepoTabController tab;

  @override
  Widget build(BuildContext context) {
    final s = tab.status;
    final modified = s.entries
        .where(
          (e) =>
              !e.isUntracked &&
              e.worktree != ChangeKind.deleted &&
              e.index != ChangeKind.deleted &&
              !e.conflicted,
        )
        .length;
    final added = s.entries
        .where((e) => e.isUntracked || e.index == ChangeKind.added)
        .length;
    final deleted = s.entries
        .where(
          (e) =>
              e.worktree == ChangeKind.deleted || e.index == ChangeKind.deleted,
        )
        .length;
    final conflicts = s.conflicted.length;
    final draft = tab.commitMessage.text.split('\n').first.trim();
    Widget stat(IconData icon, int n, Color c) => n == 0
        ? const SizedBox()
        : Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 13, color: c),
                const SizedBox(width: 3),
                Text('$n', style: TextStyle(fontSize: 12, color: c)),
              ],
            ),
          );
    return Row(
      children: [
        Flexible(
          child: Text(
            draft.isEmpty ? '// WIP' : draft,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: AppColors.textDim,
            ),
          ),
        ),
        stat(Icons.edit, modified, AppColors.warning),
        stat(Icons.add, added, AppColors.success),
        stat(Icons.remove, deleted, AppColors.danger),
        stat(Icons.warning_amber, conflicts, AppColors.danger),
      ],
    );
  }
}

/// A remote's main or master: always shown, and marked in the graph.
bool isTrunkRef(GitRef r) =>
    r.type == RefType.remoteBranch &&
    const {'main', 'master'}.contains(r.remoteBranchName);

/// A ref label group: local branch and its same-named remotes are merged
/// into one pill with icons, like GitKraken.
class _PillData {
  _PillData(this.label, this.type);
  final String label;
  final RefType type;
  GitRef? local;
  final remotes = <GitRef>[];
  GitRef? tag;
  bool get isHead => local?.isHead ?? false;
  GitRef get primary => local ?? tag ?? remotes.first;

  /// Has a remote's main or master: always shown, and stands out.
  bool get isTrunk => remotes.any(isTrunkRef);
}

class _RefPills extends StatelessWidget {
  const _RefPills({
    required this.refs,
    required this.laneColor,
    required this.actions,
    required this.headSha,
    required this.isHeadCommit,
    this.overGraph = false,
  });

  final List<GitRef> refs;
  final Color laneColor;
  final RepoActions actions;
  final String? headSha;
  final bool isHeadCommit;

  /// Drawn over the graph's lines (in a compact graph): opaque.
  final bool overGraph;

  List<_PillData> _group() {
    final pills = <String, _PillData>{};
    for (final r in refs) {
      switch (r.type) {
        case RefType.localBranch:
          (pills['b:${r.name}'] ??= _PillData(
            r.name,
            RefType.localBranch,
          )).local = r;
        case RefType.remoteBranch:
          final key = 'b:${r.remoteBranchName}';
          final hasLocal = refs.any(
            (x) =>
                x.type == RefType.localBranch && x.name == r.remoteBranchName,
          );
          if (hasLocal) {
            (pills[key] ??= _PillData(
              r.remoteBranchName,
              RefType.localBranch,
            )).remotes.add(r);
          } else {
            (pills['r:${r.name}'] ??= _PillData(
              r.name,
              RefType.remoteBranch,
            )).remotes.add(r);
          }
        case RefType.tag:
          (pills['t:${r.name}'] ??= _PillData(r.name, RefType.tag)).tag = r;
        default:
          break;
      }
    }
    final list = pills.values.toList();
    int rank(_PillData p) => p.isHead
        ? 0
        : p.isTrunk
        ? 1
        : switch (p.type) {
            RefType.localBranch => 2,
            RefType.remoteBranch => 3,
            _ => 4,
          };
    list.sort((a, b) => rank(a).compareTo(rank(b)));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final pills = _group();
    final detachedHead = isHeadCommit && !refs.any((r) => r.isHead);
    if (pills.isEmpty && !detachedHead) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: LayoutBuilder(
        builder: (context, c) {
          final fit = _fit(context, pills, c.maxWidth, detachedHead);
          final folded = pills.where((p) => !fit.shown.contains(p)).toList();
          return Row(
            children: [
              if (detachedHead)
                SizedBox(
                  width: fit.headWidth,
                  child: _pill(
                    context,
                    label: 'HEAD',
                    icon: Icons.adjust,
                    color: laneColor,
                    bold: true,
                  ),
                ),
              for (final (i, p) in fit.shown.indexed)
                Padding(
                  padding: EdgeInsets.only(
                    left: i == 0 && !detachedHead ? 0 : _gap,
                  ),
                  child: SizedBox(
                    width: fit.widths[i],
                    child: _pillFor(context, p, short: fit.short(p)),
                  ),
                ),
              if (fit.chip)
                Padding(
                  padding: EdgeInsets.only(
                    left: fit.shown.isEmpty && !detachedHead ? 0 : _gap,
                  ),
                  child: PopupMenuButton<VoidCallback>(
                    popUpAnimationStyle: AnimationStyle.noAnimation,
                    tooltip: folded.map((p) => p.label).join('\n'),
                    padding: EdgeInsets.zero,
                    itemBuilder: (_) => [
                      for (final p in folded)
                        PopupMenuItem<VoidCallback>(
                          enabled: false,
                          height: 30,
                          // Menus measure their items: no width-dependent
                          // layout in there.
                          child: _pillFor(context, p, fit: false),
                        ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.panelAlt,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        '+${folded.length}',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textDim,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static const _gap = 4.0;

  /// Shortened below this, a label isn't worth showing (about five
  /// characters and "…", its icons dropped).
  static const _minWidth = 64.0;

  /// Which labels show in [width], and how wide each is: as many as fit
  /// (in order: the checked-out branch, main/master, branches, remotes,
  /// tags), the widest shortened first, none below [_minWidth]. A tag and
  /// main/master stay when others fold into "+N".
  _Fit _fit(
    BuildContext context,
    List<_PillData> pills,
    double width,
    bool detachedHead,
  ) {
    final scaler = MediaQuery.textScalerOf(context);
    // Measured as drawn: in the app's text style (its font).
    final base = DefaultTextStyle.of(context).style;
    double text(String s, double size, {bool bold = false}) => (TextPainter(
      text: TextSpan(
        text: s,
        style: base.merge(
          TextStyle(
            fontSize: size,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout()).width;
    // A pill: text, its icons (15 each), padding and border, and a pixel to
    // spare for rounding.
    final measured = <(_PillData, bool), double>{};
    double natural(_PillData p, {required bool short}) =>
        measured[(p, short)] ??=
            text(_label(p, short: short), 11.5, bold: p.isHead) +
            _icons(p).length * 15 +
            12 +
            (p.isTrunk ? 3 : 2) +
            1;
    double plus(int n) => n == 0 ? 0 : _gap + text('+$n', 11) + 10 + 1;

    final headWidth = detachedHead
        ? min(width, text('HEAD', 11.5, bold: true) + 15 + 12 + 2 + 1)
        : 0.0;
    final room = width - headWidth;
    // A main/master remote after another label drops "origin/".
    bool short(_PillData p, List<_PillData> shown) =>
        p.isTrunk && (detachedHead || (shown.isNotEmpty && shown.first != p));

    final shown = [...pills];

    // Widths: the space left shared out, the narrowest labels first, so
    // only the widest ones are shortened.
    List<double> share(List<_PillData> shown, {bool chip = true}) {
      var space =
          room -
          (chip ? plus(pills.length - shown.length) : 0) -
          _gap * (shown.length - (detachedHead ? 0 : 1));
      final nat = [for (final p in shown) natural(p, short: short(p, shown))];
      final order = [for (var i = 0; i < shown.length; i++) i]
        ..sort((a, b) => nat[a].compareTo(nat[b]));
      final widths = List<double>.filled(shown.length, 0);
      for (final (k, i) in order.indexed) {
        final w = max(0.0, min(nat[i], space / (shown.length - k)));
        widths[i] = w;
        space -= w;
      }
      return widths;
    }

    // Shortened too much (one that's whole is fine, however short).
    bool squeezed(List<double> widths) => [
      for (final (i, w) in widths.indexed)
        w < min(_minWidth, natural(shown[i], short: short(shown[i], shown))),
    ].any((x) => x);

    var widths = share(shown);
    // Too narrow for them all: the last labels fold into "+N"; main/master
    // and a tag last (main/master first: its ring and scroll mark still
    // show it).
    while (shown.length > 1 && squeezed(widths)) {
      final tag = shown.where((p) => p.type == RefType.tag).firstOrNull;
      bool kept(_PillData p) => p == shown.first || p.isTrunk || p == tag;
      var i = shown.lastIndexWhere((p) => !kept(p));
      if (i < 0) i = shown.lastIndexWhere((p) => p != shown.first && p.isTrunk);
      shown.removeAt(i < 0 ? shown.length - 1 : i);
      widths = share(shown);
    }
    // No room for a label and "+N": just the label, or just "+N".
    var chip = shown.length < pills.length;
    if (chip && (widths.isEmpty || squeezed(widths))) {
      chip = false;
      widths = share(shown, chip: false);
    }
    if (widths.isEmpty || widths.first <= 0) {
      shown.clear();
      widths = [];
      chip = pills.isNotEmpty && room >= plus(pills.length);
    }
    return _Fit(shown, widths, headWidth, chip, (p) => short(p, shown));
  }

  /// [p]'s label; [short] drops "origin/" from a remote branch next to
  /// another pill (the cloud icon says it's remote).
  static String _label(_PillData p, {bool short = false}) =>
      short && p.local == null && p.remotes.first.remote == 'origin'
      ? p.remotes.first.remoteBranchName
      : p.label;

  static List<IconData> _icons(_PillData p) => [
    if (p.local != null) Icons.laptop_mac,
    if (p.remotes.isNotEmpty) Icons.cloud_outlined,
    if (p.tag != null) Icons.sell_outlined,
  ];

  Widget _pillFor(
    BuildContext context,
    _PillData p, {
    bool short = false,
    bool fit = true,
  }) {
    final icons = _icons(p);
    final color = p.type == RefType.tag ? AppColors.tag : laneColor;
    return GestureDetector(
      onDoubleTap: p.type == RefType.tag
          ? null
          : () => actions.checkoutRef(p.local ?? p.remotes.first),
      onSecondaryTapUp: (d) => showContextMenu(
        context,
        d.globalPosition,
        actions.refMenu(p.primary),
      ),
      child: Tooltip(
        message: [
          if (p.local != null) p.local!.name,
          ...p.remotes.map((r) => r.name),
          if (p.tag != null) 'tag ${p.tag!.name}',
          if (p.local?.upstream != null &&
              (p.local!.ahead > 0 || p.local!.behind > 0))
            '↑${p.local!.ahead} ↓${p.local!.behind}',
        ].join('\n'),
        child: _pill(
          context,
          label: _label(p, short: short),
          icons: icons,
          color: color,
          bold: p.isHead,
          outlined: p.isTrunk,
          fit: fit,
        ),
      ),
    );
  }

  /// A ref label. With [fit], icons that don't fit in the width it gets are
  /// dropped (last first) rather than overflowing, the name first keeping
  /// some room; it then can't be measured for intrinsic sizes (as menus
  /// do).
  Widget _pill(
    BuildContext context, {
    required String label,
    IconData? icon,
    List<IconData> icons = const [],
    required Color color,
    bool bold = false,
    bool outlined = false,
    bool fit = true,
  }) {
    final all = [?icon, ...icons];
    final style = TextStyle(
      fontSize: 11.5,
      color: AppColors.pillText,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
    );
    Widget content(int iconCount) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        for (final i in all.take(iconCount))
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(
              i,
              size: 11,
              color: AppColors.pillText.withValues(alpha: 0.7),
            ),
          ),
      ],
    );
    return Container(
      height: 21,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: overGraph
            ? Color.alphaBlend(
                color.withValues(alpha: bold ? 0.35 : 0.2),
                AppColors.background,
              )
            : color.withValues(alpha: bold ? 0.35 : 0.2),
        border: outlined
            ? Border.all(color: ScrollMarks.trunkColor, width: 1.5)
            : Border.all(color: color.withValues(alpha: 0.8)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: !fit || all.isEmpty
          ? content(all.length)
          : LayoutBuilder(
              builder: (context, c) {
                // Each icon takes 15px; the name keeps up to 48px (about
                // seven letters) before they show.
                final name = (TextPainter(
                  text: TextSpan(
                    text: label,
                    style: DefaultTextStyle.of(context).style.merge(style),
                  ),
                  textDirection: TextDirection.ltr,
                  textScaler: MediaQuery.textScalerOf(context),
                  maxLines: 1,
                )..layout()).width;
                final room = c.maxWidth - min(name, 48);
                final n = room.isFinite
                    ? (room / 15).floor().clamp(0, all.length)
                    : all.length;
                return content(n);
              },
            ),
    );
  }
}

/// The labels that fit in a commit's ref cell ([_RefPills._fit]).
class _Fit {
  _Fit(this.shown, this.widths, this.headWidth, this.chip, this.short);
  final List<_PillData> shown;
  final List<double> widths;

  /// The detached HEAD label's.
  final double headWidth;

  /// Whether "+N" shows the labels that don't.
  final bool chip;

  /// Whether a pill shows its short label (a main/master remote after
  /// another label).
  final bool Function(_PillData) short;
}
