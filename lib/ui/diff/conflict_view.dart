import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../app/theme.dart';
import '../../git/conflict.dart';
import '../../git/models.dart';
import '../details/details_panel.dart' show openExternally;
import '../dialogs/dialogs.dart';
import '../repo/repo_tab_controller.dart';
import '../widgets/common.dart';
import 'syntax.dart';

/// Whole file: one side's version (deleting the file if that side deleted
/// it), staged; then on to the next conflicted file.
Future<void> takeConflictSide(
  RepoTabController tab,
  String path, {
  required bool current,
}) async {
  final ok = await tab.run(
    'Resolve',
    () => tab.repo.resolveWith(path, ours: current),
  );
  if (ok) tab.openNextConflict(path);
}

/// Stages [path] as resolved, after a warning if it still has conflict
/// markers; then on to the next conflicted file.
Future<void> markConflictResolved(
  BuildContext context,
  RepoTabController tab,
  String path,
) async {
  if (await tab.hasConflictMarkers(path)) {
    if (!context.mounted) return;
    final go = await confirm(
      context,
      title: 'Conflict markers left',
      message:
          '$path still has conflict markers (<<<<<<< … >>>>>>>). Mark it '
          'resolved anyway? The markers would be committed as they are.',
      confirmLabel: 'Mark resolved',
      danger: true,
    );
    if (!go) return;
  }
  final ok = await tab.run('Resolve', () => tab.repo.markResolved([path]));
  if (ok) tab.openNextConflict(path);
}

/// Resolves the conflicts of one file: each conflict shows the current and
/// incoming sides (named after what's being combined) with buttons to keep
/// one, the other, or both. The whole file can also take one side, or be
/// edited by hand.
class ConflictView extends StatefulWidget {
  const ConflictView({super.key, required this.tab, required this.entry});
  final RepoTabController tab;
  final StatusEntry entry;

  static final currentColor = AppColors.accent;
  static final incomingColor = AppColors.remoteBranch;

  @override
  State<ConflictView> createState() => _ConflictViewState();
}

class _ConflictViewState extends State<ConflictView> {
  String? _text;
  ConflictedText? _parsed;
  bool _loading = true;
  bool _editing = false;
  final _editor = TextEditingController();
  final _expanded = <int>{};

  /// Syntax highlighting per segment (parallel to the parsed segments).
  List<_SegmentSpans>? _spans;
  bool? _spansOn;

  RepoTabController get tab => widget.tab;
  StatusEntry get entry => widget.entry;
  String get path => entry.path;

  /// Both sides still have the file: its content can be merged line by
  /// line. Otherwise one side deleted (or never had) it.
  bool get _bothHaveIt => const {'UU', 'AA'}.contains(entry.conflictCode);

  ConflictSides get _sides =>
      tab.conflictSides ??
      const ConflictSides(
        current: 'current',
        incoming: 'incoming',
        description: '',
      );

  @override
  void initState() {
    super.initState();
    _load();
    _watch = Timer.periodic(watchInterval, (_) => _checkDisk());
  }

  @override
  void didUpdateWidget(ConflictView old) {
    super.didUpdateWidget(old);
    if (old.entry.path != path) {
      _editing = false;
      _expanded.clear();
      _load();
    }
  }

  @override
  void dispose() {
    _watch?.cancel();
    _editor.dispose();
    super.dispose();
  }

  /// How often the file is checked for changes made elsewhere (an editor,
  /// a script): a stat, and a read only when it changed.
  static const watchInterval = Duration(seconds: 1);
  Timer? _watch;

  /// The file as last read or written here: (modified, size), null if it
  /// doesn't exist.
  (DateTime, int)? _stamp;
  bool _checking = false;

  /// Changed on disk while being edited here: the edit is kept, and a bar
  /// offers to reload.
  bool _changedWhileEditing = false;

  Future<(DateTime, int)?> _stat() async {
    final st = await File(p.join(tab.repo.path, path)).stat();
    return st.type == FileSystemEntityType.notFound
        ? null
        : (st.modified, st.size);
  }

  Future<void> _checkDisk() async {
    if (_checking || _loading || !mounted) return;
    _checking = true;
    try {
      final now = await _stat();
      if (!mounted || now == _stamp) return;
      if (_editing) {
        if (!_changedWhileEditing) setState(() => _changedWhileEditing = true);
        _stamp = now;
      } else {
        await _load(quiet: true);
      }
    } catch (_) {
      // Checked again next time.
    } finally {
      _checking = false;
    }
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    String? text;
    (DateTime, int)? stamp;
    try {
      stamp = await _stat();
      text = await tab.repo.readWorkingText(path);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _loading = false;
      _stamp = stamp;
      _changedWhileEditing = false;
      if (quiet && text == _text) return;
      _text = text;
      _parsed = text == null || text.contains('\u0000')
          ? null
          : ConflictedText.parse(text);
      _computeSpans();
    });
  }

  Future<void> _write(String text) async {
    try {
      await tab.repo.writeWorkingText(path, text);
      _stamp = await _stat(); // our own change: not one to reload
    } catch (e) {
      tab.app.notify('Could not write $path: $e', error: true);
      return;
    }
    if (!mounted) return;
    setState(() {
      _changedWhileEditing = false;
      _text = text;
      _parsed = ConflictedText.parse(text);
      _computeSpans();
    });
  }

  /// Highlights the file three ways (with the current sides, with the
  /// incoming sides, with the original), so each side reads as the code it
  /// would become, multi-line constructs included.
  void _computeSpans() {
    final parsed = _parsed;
    final lang = languageForPath(path);
    _spansOn = tab.app.settings.syntaxHighlight;
    if (parsed == null || lang == null || !_spansOn!) {
      _spans = null;
      return;
    }
    final segments = parsed.segments;
    (List<List<TextSpan>>?, List<(int, int)>) version(
      List<String> Function(ConflictBlock) pick,
    ) {
      final lines = <String>[];
      final ranges = <(int, int)>[];
      for (final seg in segments) {
        final ls = seg is ConflictBlock ? pick(seg) : seg as List<String>;
        ranges.add((lines.length, ls.length));
        lines.addAll(ls.map(_strip));
      }
      return (highlightLines(lines.join('\n'), lang), ranges);
    }

    List<List<TextSpan>>? slice(
      (List<List<TextSpan>>?, List<(int, int)>) v,
      int i,
    ) {
      final (all, ranges) = v;
      final (start, len) = ranges[i];
      if (all == null || all.length < start + len) return null;
      return all.sublist(start, start + len);
    }

    final current = version((b) => b.current);
    final incoming = version((b) => b.incoming);
    final base = parsed.conflicts.any((b) => b.base != null)
        ? version((b) => b.base ?? b.current)
        : null;
    _spans = [
      for (var i = 0; i < segments.length; i++)
        _SegmentSpans(
          current: slice(current, i),
          incoming: slice(incoming, i),
          base: base == null ? null : slice(base, i),
        ),
    ];
  }

  /// A line of code: highlighted when [spans] are given.
  Widget _code(String line, List<TextSpan>? spans, Color color) => spans == null
      ? Text(
          _strip(line),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          style: monoStyle(size: 12.5, color: color),
        )
      : Text.rich(
          TextSpan(
            style: monoStyle(size: 12.5, color: color),
            children: spans,
          ),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
        );

  Future<void> _resolveBlock(int index, ConflictChoice choice) =>
      _write(_parsed!.resolve(index, choice));

  Future<void> _take({required bool current}) =>
      takeConflictSide(tab, path, current: current);

  Future<void> _markResolved() => markConflictResolved(context, tab, path);

  void _startEditing() {
    _editor.text = _text ?? '';
    setState(() => _editing = true);
  }

  Future<void> _saveEdit() async {
    await _write(_editor.text);
    if (mounted) setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        // While editing: Esc cancels the edit, Ctrl/Cmd+S saves it.
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            _editing ? setState(() => _editing = false) : tab.closeDiff(),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (_editing) _saveEdit();
        },
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
          if (_editing) _saveEdit();
        },
      },
      child: Focus(
        autofocus: true,
        child: Container(
          color: AppColors.background,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              if (_loading) const LinearProgressIndicator(minHeight: 2),
              Expanded(child: _body()),
              if (_parsed != null &&
                  _parsed!.conflicts.isEmpty &&
                  !_editing &&
                  _bothHaveIt)
                _resolvedBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final n = _parsed?.conflicts.length;
    final sides = _sides;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.panelAlt,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const ChangeKindBadge(ChangeKind.conflicted),
          const SizedBox(width: 8),
          Expanded(child: PathLabel(path, fontSize: 13)),
          if (n != null && _bothHaveIt && !_editing)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                n == 0
                    ? 'No conflicts left'
                    : '$n conflict${n == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 12,
                  color: n == 0 ? AppColors.success : AppColors.warning,
                ),
              ),
            ),
          if (_editing) ...[
            TextButton(
              onPressed: () => setState(() => _editing = false),
              child: const Text('Cancel'),
            ),
            Tooltip(
              message: 'Save (${shortcut('S')})',
              child: FilledButton(
                onPressed: _saveEdit,
                child: const Text('Save'),
              ),
            ),
          ] else ...[
            if (_bothHaveIt)
              _headerButton(
                'Take ${_short(sides.current)}',
                'Use ${sides.current}\'s version of the whole file',
                () => _take(current: true),
                color: ConflictView.currentColor,
              ),
            if (_bothHaveIt)
              _headerButton(
                'Take ${_short(sides.incoming)}',
                'Use ${sides.incoming}\'s version of the whole file',
                () => _take(current: false),
                color: ConflictView.incomingColor,
              ),
            if (_bothHaveIt && _parsed != null)
              SmallIconButton(
                icon: Icons.edit_outlined,
                tooltip: 'Edit the file',
                onPressed: _startEditing,
              ),
            if (_bothHaveIt)
              SmallIconButton(
                icon: Icons.check,
                tooltip: 'Mark resolved (stage the file as it is)',
                color: AppColors.success,
                onPressed: _markResolved,
              ),
            SmallIconButton(
              icon: Icons.open_in_new,
              tooltip: 'Open in external editor',
              onPressed: () => openExternally(tab, path),
            ),
          ],
          SmallIconButton(
            icon: Icons.close,
            tooltip: 'Close (Esc)',
            onPressed: tab.closeDiff,
          ),
        ],
      ),
    );
  }

  Widget _headerButton(
    String label,
    String tooltip,
    VoidCallback onPressed, {
    required Color color,
  }) => Padding(
    padding: const EdgeInsets.only(right: 4),
    child: Tooltip(
      message: tooltip,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(foregroundColor: color),
        child: Text(label, style: const TextStyle(fontSize: 12.5)),
      ),
    ),
  );

  Widget _body() {
    if (_loading && _text == null) return const SizedBox();
    if (!_bothHaveIt) return _oneSideDeleted();
    if (_text == null) {
      return _message('The file is missing from the working tree.');
    }
    if (_parsed == null) return _binary();
    if (_editing) {
      final editor = Padding(
        padding: const EdgeInsets.all(10),
        child: TextField(
          controller: _editor,
          autofocus: true,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          style: monoStyle(size: 12.5),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.all(10),
          ),
        ),
      );
      if (!_changedWhileEditing) return editor;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: const ValueKey('conflict-changed-on-disk'),
            color: AppColors.warning.withValues(alpha: 0.16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.warning_amber, size: 16, color: AppColors.warning),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'The file changed on disk. Saving replaces that version '
                    'with yours.',
                    style: TextStyle(fontSize: 12.5),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() => _editing = false);
                    _load();
                  },
                  child: const Text('Reload (drop my edits)'),
                ),
              ],
            ),
          ),
          Expanded(child: editor),
        ],
      );
    }
    if (_spansOn != tab.app.settings.syntaxHighlight) _computeSpans();
    final segments = _parsed!.segments;
    final total = _parsed!.conflicts.length;
    var n = 0;
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (var i = 0; i < segments.length; i++)
            if (segments[i] is ConflictBlock)
              _block(segments[i] as ConflictBlock, n++, total, _spans?[i])
            else
              _plain(
                segments[i] as List<String>,
                i,
                _spans?[i].current,
                first: i == 0,
                last: i == segments.length - 1,
              ),
        ],
      ),
    );
  }

  /// Unchanged lines between conflicts; long runs fold to their ends.
  Widget _plain(
    List<String> lines,
    int key,
    List<List<TextSpan>>? spans, {
    required bool first,
    required bool last,
  }) {
    const keep = 3;
    final fold = lines.length > keep * 2 + 2 && !_expanded.contains(key);
    // Unchanged code is a little dimmer than the conflicts.
    Widget line(int i) => SelectableLine(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Opacity(
          opacity: 0.75,
          child: _code(lines[i], spans?[i], AppColors.textDim),
        ),
      ),
    );
    if (!fold) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (var i = 0; i < lines.length; i++) line(i)],
      );
    }
    final head = first ? 0 : keep;
    final tailStart = last ? lines.length : lines.length - keep;
    final hidden = tailStart - head;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < head; i++) line(i),
        SelectionContainer.disabled(
          child: InkWell(
            onTap: () => setState(() => _expanded.add(key)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
              child: Row(
                children: [
                  Icon(Icons.unfold_more, size: 14, color: AppColors.textFaint),
                  const SizedBox(width: 6),
                  Text(
                    '$hidden unchanged lines',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textFaint,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        for (var i = tailStart; i < lines.length; i++) line(i),
      ],
    );
  }

  Widget _block(ConflictBlock b, int index, int total, _SegmentSpans? spans) {
    final sides = _sides;
    Widget side(
      String title,
      String subtitle,
      List<String> lines,
      List<List<TextSpan>>? lineSpans,
      Color color, {
      bool dim = false,
    }) {
      return Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: dim ? 0.05 : 0.10),
          border: Border(left: BorderSide(color: color, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectionContainer.disabled(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 5, 12, 3),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: title,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(
                        text: '  $subtitle',
                        style: TextStyle(color: AppColors.textFaint),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
            ),
            if (lines.isEmpty)
              SelectionContainer.disabled(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(13, 0, 12, 6),
                  child: Text(
                    '(nothing: this side removed these lines)',
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textFaint,
                    ),
                  ),
                ),
              ),
            for (var i = 0; i < lines.length; i++)
              SelectableLine(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  child: Opacity(
                    opacity: dim ? 0.7 : 1,
                    child: _code(
                      lines[i],
                      lineSpans?[i],
                      dim ? AppColors.textDim : AppColors.text,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 5),
          ],
        ),
      );
    }

    Widget choice(String label, ConflictChoice c, Color color) => Padding(
      padding: const EdgeInsets.only(left: 6),
      child: OutlinedButton(
        key: ValueKey('conflict-$index-${c.name}'),
        onPressed: () => _resolveBlock(index, c),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.6)),
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: const TextStyle(fontSize: 12),
        ),
        child: Text(label),
      ),
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectionContainer.disabled(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
              child: Row(
                children: [
                  Icon(Icons.merge, size: 15, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Text(
                    'Conflict ${index + 1} of $total',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  choice(
                    'Use ${_short(sides.current)}',
                    ConflictChoice.current,
                    ConflictView.currentColor,
                  ),
                  choice(
                    'Use ${_short(sides.incoming)}',
                    ConflictChoice.incoming,
                    ConflictView.incomingColor,
                  ),
                  choice('Use both', ConflictChoice.both, AppColors.text),
                ],
              ),
            ),
          ),
          side(
            sides.current,
            'current',
            b.current,
            spans?.current,
            ConflictView.currentColor,
          ),
          if (b.base != null)
            side(
              'Original',
              'common ancestor',
              b.base!,
              spans?.base,
              AppColors.textFaint,
              dim: true,
            ),
          side(
            sides.incoming,
            sides.incomingDetail == null
                ? 'incoming'
                : 'incoming · ${sides.incomingDetail}',
            b.incoming,
            spans?.incoming,
            ConflictView.incomingColor,
          ),
        ],
      ),
    );
  }

  Widget _resolvedBar() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.success.withValues(alpha: 0.12),
      border: Border(top: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      children: [
        Icon(Icons.check_circle_outline, size: 18, color: AppColors.success),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'No conflicts left in this file.',
            style: TextStyle(fontSize: 13),
          ),
        ),
        FilledButton(
          key: const ValueKey('conflict-mark-resolved'),
          onPressed: _markResolved,
          child: const Text('Mark resolved'),
        ),
      ],
    ),
  );

  /// One side deleted the file (or only one side added it): keep it, or
  /// delete it.
  Widget _oneSideDeleted() {
    final sides = _sides;
    final code = entry.conflictCode;
    final (text, keepCurrent, keepIncoming) = switch (code) {
      'DU' => (
        '${sides.current} deleted this file, and ${sides.incoming} changed it.',
        'Keep it deleted',
        'Keep ${_short(sides.incoming)}\'s version',
      ),
      'UD' => (
        '${sides.incoming} deleted this file, and ${sides.current} changed it.',
        'Keep ${_short(sides.current)}\'s version',
        'Delete it',
      ),
      'AU' => (
        'Only ${sides.current} added this file.',
        'Keep it',
        'Delete it',
      ),
      'UA' => (
        'Only ${sides.incoming} added this file.',
        'Delete it',
        'Keep it',
      ),
      _ => (
        'Both sides deleted this file (probably renamed differently).',
        'Delete it',
        'Delete it',
      ),
    };
    return _message(
      text,
      actions: [
        FilledButton.tonal(
          onPressed: () => _take(current: true),
          child: Text(keepCurrent),
        ),
        if (keepIncoming != keepCurrent)
          FilledButton.tonal(
            onPressed: () => _take(current: false),
            child: Text(keepIncoming),
          ),
      ],
    );
  }

  Widget _binary() {
    final sides = _sides;
    return _message(
      'This is a binary file: pick one version.',
      actions: [
        FilledButton.tonal(
          onPressed: () => _take(current: true),
          child: Text('Take ${_short(sides.current)}'),
        ),
        FilledButton.tonal(
          onPressed: () => _take(current: false),
          child: Text('Take ${_short(sides.incoming)}'),
        ),
      ],
    );
  }

  Widget _message(String text, {List<Widget> actions = const []}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.merge, size: 28, color: AppColors.warning),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13.5),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 10, children: actions),
          ],
        ],
      ),
    ),
  );

  static String _strip(String line) =>
      line.replaceAll('\t', '    ').replaceAll(RegExp(r'\r?\n$'), '');

  /// A side's name, short enough for a button.
  static String _short(String name) {
    final first = name.length > 24 ? '${name.substring(0, 22)}…' : name;
    return first;
  }
}

/// Highlight spans of one segment's lines, per side (a plain segment uses
/// [current]).
class _SegmentSpans {
  const _SegmentSpans({this.current, this.incoming, this.base});
  final List<List<TextSpan>>? current;
  final List<List<TextSpan>>? incoming;
  final List<List<TextSpan>>? base;
}
