import 'dart:math';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../git/models.dart';
import '../widgets/common.dart';
import 'dialogs.dart';

/// Lists the local branches that can be deleted, merged ones checked; the
/// rest (gone from the remote, maybe not merged) unchecked. Returns the
/// chosen names, or null when cancelled.
Future<List<String>?> showCleanupBranches(
  BuildContext context,
  BranchCleanup cleanup,
) => showAppDialog<List<String>>(
  context: context,
  builder: (_) => CleanupBranchesDialog(cleanup: cleanup),
);

/// Above this many branches the list gets a filter, and its sections start
/// collapsed (so each one's heading, count and select-all show at once).
const _longList = 15;

class _Section {
  const _Section(this.id, this.title, this.note, this.branches);
  final String id;
  final String title;
  final String note;
  final List<CleanupBranch> branches;
}

class CleanupBranchesDialog extends StatefulWidget {
  const CleanupBranchesDialog({super.key, required this.cleanup});
  final BranchCleanup cleanup;

  @override
  State<CleanupBranchesDialog> createState() => _CleanupBranchesDialogState();
}

class _CleanupBranchesDialogState extends State<CleanupBranchesDialog> {
  late final Set<String> _chosen = {
    for (final b in widget.cleanup.merged) b.name,
  };
  late final List<_Section> _sections = [
    if (widget.cleanup.merged.isNotEmpty)
      _Section(
        'merged',
        'Merged into ${widget.cleanup.base}',
        'All their commits are in ${widget.cleanup.base}: nothing is lost.',
        widget.cleanup.merged,
      ),
    if (widget.cleanup.gone.isNotEmpty)
      _Section(
        'gone',
        'Deleted on the remote',
        'Not merged into ${widget.cleanup.base}. Usually they were '
            'squash-merged, but commits found only here would be lost.',
        widget.cleanup.gone,
      ),
  ];
  late final bool _long =
      widget.cleanup.merged.length + widget.cleanup.gone.length > _longList;
  late final Set<String> _collapsed = {
    if (_long) ..._sections.map((s) => s.id),
  };
  final _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  String get _query => _filter.text.trim().toLowerCase();

  List<CleanupBranch> _visible(_Section s) => _query.isEmpty
      ? s.branches
      : s.branches.where((b) => b.name.toLowerCase().contains(_query)).toList();

  void _toggle(String name) => setState(
    () => _chosen.contains(name) ? _chosen.remove(name) : _chosen.add(name),
  );

  /// Selects the section's shown branches, or clears them when all are.
  void _toggleAll(List<CleanupBranch> shown) => setState(() {
    final names = shown.map((b) => b.name);
    if (names.every(_chosen.contains)) {
      _chosen.removeAll(names);
    } else {
      _chosen.addAll(names);
    }
  });

  @override
  Widget build(BuildContext context) {
    final n = _chosen.length;
    final filtering = _query.isNotEmpty;
    final items = <Widget>[];
    for (final (i, s) in _sections.indexed) {
      final shown = _visible(s);
      if (filtering && shown.isEmpty) continue;
      // A filter opens the sections it matches in.
      final open = filtering || !_collapsed.contains(s.id);
      if (i > 0 && items.isNotEmpty) items.add(const SizedBox(height: 10));
      items.add(_heading(s, shown, open));
      // Always shown: it says what deleting them costs.
      items.add(
        Padding(
          padding: const EdgeInsets.only(left: 52, bottom: 4),
          child: Text(
            s.note,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textDim),
          ),
        ),
      );
      if (open) {
        items.addAll(shown.map(_row));
      }
    }
    if (filtering && items.isEmpty) {
      items.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'No branches match.',
            style: TextStyle(color: AppColors.textDim),
          ),
        ),
      );
    }
    final maxHeight = max(300.0, MediaQuery.sizeOf(context).height * 0.7 - 160);
    return AlertDialog(
      title: const Text('Clean up branches', style: TextStyle(fontSize: 17)),
      content: SizedBox(
        width: 540,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_long)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  key: const ValueKey('cleanup-filter'),
                  controller: _filter,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 16),
                    hintText: 'Filter branches',
                  ),
                ),
              ),
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: ListView(shrinkWrap: true, children: items),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('cleanup-delete'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: n == 0
              ? null
              : () => Navigator.pop(context, [
                  for (final s in _sections)
                    for (final b in s.branches)
                      if (_chosen.contains(b.name)) b.name,
                ]),
          child: Text(n == 1 ? 'Delete 1 branch…' : 'Delete $n branches…'),
        ),
      ],
    );
  }

  /// Chevron (collapse), tri-state checkbox (all / some / none of the
  /// shown branches), title and "chosen of total".
  Widget _heading(_Section s, List<CleanupBranch> shown, bool open) {
    final chosen = shown.where((b) => _chosen.contains(b.name)).length;
    final all = s.branches.where((b) => _chosen.contains(b.name)).length;
    return InkWell(
      key: ValueKey('cleanup-section-${s.id}'),
      borderRadius: BorderRadius.circular(4),
      onTap: _query.isNotEmpty
          ? null
          : () => setState(
              () => _collapsed.contains(s.id)
                  ? _collapsed.remove(s.id)
                  : _collapsed.add(s.id),
            ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Icon(
              open ? Icons.expand_more : Icons.chevron_right,
              size: 18,
              color: AppColors.textDim,
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                key: ValueKey('cleanup-all-${s.id}'),
                tristate: true,
                value: chosen == 0
                    ? false
                    : chosen == shown.length
                    ? true
                    : null,
                onChanged: shown.isEmpty ? null : (_) => _toggleAll(shown),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '$all of ${s.branches.length}',
              style: const TextStyle(fontSize: 12, color: AppColors.textDim),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(CleanupBranch b) => InkWell(
    key: ValueKey('cleanup-${b.name}'),
    onTap: () => _toggle(b.name),
    borderRadius: BorderRadius.circular(4),
    child: Padding(
      padding: const EdgeInsets.only(left: 22, top: 3, bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: _chosen.contains(b.name),
              onChanged: (_) => _toggle(b.name),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              b.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            relativeTime(b.date),
            style: const TextStyle(fontSize: 12, color: AppColors.textFaint),
          ),
        ],
      ),
    ),
  );
}
