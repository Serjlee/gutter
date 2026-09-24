import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../git/models.dart';
import '../../git/parsers/diff_parser.dart';
import '../repo/repo_actions.dart';
import '../repo/repo_tab_controller.dart';
import '../widgets/common.dart';
import 'file_preview.dart';

const _lineHeight = 19.0;
const _maxLinesBeforeConfirm = 6000;

/// Diff (or file preview) of the file selected in the details panel.
class DiffView extends StatefulWidget {
  const DiffView({super.key, required this.tab});
  final RepoTabController tab;

  @override
  State<DiffView> createState() => _DiffViewState();
}

enum _Mode { unified, split, file }

class _DiffViewState extends State<DiffView> {
  late _Mode _mode = widget.tab.app.settings.diffSplit
      ? _Mode.split
      : _Mode.unified;
  final _selection = <int, Set<int>>{};
  (int, int)? _anchor; // (hunk, line) for shift-click ranges
  FileDiff? _selectionFor;
  bool _showHuge = false;
  final _vScroll = ScrollController();
  final _hScroll = ScrollController();

  RepoTabController get tab => widget.tab;

  @override
  void dispose() {
    _vScroll.dispose();
    _hScroll.dispose();
    super.dispose();
  }

  void _setMode(_Mode m) {
    setState(() => _mode = m);
    if (m != _Mode.file) {
      tab.app.settings.diffSplit = m == _Mode.split;
      tab.app.save();
    }
  }

  bool get _canSelect {
    final t = tab.diffTarget;
    return t is WorkingFileTarget && !t.entry.conflicted;
  }

  void _toggleLine(int hunk, int line, {required bool shift}) {
    if (!_canSelect) return;
    final lines = tab.diff!.hunks[hunk].lines;
    if (!lines[line].isChange) return;
    setState(() {
      final set = _selection.putIfAbsent(hunk, () => <int>{});
      if (shift && _anchor != null && _anchor!.$1 == hunk) {
        final a = min(_anchor!.$2, line), b = max(_anchor!.$2, line);
        for (var i = a; i <= b; i++) {
          if (lines[i].isChange) set.add(i);
        }
      } else if (!set.remove(line)) {
        set.add(line);
      }
      if (set.isEmpty) _selection.remove(hunk);
      _anchor = (hunk, line);
    });
  }

  int get _selectedCount => _selection.values.fold(0, (a, s) => a + s.length);

  Future<void> _applyLines({bool discard = false}) async {
    final sel = {
      for (final e in _selection.entries) e.key: {...e.value},
    };
    if (discard && !await _confirmDiscard('the selected lines')) return;
    setState(_selection.clear);
    await tab.applySelection(sel, discard: discard);
  }

  Future<void> _applyHunk(int hunk, {bool discard = false}) async {
    if (discard && !await _confirmDiscard('this hunk')) return;
    setState(_selection.clear);
    await tab.applySelection({hunk: null}, discard: discard);
  }

  Future<bool> _confirmDiscard(String what) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text(
              'Discard changes',
              style: TextStyle(fontSize: 17),
            ),
            content: Text(
              'Discard $what from the working tree? This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final target = tab.diffTarget!;
    final diff = tab.diff;
    if (!identical(diff, _selectionFor)) {
      _selection.clear();
      _anchor = null;
      _selectionFor = diff;
      _showHuge = false;
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): tab.closeDiff,
      },
      child: Focus(
        autofocus: true,
        child: Container(
          color: AppColors.background,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(target, diff),
              if (tab.diffLoading) const LinearProgressIndicator(minHeight: 2),
              Expanded(child: _body(target, diff)),
              if (_selectedCount > 0) _selectionBar(target),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(DiffTarget target, FileDiff? diff) {
    final actions = RepoActions(context, tab);
    final kind = switch (target) {
      final CommitFileTarget t => t.file.kind,
      final WorkingFileTarget t =>
        t.staged
            ? (t.entry.index ?? ChangeKind.modified)
            : (t.entry.worktree ?? ChangeKind.modified),
    };
    final oldPath = switch (target) {
      final CommitFileTarget t => t.file.oldPath,
      final WorkingFileTarget t => t.entry.oldPath,
    };
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: AppColors.panelAlt,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          ChangeKindBadge(kind),
          const SizedBox(width: 8),
          Expanded(
            child: PathLabel(target.path, oldPath: oldPath, fontSize: 13),
          ),
          if (diff != null && !diff.isBinary)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '+${diff.additions} ',
                      style: const TextStyle(color: AppColors.diffAddText),
                    ),
                    TextSpan(
                      text: '-${diff.deletions}',
                      style: const TextStyle(color: AppColors.diffDelText),
                    ),
                  ],
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          if (target is WorkingFileTarget && !target.entry.conflicted) ...[
            if (target.staged)
              TextButton.icon(
                onPressed: () => tab.unstageEntries([target.entry]),
                icon: const Icon(Icons.remove_circle_outline, size: 16),
                label: const Text('Unstage file'),
              )
            else ...[
              TextButton.icon(
                onPressed: () => actions.discard([target.entry]),
                icon: const Icon(
                  Icons.delete_outline,
                  size: 16,
                  color: AppColors.danger,
                ),
                label: const Text(
                  'Discard file',
                  style: TextStyle(color: AppColors.danger),
                ),
              ),
              TextButton.icon(
                onPressed: () => tab.stageEntries([target.entry]),
                icon: const Icon(Icons.add_circle_outline, size: 16),
                label: const Text('Stage file'),
              ),
            ],
          ],
          const SizedBox(width: 8),
          SegmentedButton<_Mode>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity(horizontal: -4, vertical: -4),
              textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
            ),
            segments: const [
              ButtonSegment(value: _Mode.unified, label: Text('Unified')),
              ButtonSegment(value: _Mode.split, label: Text('Split')),
              ButtonSegment(value: _Mode.file, label: Text('File')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => _setMode(s.first),
          ),
          const SizedBox(width: 6),
          SmallIconButton(
            icon: Icons.close,
            tooltip: 'Close (Esc)',
            onPressed: tab.closeDiff,
          ),
        ],
      ),
    );
  }

  Widget _selectionBar(DiffTarget target) {
    final staged = target is WorkingFileTarget && target.staged;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: AppColors.toolbar,
      child: Row(
        children: [
          Text(
            '$_selectedCount line${_selectedCount == 1 ? '' : 's'} selected',
            style: const TextStyle(fontSize: 12.5),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => setState(_selection.clear),
            child: const Text('Clear'),
          ),
          if (!staged)
            TextButton(
              onPressed: () => _applyLines(discard: true),
              child: const Text(
                'Discard lines',
                style: TextStyle(color: AppColors.danger),
              ),
            ),
          const SizedBox(width: 6),
          FilledButton(
            onPressed: () => _applyLines(),
            child: Text(staged ? 'Unstage lines' : 'Stage lines'),
          ),
        ],
      ),
    );
  }

  Widget _body(DiffTarget target, FileDiff? diff) {
    if (_mode == _Mode.file) {
      return FilePreview(key: _previewKey(target), tab: tab, version: diff);
    }
    if (tab.diffError != null) {
      return Center(
        child: Text(
          tab.diffError!,
          style: const TextStyle(color: AppColors.danger),
        ),
      );
    }
    if (diff == null) {
      if (tab.diffLoading) return const SizedBox();
      return const Center(
        child: Text(
          'No changes to show (mode or permission change only)',
          style: TextStyle(color: AppColors.textDim),
        ),
      );
    }
    if (diff.isBinary) {
      return Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Binary file changed',
              style: TextStyle(color: AppColors.textDim),
            ),
          ),
          Expanded(
            child: FilePreview(
              key: _previewKey(target),
              tab: tab,
              version: diff,
            ),
          ),
        ],
      );
    }
    final totalLines = diff.hunks.fold<int>(0, (a, h) => a + h.lines.length);
    if (totalLines > _maxLinesBeforeConfirm && !_showHuge) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Large diff ($totalLines lines)',
              style: const TextStyle(color: AppColors.textDim),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => setState(() => _showHuge = true),
              child: const Text('Show anyway'),
            ),
          ],
        ),
      );
    }
    return _mode == _Mode.split ? _splitBody(diff) : _unifiedBody(diff);
  }

  Key _previewKey(DiffTarget t) => ValueKey(switch (t) {
    final CommitFileTarget c => '${c.commit.sha}:${c.path}',
    final WorkingFileTarget w => '${w.staged}:${w.path}',
  });

  // ----------------------------------------------------------- unified

  Widget _unifiedBody(FileDiff diff) {
    final rows = <(int, int)>[]; // (hunk, line) ; line -1 = hunk header
    var maxLen = 0;
    var maxNo = 0;
    for (var h = 0; h < diff.hunks.length; h++) {
      rows.add((h, -1));
      final hunk = diff.hunks[h];
      for (var l = 0; l < hunk.lines.length; l++) {
        rows.add((h, l));
        final line = hunk.lines[l];
        maxLen = max(maxLen, _visualLength(line.text));
      }
      maxNo = max(
        maxNo,
        max(hunk.oldStart + hunk.oldCount, hunk.newStart + hunk.newCount),
      );
    }
    final noWidth = max(3, '$maxNo'.length) * _charWidth + 12;
    final contentWidth = noWidth * 2 + 20 + maxLen * _charWidth + 40;
    return _scrollable(
      contentWidth,
      ListView.builder(
        controller: _vScroll,
        itemExtent: _lineHeight,
        itemCount: rows.length,
        itemBuilder: (context, i) {
          final (h, l) = rows[i];
          if (l < 0) return _hunkHeader(diff, h);
          final line = diff.hunks[h].lines[l];
          return _UnifiedLine(
            line: line,
            numberWidth: noWidth,
            selected: _selection[h]?.contains(l) ?? false,
            selectable: _canSelect && line.isChange,
            onToggle: (shift) => _toggleLine(h, l, shift: shift),
          );
        },
      ),
    );
  }

  Widget _scrollable(double contentWidth, Widget list) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = max(c.maxWidth, contentWidth);
        return Scrollbar(
          controller: _hScroll,
          child: SingleChildScrollView(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: w, height: c.maxHeight, child: list),
          ),
        );
      },
    );
  }

  Widget _hunkHeader(FileDiff diff, int h) {
    final hunk = diff.hunks[h];
    final t = tab.diffTarget;
    final working = t is WorkingFileTarget && !t.entry.conflicted;
    final staged = t is WorkingFileTarget && t.staged;
    Widget btn(String label, VoidCallback onTap, {Color? color}) => InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          label,
          style: TextStyle(fontSize: 11.5, color: color ?? AppColors.accent),
        ),
      ),
    );
    return Container(
      color: AppColors.diffHunkBg,
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              hunk.header,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: monoStyle(size: 12, color: AppColors.textDim),
            ),
          ),
          if (working && !staged) ...[
            btn(
              'Discard hunk',
              () => _applyHunk(h, discard: true),
              color: AppColors.danger,
            ),
            btn('Stage hunk', () => _applyHunk(h)),
          ],
          if (working && staged) btn('Unstage hunk', () => _applyHunk(h)),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- split

  Widget _splitBody(FileDiff diff) {
    // Each row: (hunk, leftLine?, rightLine?) ; header rows have both -1.
    final rows = <(int, int?, int?)>[];
    var maxLen = 0;
    for (var h = 0; h < diff.hunks.length; h++) {
      rows.add((h, -1, -1));
      final lines = diff.hunks[h].lines;
      var i = 0;
      while (i < lines.length) {
        final l = lines[i];
        maxLen = max(maxLen, _visualLength(l.text));
        if (l.type == DiffLineType.context) {
          rows.add((h, i, i));
          i++;
        } else if (l.type == DiffLineType.noNewline) {
          i++;
        } else {
          final dels = <int>[], adds = <int>[];
          while (i < lines.length && lines[i].type == DiffLineType.remove) {
            maxLen = max(maxLen, _visualLength(lines[i].text));
            dels.add(i++);
            if (i < lines.length && lines[i].type == DiffLineType.noNewline) {
              i++;
            }
          }
          while (i < lines.length && lines[i].type == DiffLineType.add) {
            maxLen = max(maxLen, _visualLength(lines[i].text));
            adds.add(i++);
            if (i < lines.length && lines[i].type == DiffLineType.noNewline) {
              i++;
            }
          }
          for (var k = 0; k < max(dels.length, adds.length); k++) {
            rows.add((
              h,
              k < dels.length ? dels[k] : null,
              k < adds.length ? adds[k] : null,
            ));
          }
        }
      }
    }
    final half = maxLen * _charWidth + 70;
    return LayoutBuilder(
      builder: (context, c) {
        final paneW = max(c.maxWidth / 2, half);
        return _scrollable(
          paneW * 2,
          ListView.builder(
            controller: _vScroll,
            itemExtent: _lineHeight,
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final (h, left, right) = rows[i];
              if (left == -1 && right == -1) return _hunkHeader(diff, h);
              final lines = diff.hunks[h].lines;
              Widget side(int? idx, bool isLeft) {
                if (idx == null) {
                  return Container(width: paneW, color: AppColors.panel);
                }
                final line = lines[idx];
                return SizedBox(
                  width: paneW,
                  child: _SplitLine(
                    line: line,
                    number: isLeft ? line.oldNo : line.newNo,
                    selected: _selection[h]?.contains(idx) ?? false,
                    selectable: _canSelect && line.isChange,
                    onToggle: (shift) => _toggleLine(h, idx, shift: shift),
                  ),
                );
              }

              return Row(
                children: [
                  side(left, true),
                  Container(width: 1, color: AppColors.border),
                  side(right, false),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

double get _charWidth => _measureChar();
double? _cachedCharWidth;
double _measureChar() {
  return _cachedCharWidth ??=
      (TextPainter(
        text: TextSpan(text: 'MMMMMMMMMM', style: monoStyle(size: 12.5)),
        textDirection: TextDirection.ltr,
      )..layout()).width /
      10;
}

int _visualLength(String s) {
  var n = 0;
  for (var i = 0; i < s.length; i++) {
    n += s.codeUnitAt(i) == 9 ? 4 : 1;
  }
  return n;
}

String _expandTabs(String s) => s.replaceAll('\t', '    ');

class _UnifiedLine extends StatelessWidget {
  const _UnifiedLine({
    required this.line,
    required this.numberWidth,
    required this.selected,
    required this.selectable,
    required this.onToggle,
  });

  final DiffLine line;
  final double numberWidth;
  final bool selected;
  final bool selectable;
  final void Function(bool shift) onToggle;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _colors(line.type, selected);
    final numStyle = monoStyle(size: 11.5, color: AppColors.textFaint);
    return Container(
      color: bg,
      child: Row(
        children: [
          _Gutter(
            selectable: selectable,
            selected: selected,
            onToggle: onToggle,
            child: Row(
              children: [
                SizedBox(
                  width: numberWidth,
                  child: Text(
                    line.oldNo?.toString() ?? '',
                    textAlign: TextAlign.right,
                    style: numStyle,
                  ),
                ),
                SizedBox(
                  width: numberWidth,
                  child: Text(
                    line.newNo?.toString() ?? '',
                    textAlign: TextAlign.right,
                    style: numStyle,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 20,
            child: Text(
              line.marker == ' ' ? '' : line.marker,
              textAlign: TextAlign.center,
              style: monoStyle(size: 12.5, color: fg),
            ),
          ),
          Expanded(
            child: Text(
              line.type == DiffLineType.noNewline
                  ? line.text
                  : _expandTabs(line.text),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: monoStyle(size: 12.5, color: fg).copyWith(
                fontStyle: line.type == DiffLineType.noNewline
                    ? FontStyle.italic
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SplitLine extends StatelessWidget {
  const _SplitLine({
    required this.line,
    required this.number,
    required this.selected,
    required this.selectable,
    required this.onToggle,
  });

  final DiffLine line;
  final int? number;
  final bool selected;
  final bool selectable;
  final void Function(bool shift) onToggle;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _colors(line.type, selected);
    return Container(
      color: bg,
      child: Row(
        children: [
          _Gutter(
            selectable: selectable,
            selected: selected,
            onToggle: onToggle,
            child: SizedBox(
              width: 48,
              child: Text(
                number?.toString() ?? '',
                textAlign: TextAlign.right,
                style: monoStyle(size: 11.5, color: AppColors.textFaint),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _expandTabs(line.text),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: monoStyle(size: 12.5, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

(Color?, Color) _colors(DiffLineType t, bool selected) {
  if (selected) return (AppColors.diffSelected, AppColors.text);
  return switch (t) {
    DiffLineType.add => (AppColors.diffAddBg, AppColors.diffAddText),
    DiffLineType.remove => (AppColors.diffDelBg, AppColors.diffDelText),
    DiffLineType.noNewline => (null, AppColors.textFaint),
    DiffLineType.context => (null, AppColors.text),
  };
}

/// Line-number gutter; clicking selects the line for partial staging.
class _Gutter extends StatelessWidget {
  const _Gutter({
    required this.selectable,
    required this.selected,
    required this.onToggle,
    required this.child,
  });

  final bool selectable;
  final bool selected;
  final void Function(bool shift) onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!selectable) return child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onToggle(HardwareKeyboard.instance.isShiftPressed),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selected ? AppColors.accent : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
