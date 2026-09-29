import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../git/conflict.dart';
import '../../git/models.dart';
import '../details/details_panel.dart' show openExternally;
import '../dialogs/dialogs.dart';
import '../repo/repo_tab_controller.dart';
import '../widgets/common.dart';

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

  static const currentColor = AppColors.accent;
  static const incomingColor = AppColors.remoteBranch;

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
    _editor.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    String? text;
    try {
      text = await tab.repo.readWorkingText(path);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _loading = false;
      _text = text;
      _parsed = text == null || text.contains('\u0000')
          ? null
          : ConflictedText.parse(text);
    });
  }

  Future<void> _write(String text) async {
    try {
      await tab.repo.writeWorkingText(path, text);
    } catch (e) {
      tab.app.notify('Could not write $path: $e', error: true);
      return;
    }
    if (!mounted) return;
    setState(() {
      _text = text;
      _parsed = ConflictedText.parse(text);
    });
  }

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
      decoration: const BoxDecoration(
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
              message: 'Save (Ctrl/Cmd+S)',
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
            SmallIconButton(
              icon: Icons.refresh,
              tooltip: 'Reload the file (after editing it elsewhere)',
              onPressed: _load,
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
      return Padding(
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
    }
    final segments = _parsed!.segments;
    final total = _parsed!.conflicts.length;
    var n = 0;
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (var i = 0; i < segments.length; i++)
            if (segments[i] is ConflictBlock)
              _block(segments[i] as ConflictBlock, n++, total)
            else
              _plain(
                segments[i] as List<String>,
                i,
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
    int key, {
    required bool first,
    required bool last,
  }) {
    const keep = 3;
    final fold = lines.length > keep * 2 + 2 && !_expanded.contains(key);
    Widget line(String l) => SelectableLine(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          _strip(l),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          style: monoStyle(size: 12.5, color: AppColors.textDim),
        ),
      ),
    );
    if (!fold) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final l in lines) line(l)],
      );
    }
    final head = first ? const <String>[] : lines.sublist(0, keep);
    final tail = last ? const <String>[] : lines.sublist(lines.length - keep);
    final hidden = lines.length - head.length - tail.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final l in head) line(l),
        SelectionContainer.disabled(
          child: InkWell(
            onTap: () => setState(() => _expanded.add(key)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
              child: Row(
                children: [
                  const Icon(
                    Icons.unfold_more,
                    size: 14,
                    color: AppColors.textFaint,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$hidden unchanged lines',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textFaint,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        for (final l in tail) line(l),
      ],
    );
  }

  Widget _block(ConflictBlock b, int index, int total) {
    final sides = _sides;
    Widget side(
      String title,
      String subtitle,
      List<String> lines,
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
                        style: const TextStyle(color: AppColors.textFaint),
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
              const SelectionContainer.disabled(
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
            for (final l in lines)
              SelectableLine(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  child: Text(
                    _strip(l),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: monoStyle(
                      size: 12.5,
                      color: dim ? AppColors.textDim : AppColors.text,
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
                  const Icon(Icons.merge, size: 15, color: AppColors.warning),
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
          side(sides.current, 'current', b.current, ConflictView.currentColor),
          if (b.base != null)
            side(
              'Original',
              'common ancestor',
              b.base!,
              AppColors.textFaint,
              dim: true,
            ),
          side(
            sides.incoming,
            sides.incomingDetail == null
                ? 'incoming'
                : 'incoming · ${sides.incomingDetail}',
            b.incoming,
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
      border: const Border(top: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.check_circle_outline,
          size: 18,
          color: AppColors.success,
        ),
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
          const Icon(Icons.merge, size: 28, color: AppColors.warning),
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
