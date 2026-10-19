import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../git/rebase_plan.dart';
import '../repo/repo_tab_controller.dart';
import '../widgets/common.dart';
import 'work_in_progress.dart';

/// Opens the interactive rebase editor for `base..HEAD` (null base: root),
/// docked under the graph: the tab is read-only until the rebase is started
/// or cancelled.
Future<void> showInteractiveRebase(
  BuildContext context,
  RepoTabController tab,
  String? base, {
  required String baseLabel,
  bool Function(List<RebaseStep> steps)? prepare,
  Set<String> initialSelection = const {},
}) async {
  if (tab.rebaseSession.value != null) {
    tab.app.notify('An interactive rebase is already being prepared');
    return;
  }
  List<RebaseStep> steps;
  bool hasMerges;
  String? head;
  try {
    steps = await tab.repo.rebaseCandidates(base);
    hasMerges = await tab.repo.rangeHasMerges(base);
    head = await tab.repo.headSha();
  } catch (e) {
    tab.app.notifyError(e);
    return;
  }
  if (steps.isEmpty) {
    tab.app.notify('No commits to rebase');
    return;
  }
  // Lets callers preset actions (e.g. squash a selection); false cancels.
  if (prepare != null && !prepare(steps)) return;
  tab.openRebase(
    RebaseSession(
      base: base,
      baseLabel: baseLabel,
      branch: tab.currentBranch ?? 'HEAD',
      head: head,
      steps: steps,
      hasMerges: hasMerges,
      initialSelection: initialSelection,
    ),
  );
}

/// Runs the prepared rebase with [plan], once uncommitted changes are dealt
/// with; if that's cancelled, the editor stays open.
Future<void> startInteractiveRebase(
  BuildContext context,
  RepoTabController tab,
  RebasePlan plan,
) async {
  final session = tab.rebaseSession.value;
  if (session == null) return;
  session.starting = true;
  try {
    if (await tab.repo.headSha() != session.head) {
      tab.app.notify(
        '${session.branch} changed since the editor opened: '
        'open it again to rebase what it has now.',
        error: true,
      );
      tab.closeRebase();
      return;
    }
    if (!context.mounted ||
        !await resolveWorkInProgress(context, tab, action: 'rebase')) {
      return;
    }
  } finally {
    session.starting = false;
  }
  if (tab.rebaseSession.value != session) return;
  tab.closeRebase();
  await tab.run(
    'Interactive rebase',
    () => tab.repo.rebaseInteractive(session.base, plan),
  );
}

/// The color a rebase action is shown in (the editor, the graph).
Color rebaseActionColor(RebaseAction a) => switch (a) {
  RebaseAction.pick => AppColors.text,
  RebaseAction.reword => AppColors.accent,
  RebaseAction.edit => AppColors.warning,
  RebaseAction.squash || RebaseAction.fixup => AppColors.squash,
  RebaseAction.drop => AppColors.danger,
};

/// Starts [session]'s plan if it's valid; otherwise shows why in the editor.
void _startSession(
  BuildContext context,
  RepoTabController tab,
  RebaseSession session,
) {
  final error = session.check();
  if (error != null) {
    session.error = error;
    tab.setRebaseCollapsed(false);
    return;
  }
  unawaited(startInteractiveRebase(context, tab, session.plan));
}

/// [tab]'s prepared rebase, docked under the graph: the editor, resized
/// from its top edge, or collapsed into a one-line summary.
class RebaseDock extends StatelessWidget {
  const RebaseDock({
    super.key,
    required this.tab,
    required this.session,
    required this.maxHeight,
  });
  final RepoTabController tab;
  final RebaseSession session;

  /// The most it can take (the graph keeps the rest).
  final double maxHeight;

  static const minHeight = 220.0;

  @override
  Widget build(BuildContext context) {
    final settings = tab.app.settings;
    void save() => tab.app.save();
    if (session.collapsed) return _summary(context);
    final low = min(minHeight, maxHeight);
    final height = settings.rebaseDockHeight.clamp(low, maxHeight).toDouble();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResizeHandle(
          key: const ValueKey('rebase-dock-resize'),
          vertical: true,
          onDrag: (dy) {
            // From the current height, not this build's: several moves can
            // come in one frame.
            final now = settings.rebaseDockHeight.clamp(low, maxHeight);
            settings.rebaseDockHeight = (now - dy)
                .clamp(low, maxHeight)
                .toDouble();
            tab.setRebaseCollapsed(false);
          },
          onEnd: save,
        ),
        SizedBox(
          key: const ValueKey('rebase-dock'),
          height: height,
          child: Material(
            color: AppColors.panel,
            child: InteractiveRebaseEditor(
              tab: tab,
              session: session,
              onStart: (_) => _startSession(context, tab, session),
              onCancel: tab.closeRebase,
              onCollapse: () => tab.setRebaseCollapsed(true),
              split: settings.rebaseSplit,
              onSplit: (split) {
                settings.rebaseSplit = split;
                save();
              },
            ),
          ),
        ),
      ],
    );
  }

  /// One line: what the plan does, and its actions.
  Widget _summary(BuildContext context) {
    return Container(
      key: const ValueKey('rebase-summary'),
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.edit_note, size: 18, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text:
                        'Interactive rebase: ${session.branch} onto '
                        '${session.baseLabel}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: '  ${session.summary}',
                    style: TextStyle(color: AppColors.textDim),
                  ),
                ],
              ),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          TextButton(
            key: const ValueKey('rebase-expand'),
            onPressed: () => tab.setRebaseCollapsed(false),
            child: const Text('Edit plan'),
          ),
          TextButton(onPressed: tab.closeRebase, child: const Text('Cancel')),
          const SizedBox(width: 6),
          FilledButton(
            onPressed: () => _startSession(context, tab, session),
            child: const Text('Start rebase'),
          ),
          const SizedBox(width: 4),
          SmallIconButton(
            icon: Icons.expand_less,
            tooltip: 'Show panel',
            onPressed: () => tab.setRebaseCollapsed(false),
          ),
        ],
      ),
    );
  }
}

class InteractiveRebaseEditor extends StatefulWidget {
  const InteractiveRebaseEditor({
    super.key,
    this.tab,
    required this.session,
    required this.onStart,
    required this.onCancel,
    this.onCollapse,
    this.split = 0.6,
    this.onSplit,
  });

  /// Lists the highlighted commit's files (and previews them) when given.
  final RepoTabController? tab;

  /// The rebase being prepared, which also keeps the editor's state (the
  /// editor is built again when shown again).
  final RebaseSession session;

  /// Called with a valid plan to run it.
  final ValueChanged<RebasePlan> onStart;
  final VoidCallback onCancel;

  /// Collapses the panel into a summary, when it can be.
  final VoidCallback? onCollapse;

  /// The commit list's share of the width; dragging the gap changes it.
  final double split;
  final ValueChanged<double>? onSplit;

  @override
  State<InteractiveRebaseEditor> createState() =>
      _InteractiveRebaseEditorState();
}

class _InteractiveRebaseEditorState extends State<InteractiveRebaseEditor> {
  RebaseSession get _session => widget.session;

  /// Changes the plan (or the editor's view of it): the graph shows it too.
  void _update(VoidCallback f) {
    setState(f);
    _session.changed();
  }

  // Displayed newest first like the graph; the plan is built oldest first.
  List<RebaseStep> get _rows => _session.rows;

  /// Rows the actions apply to.
  Set<RebaseStep> get _selection => _session.selection;

  /// Highlighted row: its message is shown on the right, arrow keys move it.
  RebaseStep? get _cursor => _session.cursor;
  set _cursor(RebaseStep? s) => _session.cursor = s;

  /// Start of a Shift range.
  RebaseStep? get _anchor => _session.anchor;
  set _anchor(RebaseStep? s) => _session.anchor = s;

  String? get _error => _session.error;
  set _error(String? e) => _session.error = e;

  final _message = TextEditingController();
  final _listFocus = FocusNode(debugLabel: 'rebase-list');
  late double _split = widget.split;

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
    if (!_session.shown) {
      _session.shown = true;
      final initial = _rows
          .where((s) => _session.initialSelection.contains(s.sha))
          .toList();
      if (initial.isNotEmpty) {
        _selection.addAll(initial);
        _anchor = initial.last;
        _setCursor(initial.last);
      } else if (_rows.isNotEmpty) {
        _selectOnly(_rows.first);
      }
    } else {
      // Shown again (expanded, or back on the tab): as it was.
      _message.text = _cursor?.newMessage ?? '';
    }
    // Docked under the graph (not a dialog): take the keys from it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _listFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _commitEditor(); // what was typed stays with the plan
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
    if (s != _cursor) {
      // The graph shows the highlighted commit (after this frame: it may be
      // being built).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _cursor == s) widget.tab?.jumpToSha(s.sha);
      });
    }
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
    _update(() {
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
    _update(() {
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
    _update(() {
      _selection.clear();
      if (all) _selection.addAll(_rows);
    });
    _listFocus.requestFocus();
  }

  void _moveCursor(int delta, {required bool extend}) {
    if (_rows.isEmpty) return;
    final i = _cursor == null ? -1 : _rows.indexOf(_cursor!);
    final next = _rows[(i + delta).clamp(0, _rows.length - 1)];
    _update(() {
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
    _update(() {
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
    _update(() {
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
    final error = _session.check();
    if (error != null) {
      _update(() => _error = error);
      return;
    }
    widget.onStart(_session.plan);
  }

  static Color actionColor(RebaseAction a) => rebaseActionColor(a);

  static String _keyOf(RebaseAction a) => a.label[0];

  // ------------------------------------------------------------------ UI

  Widget _toolbar() {
    final n = _selection.length;
    final all = n == _rows.length && n > 0;
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
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
            style: TextStyle(fontSize: 12.5, color: AppColors.textDim),
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
                Icon(
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

  Widget _listPane() {
    return Container(
      key: const ValueKey('rebase-list-pane'),
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
                  _update(() {
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
    );
  }

  /// The new message of [s] (reworded, or heading squashed commits).
  Widget _messagePane(RebaseStep s) {
    return Column(
      key: const ValueKey('rebase-message'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          s.action == RebaseAction.reword
              ? 'New message'
              : 'Message of the squashed commits',
          style: TextStyle(fontSize: 12, color: AppColors.textDim),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: TextField(
            key: ObjectKey(s),
            controller: _message,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: monoStyle(size: 12.5),
            onChanged: (_) => _commitEditor(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final selStep = _cursor;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _start,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _start,
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // One line: what, how (a tooltip), what's wrong, the actions.
            SizedBox(
              height: 36,
              child: Row(
                children: [
                  // What it is and what's wrong take what's left; the
                  // actions stay at the right edge.
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.edit_note,
                          size: 18,
                          color: AppColors.accent,
                        ),
                        const SizedBox(width: 8),
                        // The title shrinks last.
                        Flexible(
                          flex: 3,
                          child: Text(
                            'Interactive rebase: ${_session.branch} onto '
                            '${_session.baseLabel}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Tooltip(
                          message:
                              'Newest on top. Drag or ${altShortcut('↑↓')} to '
                              'reorder; Shift/$modKey-click to select several.\n'
                              'Keys: P pick, R reword, E edit, S squash, F fixup, '
                              'D drop.\nSquash/Fixup fold commits into the one '
                              'below them. $modKey+Enter starts.',
                          child: Icon(
                            Icons.info_outline,
                            size: 16,
                            color: AppColors.textFaint,
                          ),
                        ),
                        if (_session.hasMerges) ...[
                          const SizedBox(width: 10),
                          Tooltip(
                            message:
                                'This range contains merge commits; they will be '
                                'flattened.',
                            child: Text(
                              'Merges will be flattened',
                              style: TextStyle(
                                color: AppColors.warning,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _error ?? '',
                            key: const ValueKey('rebase-error'),
                            textAlign: TextAlign.right,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.danger,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: widget.onCancel,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    onPressed: _start,
                    child: const Text('Start rebase'),
                  ),
                  if (widget.onCollapse != null) ...[
                    const SizedBox(width: 4),
                    SmallIconButton(
                      key: const ValueKey('rebase-collapse'),
                      icon: Icons.expand_more,
                      tooltip: 'Collapse panel',
                      onPressed: widget.onCollapse,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              // The commits; beside them, a message to write when the
              // highlighted one gets a new one.
              child: selStep == null || !_editsMessage(selStep)
                  ? _listPane()
                  : LayoutBuilder(
                      builder: (context, c) {
                        // The commit list's share; the gap between the panes
                        // drags. Each pane keeps room for its controls.
                        const gap = 14.0;
                        final total = c.maxWidth - gap;
                        double fit(double w) => w.clamp(
                          min(300.0, total / 2),
                          max(total / 2, total - 220),
                        );
                        final width = fit(total * _split);
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(width: width, child: _listPane()),
                            SizedBox(
                              key: const ValueKey('rebase-split'),
                              width: gap,
                              child: ResizeHandle(
                                line: false,
                                onDrag: (dx) => _update(
                                  // From the current split: several moves can
                                  // come in one frame.
                                  () => _split =
                                      fit(fit(total * _split) + dx) / total,
                                ),
                                onEnd: () => widget.onSplit?.call(_split),
                              ),
                            ),
                            Expanded(child: _messagePane(selStep)),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
