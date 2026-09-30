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

  void _toggle(String name) => setState(
    () => _chosen.contains(name) ? _chosen.remove(name) : _chosen.add(name),
  );

  @override
  Widget build(BuildContext context) {
    final c = widget.cleanup;
    const dim = TextStyle(fontSize: 12.5, color: AppColors.textDim);
    final n = _chosen.length;
    return AlertDialog(
      title: const Text('Clean up branches', style: TextStyle(fontSize: 17)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (c.merged.isNotEmpty) ...[
                _heading('Merged into ${c.base}'),
                Text(
                  'All their commits are in ${c.base}: nothing is lost.',
                  style: dim,
                ),
                const SizedBox(height: 4),
                for (final b in c.merged) _row(b),
              ],
              if (c.gone.isNotEmpty) ...[
                if (c.merged.isNotEmpty) const SizedBox(height: 14),
                _heading('Deleted on the remote'),
                Text(
                  'Not merged into ${c.base}. Usually they were squash-merged, '
                  'but commits found only here would be lost.',
                  style: dim,
                ),
                const SizedBox(height: 4),
                for (final b in c.gone) _row(b),
              ],
            ],
          ),
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
                  for (final b in [...c.merged, ...c.gone])
                    if (_chosen.contains(b.name)) b.name,
                ]),
          child: Text(n == 1 ? 'Delete 1 branch…' : 'Delete $n branches…'),
        ),
      ],
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
  );

  Widget _row(CleanupBranch b) => InkWell(
    key: ValueKey('cleanup-${b.name}'),
    onTap: () => _toggle(b.name),
    borderRadius: BorderRadius.circular(4),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
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
