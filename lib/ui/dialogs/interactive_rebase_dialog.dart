import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../git/rebase_plan.dart';
import '../repo/repo_tab_controller.dart';
import '../widgets/common.dart';
import 'dialogs.dart';

/// Opens the interactive rebase editor for `base..HEAD` (null base: root).
Future<void> showInteractiveRebase(
  BuildContext context,
  RepoTabController tab,
  String? base, {
  required String baseLabel,
}) async {
  if (tab.isDirty) {
    tab.app.notify(
      'Commit or stash your changes before an interactive rebase.',
      error: true,
    );
    return;
  }
  List<RebaseStep> steps;
  bool hasMerges;
  try {
    steps = await tab.repo.rebaseCandidates(base);
    hasMerges = await tab.repo.rangeHasMerges(base);
  } catch (e) {
    tab.app.notify('$e', error: true);
    return;
  }
  if (steps.isEmpty) {
    tab.app.notify('No commits to rebase');
    return;
  }
  if (!context.mounted) return;
  final plan = await showAppDialog<RebasePlan>(
    context: context,
    builder: (_) => InteractiveRebaseDialog(
      steps: steps,
      branch: tab.currentBranch ?? 'HEAD',
      baseLabel: baseLabel,
      hasMerges: hasMerges,
    ),
  );
  if (plan == null) return;
  await tab.run(
    'Interactive rebase',
    () => tab.repo.rebaseInteractive(base, plan),
  );
}

class InteractiveRebaseDialog extends StatefulWidget {
  const InteractiveRebaseDialog({
    super.key,
    required this.steps,
    required this.branch,
    required this.baseLabel,
    required this.hasMerges,
  });

  /// Oldest first.
  final List<RebaseStep> steps;
  final String branch;
  final String baseLabel;
  final bool hasMerges;

  @override
  State<InteractiveRebaseDialog> createState() =>
      _InteractiveRebaseDialogState();
}

class _InteractiveRebaseDialogState extends State<InteractiveRebaseDialog> {
  // Displayed newest first like the graph; the plan is built oldest first.
  late final List<RebaseStep> _rows = widget.steps.reversed.toList();

  /// Rows the actions apply to.
  final Set<RebaseStep> _selection = {};

  /// Highlighted row: its message is shown on the right, arrow keys move it.
  RebaseStep? _cursor;

  /// Start of a Shift range.
  RebaseStep? _anchor;

  final _message = TextEditingController();
  final _listFocus = FocusNode(debugLabel: 'rebase-list');
  String? _error;

  static final _keys = {
    LogicalKeyboardKey.keyP: RebaseAction.pick,
    LogicalKeyboardKey.keyR: RebaseAction.reword,
    LogicalKeyboardKey.keyE: RebaseAction.edit,
    LogicalKeyboardKey.keyS: RebaseAction.squash,
    LogicalKeyboardKey.keyF: RebaseAction.fixup,
    LogicalKeyboardKey.keyD: RebaseAction.drop,
  };

  List<RebaseStep> get _oldestFirst => _rows.reversed.toList();

  /// Selected rows in display order (newest first).
  List<RebaseStep> get _selected => _rows.where(_selection.contains).toList();

  @override
  void initState() {
    super.initState();
    if (_rows.isNotEmpty) _selectOnly(_rows.first);
  }

  @override
  void dispose() {
    _message.dispose();
    _listFocus.dispose();
    super.dispose();
  }

  /// Group head a step's message belongs to (for squash groups).
  RebaseGroup? _groupFor(RebaseStep s) {
    try {
      for (final g in RebasePlan(_oldestFirst).groups()) {
        if (g.head == s) return g;
      }
    } on RebasePlanError {
      return null;
    }
    return null;
  }

  bool _editsMessage(RebaseStep s) {
    if (s.action == RebaseAction.reword) return true;
    final g = _groupFor(s);
    return g != null && g.hasSquash;
  }

  // ------------------------------------------------------------ selection

  void _setCursor(RebaseStep s) {
    _commitEditor();
    _cursor = s;
    final g = _groupFor(s);
    if (g != null && g.hasSquash && s.newMessage == s.message) {
      s.newMessage = g.defaultMessage();
    }
    _message.text = s.newMessage;
  }

  void _selectOnly(RebaseStep s) {
    _selection
      ..clear()
      ..add(s);
    _anchor = s;
    _setCursor(s);
  }

  void _selectRange(RebaseStep from, RebaseStep to) {
    final a = _rows.indexOf(from), b = _rows.indexOf(to);
    _selection
      ..clear()
      ..addAll(_rows.sublist(a < b ? a : b, (a < b ? b : a) + 1));
  }

  /// Click: select the row; Shift extends from the anchor, Ctrl/Cmd toggles.
  void _tapRow(RebaseStep s) {
    final kb = HardwareKeyboard.instance;
    setState(() {
      if (kb.isShiftPressed && _anchor != null) {
        _selectRange(_anchor!, s);
        _setCursor(s);
      } else if (kb.isControlPressed || kb.isMetaPressed) {
        _toggle(s);
      } else {
        _selectOnly(s);
      }
    });
    _listFocus.requestFocus();
  }

  void _toggle(RebaseStep s) {
    if (!_selection.remove(s)) _selection.add(s);
    _anchor = s;
    _setCursor(s);
  }

  void _tapCheckbox(RebaseStep s) {
    final kb = HardwareKeyboard.instance;
    setState(() {
      if (kb.isShiftPressed && _anchor != null) {
        _selectRange(_anchor!, s);
        _setCursor(s);
      } else {
        _toggle(s);
      }
    });
    _listFocus.requestFocus();
  }

  void _selectAll(bool all) {
    setState(() {
      _selection.clear();
      if (all) _selection.addAll(_rows);
    });
    _listFocus.requestFocus();
  }

  void _moveCursor(int delta, {required bool extend}) {
    if (_rows.isEmpty) return;
    final i = _cursor == null ? -1 : _rows.indexOf(_cursor!);
    final next = _rows[(i + delta).clamp(0, _rows.length - 1)];
    setState(() {
      if (extend && _anchor != null) {
        _selectRange(_anchor!, next);
        _setCursor(next);
      } else {
        _selectOnly(next);
      }
    });
  }

  /// Moves the selected rows one place up (towards newer) or down, keeping
  /// their relative order.
  void _moveSelection(int delta) {
    _commitEditor();
    setState(() {
      if (delta < 0) {
        for (var i = 1; i < _rows.length; i++) {
          if (_selection.contains(_rows[i]) &&
              !_selection.contains(_rows[i - 1])) {
            final s = _rows.removeAt(i);
            _rows.insert(i - 1, s);
          }
        }
      } else {
        for (var i = _rows.length - 2; i >= 0; i--) {
          if (_selection.contains(_rows[i]) &&
              !_selection.contains(_rows[i + 1])) {
            final s = _rows.removeAt(i);
            _rows.insert(i + 1, s);
          }
        }
      }
      _error = null;
    });
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final kb = HardwareKeyboard.instance;
    final ctrl = kb.isControlPressed || kb.isMetaPressed;
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      final delta = key == LogicalKeyboardKey.arrowUp ? -1 : 1;
      if (kb.isAltPressed) {
        _moveSelection(delta);
      } else {
        _moveCursor(delta, extend: kb.isShiftPressed);
      }
      return KeyEventResult.handled;
    }
    if (e is KeyRepeatEvent) return KeyEventResult.ignored;
    if (ctrl && key == LogicalKeyboardKey.keyA) {
      _selectAll(true);
      return KeyEventResult.handled;
    }
    final action = _keys[key];
    if (action != null && !ctrl && !kb.isAltPressed) {
      _applyToSelection(action);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // -------------------------------------------------------------- actions

  void _commitEditor() {
    final c = _cursor;
    if (c != null && _editsMessage(c)) c.newMessage = _message.text;
  }

  /// Applies [a] to the selection (or the highlighted row). Squashing or
  /// fixing up several rows folds them into the oldest one, which is kept.
  void _applyToSelection(RebaseAction a) {
    var targets = _selected;
    if (targets.isEmpty && _cursor != null) targets = [_cursor!];
    if (targets.isEmpty) return;
    if (a.folds && targets.length > 1) {
      final oldest = targets.last;
      if (oldest.action.folds || oldest.action == RebaseAction.drop) {
        oldest.action = RebaseAction.pick;
      }
      targets = targets.sublist(0, targets.length - 1);
    }
    _setActions(targets, a);
  }

  void _setActions(List<RebaseStep> targets, RebaseAction a) {
    _commitEditor();
    setState(() {
      for (final t in targets) {
        t.action = a;
      }
      _error = null;
      // Newly formed squash groups get the combined default message.
      for (final s in _rows) {
        final g = _groupFor(s);
        if (g != null && g.hasSquash && s.newMessage == s.message) {
          s.newMessage = g.defaultMessage();
        }
        if (g != null && !g.hasSquash && s.action != RebaseAction.reword) {
          s.newMessage = s.message;
        }
      }
      if (_cursor != null) _message.text = _cursor!.newMessage;
    });
  }

  void _start() {
    _commitEditor();
    final plan = RebasePlan(_oldestFirst);
    try {
      plan.validate();
    } on RebasePlanError catch (e) {
      setState(() => _error = e.message);
      return;
    }
    if (_rows.every((s) => s.action == RebaseAction.drop)) {
      setState(() => _error = 'At least one commit must be kept.');
      return;
    }
    Navigator.pop(context, plan);
  }

  static Color actionColor(RebaseAction a) => switch (a) {
    RebaseAction.pick => AppColors.text,
    RebaseAction.reword => AppColors.accent,
    RebaseAction.edit => AppColors.warning,
    RebaseAction.squash || RebaseAction.fixup => const Color(0xFFB180F0),
    RebaseAction.drop => AppColors.danger,
  };

  static String _keyOf(RebaseAction a) => a.label[0];

  // ------------------------------------------------------------------ UI

  Widget _toolbar() {
    final n = _selection.length;
    final all = n == _rows.length && n > 0;
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Checkbox(
              key: const ValueKey('rebase-select-all'),
              tristate: true,
              value: all ? true : (n == 0 ? false : null),
              visualDensity: VisualDensity.compact,
              onChanged: (_) => _selectAll(!all),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            n == 0 ? 'Select commits' : '$n selected',
            style: const TextStyle(fontSize: 12.5, color: AppColors.textDim),
          ),
          const SizedBox(width: 8),
          // Shrinks rather than overflows in a narrow dialog.
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                children: [
                  for (final a in RebaseAction.values)
                    Tooltip(
                      message: '${a.label} selected (${_keyOf(a)})',
                      child: TextButton(
                        key: ValueKey('rebase-action-${a.name}'),
                        onPressed: n == 0 && _cursor == null
                            ? null
                            : () {
                                _applyToSelection(a);
                                _listFocus.requestFocus(); // keep keys working
                              },
                        style: TextButton.styleFrom(
                          foregroundColor: actionColor(a),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: _keyOf(a),
                                style: const TextStyle(
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                              TextSpan(text: a.label.substring(1)),
                            ],
                          ),
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, int i) {
    final s = _rows[i];
    final dropped = s.action == RebaseAction.drop;
    final selected = _selection.contains(s);
    final isCursor = s == _cursor;
    return ReorderableDragStartListener(
      key: ObjectKey(s),
      index: i,
      child: Material(
        color: selected ? AppColors.selection : Colors.transparent,
        child: InkWell(
          onTap: () => _tapRow(s),
          child: Container(
            height: 38,
            padding: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: isCursor ? AppColors.accent : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 6),
                SizedBox(
                  width: 24,
                  child: Checkbox(
                    value: selected,
                    visualDensity: VisualDensity.compact,
                    onChanged: (_) => _tapCheckbox(s),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.drag_indicator,
                  size: 16,
                  color: AppColors.textFaint,
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 96,
                  child: AppDropdown<RebaseAction>(
                    value: s.action,
                    expand: true,
                    items: [
                      for (final a in RebaseAction.values)
                        (a, a.label, actionColor(a)),
                    ],
                    onChanged: (a) => _setActions([s], a),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  s.shortSha,
                  style: monoStyle(size: 12, color: AppColors.textDim),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _editsMessage(s)
                        ? s.newMessage.split('\n').first
                        : s.subject,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: dropped ? AppColors.textFaint : AppColors.text,
                      decoration: dropped ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selStep = _cursor;
    return Dialog(
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true):
              _start,
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): _start,
        },
        child: SizedBox(
          width: 960,
          height: 620,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Interactive rebase: ${widget.branch} onto ${widget.baseLabel}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Newest on top. Drag or Alt+↑↓ to reorder; Shift/Ctrl-click '
                  'to select several. Keys: P pick, R reword, E edit, '
                  'S squash, F fixup, D drop. Squash/Fixup fold commits into '
                  'the one below them.',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12),
                ),
                if (widget.hasMerges)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'This range contains merge commits; they will be flattened.',
                      style: TextStyle(color: AppColors.warning, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 12),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _toolbar(),
                              Expanded(
                                child: Focus(
                                  focusNode: _listFocus,
                                  autofocus: true,
                                  onKeyEvent: _onKey,
                                  child: ReorderableListView.builder(
                                    buildDefaultDragHandles: false,
                                    itemCount: _rows.length,
                                    onReorderItem: (from, to) {
                                      _commitEditor();
                                      setState(() {
                                        final s = _rows.removeAt(from);
                                        _rows.insert(to, s);
                                      });
                                    },
                                    itemBuilder: _row,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 2,
                        child: selStep == null
                            ? const Center(
                                child: Text(
                                  'Select a commit to see or edit its message',
                                  style: TextStyle(color: AppColors.textDim),
                                ),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    _editsMessage(selStep)
                                        ? 'New message'
                                        : 'Message (choose Reword to edit)',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textDim,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Expanded(
                                    child: TextField(
                                      key: ObjectKey(selStep),
                                      controller: _message,
                                      readOnly: !_editsMessage(selStep),
                                      maxLines: null,
                                      expands: true,
                                      textAlignVertical: TextAlignVertical.top,
                                      style: monoStyle(size: 12.5),
                                      onChanged: (_) => _commitEditor(),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _start,
                      child: const Text('Start rebase'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
