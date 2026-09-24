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
  int? _selected;
  final _message = TextEditingController();
  String? _error;

  List<RebaseStep> get _oldestFirst => _rows.reversed.toList();

  @override
  void dispose() {
    _message.dispose();
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

  void _select(int? i) {
    _commitEditor();
    setState(() {
      _selected = i;
      if (i != null) {
        final s = _rows[i];
        final g = _groupFor(s);
        if (g != null && g.hasSquash && s.newMessage == s.message) {
          s.newMessage = g.defaultMessage();
        }
        _message.text = s.newMessage;
      }
    });
  }

  void _commitEditor() {
    final i = _selected;
    if (i != null && i < _rows.length && _editsMessage(_rows[i])) {
      _rows[i].newMessage = _message.text;
    }
  }

  void _setAction(int i, RebaseAction a) {
    _commitEditor();
    setState(() {
      _rows[i].action = a;
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
      if (_selected != null) _message.text = _rows[_selected!].newMessage;
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

  Color _actionColor(RebaseAction a) => switch (a) {
    RebaseAction.pick => AppColors.text,
    RebaseAction.reword => AppColors.accent,
    RebaseAction.edit => AppColors.warning,
    RebaseAction.squash || RebaseAction.fixup => const Color(0xFFB180F0),
    RebaseAction.drop => AppColors.danger,
  };

  @override
  Widget build(BuildContext context) {
    final sel = _selected;
    final selStep = sel == null ? null : _rows[sel];
    return Dialog(
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true):
              _start,
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): _start,
        },
        child: SizedBox(
          width: 860,
          height: 600,
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
                  'Drag to reorder (newest on top). Squash/Fixup fold a commit into the one below it.',
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
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: ReorderableListView.builder(
                            buildDefaultDragHandles: false,
                            itemCount: _rows.length,
                            onReorderItem: (from, to) {
                              _commitEditor();
                              setState(() {
                                final s = _rows.removeAt(from);
                                _rows.insert(to, s);
                                if (_selected == from) _selected = to;
                              });
                            },
                            itemBuilder: (context, i) {
                              final s = _rows[i];
                              final dropped = s.action == RebaseAction.drop;
                              return ReorderableDragStartListener(
                                key: ObjectKey(s),
                                index: i,
                                child: Material(
                                  color: i == _selected
                                      ? AppColors.selection
                                      : Colors.transparent,
                                  child: InkWell(
                                    onTap: () => _select(i),
                                    child: Container(
                                      height: 38,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      child: Row(
                                        children: [
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
                                                for (final a
                                                    in RebaseAction.values)
                                                  (a, a.label, _actionColor(a)),
                                              ],
                                              onChanged: (a) =>
                                                  _setAction(i, a),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            s.shortSha,
                                            style: monoStyle(
                                              size: 12,
                                              color: AppColors.textDim,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              _editsMessage(s)
                                                  ? s.newMessage
                                                        .split('\n')
                                                        .first
                                                  : s.subject,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: dropped
                                                    ? AppColors.textFaint
                                                    : AppColors.text,
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
                                ),
                              );
                            },
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
