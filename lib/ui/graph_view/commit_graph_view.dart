import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../git/models.dart';
import '../../graph/graph_painter.dart';
import '../repo/repo_actions.dart';
import '../repo/repo_tab_controller.dart';
import '../widgets/common.dart';

const _metrics = GraphMetrics();

/// Column widths (message column takes the remaining space).
class GraphColumns {
  GraphColumns(Map<String, double> saved)
    : refs = saved['refs'] ?? 190,
      graph = saved['graph'],
      author = saved['author'] ?? 140,
      date = saved['date'] ?? 130,
      sha = saved['sha'] ?? 70;

  double refs;
  double? graph; // null: auto from lane count
  double author;
  double date;
  double sha;

  double graphWidth(int lanes) =>
      graph ?? _metrics.widthFor(max(1, min(lanes, 12)));

  /// Decides which columns fit in [width]: optional columns are dropped
  /// (sha, then date, then author) and the ref column shrinks so the
  /// message column keeps at least [minMessage] pixels.
  FittedColumns fit(double width, double graphW, {double minMessage = 160}) {
    var refsW = refs;
    var showSha = true, showDate = true, showAuthor = true;
    double used() =>
        refsW +
        graphW +
        (showAuthor ? author : 0) +
        (showDate ? date : 0) +
        (showSha ? sha : 0);
    if (used() + minMessage > width) showSha = false;
    if (used() + minMessage > width) showDate = false;
    if (used() + minMessage > width) showAuthor = false;
    if (used() + minMessage > width) {
      refsW = max(70, width - minMessage - graphW);
    }
    return FittedColumns(
      refs: refsW,
      graph: graphW,
      author: showAuthor ? author : null,
      date: showDate ? date : null,
      sha: showSha ? sha : null,
    );
  }

  Map<String, double> toJson() => {
    'refs': refs,
    'graph': ?graph,
    'author': author,
    'date': date,
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
    this.date,
    this.sha,
  });
  final double refs;
  final double graph;
  final double? author;
  final double? date;
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

  RepoTabController get tab => widget.tab;

  @override
  void initState() {
    super.initState();
    tab.scrollToRow.addListener(_onScrollRequest);
    _scroll.addListener(_onScroll);
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
    final top = row * h;
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
    final graphW = _cols.graphWidth(graph.layout.maxLanes);
    final actions = RepoActions(context, tab);
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
                            : const Text(
                                'No commits yet',
                                style: TextStyle(color: AppColors.textDim),
                              ),
                      )
                    : ListView.builder(
                        key: PageStorageKey('graph-${tab.repo.path}'),
                        controller: _scroll,
                        itemExtent: _metrics.rowHeight,
                        itemCount: graph.rowCount + (graph.truncated ? 1 : 0),
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
                                      child: const Text('Load more commits'),
                                    ),
                            );
                          }
                          return _GraphRow(
                            key: ValueKey(graph.commitAt(row)?.sha ?? wipSha),
                            tab: tab,
                            row: row,
                            cols: fitted,
                            actions: actions,
                            onFocus: () => _focus.requestFocus(),
                          );
                        },
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
  });

  final GraphColumns cols;
  final FittedColumns fitted;
  final void Function(void Function()) onResize;
  final VoidCallback onResizeEnd;
  final VoidCallback onResetGraph;

  Widget _title(String t, double? width, {bool expand = false}) {
    final text = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        t,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 11,
          letterSpacing: 0.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textDim,
        ),
      ),
    );
    if (expand) return Expanded(child: text);
    return SizedBox(width: width, child: text);
  }

  Widget _handle(void Function(double) onDrag) => ResizeHandle(
    onDrag: (dx) => onResize(() => onDrag(dx)),
    onEnd: onResizeEnd,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      decoration: const BoxDecoration(
        color: AppColors.panelAlt,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          _title('BRANCH / TAG', fitted.refs - 5),
          _handle((dx) => cols.refs = max(60, fitted.refs + dx)),
          GestureDetector(
            onDoubleTap: onResetGraph,
            child: _title('GRAPH', fitted.graph - 5),
          ),
          _handle((dx) => cols.graph = max(30, fitted.graph + dx)),
          _title('COMMIT MESSAGE', null, expand: true),
          if (fitted.author != null) ...[
            _handle((dx) => cols.author = max(40, cols.author - dx)),
            _title('AUTHOR', fitted.author! - 5),
          ],
          if (fitted.date != null) ...[
            _handle((dx) => cols.date = max(40, cols.date - dx)),
            _title('DATE', fitted.date! - 5),
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

class _GraphRow extends StatefulWidget {
  const _GraphRow({
    super.key,
    required this.tab,
    required this.row,
    required this.cols,
    required this.actions,
    required this.onFocus,
  });

  final RepoTabController tab;
  final int row;
  final FittedColumns cols;
  final RepoActions actions;
  final VoidCallback onFocus;

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
    final dimmed = tab.search.trim().isNotEmpty && !isHit;

    Color? bg;
    if (selected) {
      bg = laneColor.withValues(alpha: 0.22);
    } else if (_hover) {
      bg = AppColors.hover;
    } else if (isHit) {
      bg = AppColors.warning.withValues(alpha: 0.10);
    }

    final refs = commit == null || stash != null
        ? const <GitRef>[]
        : (tab.refsBySha[sha] ?? const <GitRef>[]);
    final msgColor = dimmed ? AppColors.textFaint : AppColors.text;
    final dimColor = dimmed ? AppColors.textFaint : AppColors.textDim;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          widget.onFocus();
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
          child: Row(
            children: [
              SizedBox(
                width: widget.cols.refs,
                child: commit == null
                    ? const SizedBox()
                    : _RefPills(
                        refs: refs,
                        laneColor: laneColor,
                        actions: widget.actions,
                        headSha: tab.headSha,
                        isHeadCommit: sha == tab.headSha,
                      ),
              ),
              SizedBox(
                width: widget.cols.graph,
                height: _metrics.rowHeight,
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
                      isHead: commit != null && sha == tab.headSha,
                      dimmed: dimmed,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: commit == null
                      ? _WipSummary(tab: tab)
                      : Text(
                          commit.subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: stash != null ? dimColor : msgColor,
                            fontStyle: stash != null ? FontStyle.italic : null,
                          ),
                        ),
                ),
              ),
              if (widget.cols.author != null)
                _cell(commit?.authorName ?? '', widget.cols.author!, dimColor),
              if (widget.cols.date != null)
                _cell(
                  commit == null ? '' : formatDate(commit.date),
                  widget.cols.date!,
                  dimColor,
                ),
              if (widget.cols.sha != null)
                SizedBox(
                  width: widget.cols.sha,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      commit?.shortSha ?? '',
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
  }

  Widget _cell(String text, double width, Color color) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        text,
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
            style: const TextStyle(
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
}

class _RefPills extends StatelessWidget {
  const _RefPills({
    required this.refs,
    required this.laneColor,
    required this.actions,
    required this.headSha,
    required this.isHeadCommit,
  });

  final List<GitRef> refs;
  final Color laneColor;
  final RepoActions actions;
  final String? headSha;
  final bool isHeadCommit;

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
        : switch (p.type) {
            RefType.localBranch => 1,
            RefType.remoteBranch => 2,
            _ => 3,
          };
    list.sort((a, b) => rank(a).compareTo(rank(b)));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final pills = _group();
    final detachedHead = isHeadCommit && !refs.any((r) => r.isHead);
    if (pills.isEmpty && !detachedHead) return const SizedBox();
    final first = pills.isEmpty ? null : pills.first;
    final more = pills.length - 1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          if (detachedHead)
            _pill(
              context,
              label: 'HEAD',
              icon: Icons.adjust,
              color: laneColor,
              bold: true,
            ),
          if (first != null) Flexible(child: _pillFor(context, first)),
          if (more > 0)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: PopupMenuButton<VoidCallback>(
                popUpAnimationStyle: AnimationStyle.noAnimation,
                tooltip: pills.skip(1).map((p) => p.label).join('\n'),
                padding: EdgeInsets.zero,
                itemBuilder: (_) => [
                  for (final p in pills.skip(1))
                    PopupMenuItem<VoidCallback>(
                      enabled: false,
                      height: 30,
                      child: _pillFor(context, p),
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
                    '+$more',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textDim,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pillFor(BuildContext context, _PillData p) {
    final icons = <IconData>[
      if (p.local != null) Icons.laptop_mac,
      if (p.remotes.isNotEmpty) Icons.cloud_outlined,
      if (p.tag != null) Icons.sell_outlined,
    ];
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
          label: p.label,
          icons: icons,
          color: color,
          bold: p.isHead,
          check: p.isHead,
        ),
      ),
    );
  }

  Widget _pill(
    BuildContext context, {
    required String label,
    IconData? icon,
    List<IconData> icons = const [],
    required Color color,
    bool bold = false,
    bool check = false,
  }) {
    return Container(
      height: 21,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: bold ? 0.35 : 0.2),
        border: Border.all(color: color.withValues(alpha: 0.8)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (check)
            const Padding(
              padding: EdgeInsets.only(right: 3),
              child: Icon(Icons.check, size: 12, color: Colors.white),
            ),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.white,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (icon != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(icon, size: 11, color: Colors.white70),
            ),
          for (final i in icons)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(i, size: 11, color: Colors.white70),
            ),
        ],
      ),
    );
  }
}
