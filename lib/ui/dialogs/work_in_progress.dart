import 'package:flutter/widgets.dart';

import '../repo/repo_tab_controller.dart';
import 'dialogs.dart';

enum _WipChoice { stash, discard, keep, cancel }

/// Uncommitted changes to tracked files (untracked files don't get in the
/// way of a rebase or reset, and are left alone).
int trackedChanges(RepoTabController tab) =>
    tab.status.entries.where((e) => !e.isUntracked).length;

/// Before [action] (e.g. "rebase"), if tracked files have uncommitted
/// changes, asks whether to stash or discard them, or cancel. [allowKeep]
/// also offers to leave them (for a soft or mixed reset, which keeps them).
/// Returns true if the action can go ahead.
Future<bool> resolveWorkInProgress(
  BuildContext context,
  RepoTabController tab, {
  required String action,
  bool allowKeep = false,
}) async {
  final n = trackedChanges(tab);
  if (n == 0) return true;
  final choice = await chooseOption<_WipChoice>(
    context,
    title: 'Uncommitted changes',
    message:
        '$n file${n == 1 ? ' has' : 's have'} uncommitted changes. '
        'What should happen to them before the $action?',
    options: [
      (
        _WipChoice.stash,
        'Stash changes',
        'Save them in a new stash and continue. Pop the stash afterwards '
            'to get them back.',
      ),
      (
        _WipChoice.discard,
        'Discard changes',
        'Throw them away and continue. Cannot be undone.',
      ),
      if (allowKeep)
        (
          _WipChoice.keep,
          'Keep changes',
          'Leave them in the working tree; the $action keeps them.',
        ),
      (_WipChoice.cancel, 'Cancel', 'Leave everything as it is.'),
    ],
  );
  if (!context.mounted) return false;
  switch (choice) {
    case _WipChoice.stash:
      return tab.run(
        'Stash',
        () => tab.repo.stashPush(
          message: 'Before $action',
          includeUntracked: false,
        ),
        success: 'Changes stashed ("Before $action")',
      );
    case _WipChoice.discard:
      final ok = await confirm(
        context,
        title: 'Discard changes',
        message:
            'Discard the uncommitted changes to $n file${n == 1 ? '' : 's'}? '
            'This cannot be undone.',
        confirmLabel: 'Discard',
        danger: true,
      );
      if (!ok) return false;
      return tab.run('Discard', tab.repo.discardTracked);
    case _WipChoice.keep:
      return true;
    case _WipChoice.cancel || null:
      return false;
  }
}
