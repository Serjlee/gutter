import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../git/models.dart';
import '../../git/rebase_plan.dart';
import '../../git/repository.dart';
import '../dialogs/dialogs.dart';
import '../dialogs/interactive_rebase_dialog.dart';
import '../widgets/common.dart';
import 'repo_tab_controller.dart';

/// Commands that need user interaction (dialogs, confirmations) shared by
/// the graph, sidebar and toolbar.
class RepoActions {
  RepoActions(this.context, this.tab);

  final BuildContext context;
  final RepoTabController tab;

  Repository get repo => tab.repo;

  String _short(String sha) => sha.length > 7 ? sha.substring(0, 7) : sha;

  // ------------------------------------------------------------ branches

  Future<void> checkoutRef(GitRef ref) async {
    if (ref.type == RefType.remoteBranch) {
      RemoteCheckout? result;
      final ok = await tab.run(
        'Checkout',
        () async => result = await repo.checkoutRemote(ref, tab.refs),
      );
      final local = ref.remoteBranchName;
      if (!ok) return;
      switch (result) {
        case RemoteCheckout.fastForwarded:
          tab.app.notify('Updated $local to ${ref.name}');
        case RemoteCheckout.diverged:
          tab.app.notify(
            '$local and ${ref.name} have diverged: pull to merge or rebase',
          );
        case RemoteCheckout.ahead:
          tab.app.notify('$local is ahead of ${ref.name}');
        case RemoteCheckout.created || RemoteCheckout.upToDate || null:
          break;
      }
    } else if (ref.type == RefType.localBranch) {
      await tab.run('Checkout', () => repo.checkout(ref.name));
    } else {
      await checkoutDetached(ref.sha);
    }
  }

  Future<void> checkoutDetached(String sha) async {
    final ok = await confirm(
      context,
      title: 'Checkout commit',
      message: 'Check out ${_short(sha)} in detached HEAD state?',
      confirmLabel: 'Checkout',
    );
    if (ok) await tab.run('Checkout', () => repo.checkout(sha));
  }

  Future<void> createBranch({String? at}) async {
    final r = await promptFields(
      context,
      title: at == null ? 'Create branch' : 'Create branch at ${_short(at)}',
      fields: const [FieldSpec('Branch name')],
      confirmLabel: 'Create and checkout',
      validate: (v) => validateRefName(v.first),
    );
    if (r == null) return;
    await tab.run(
      'Create branch',
      () => repo.createBranch(r.first.trim(), startPoint: at),
    );
  }

  Future<void> renameBranch(GitRef ref) async {
    final name = await promptText(
      context,
      title: 'Rename branch',
      label: 'New name',
      initial: ref.name,
      confirmLabel: 'Rename',
    );
    if (name == null || name.trim() == ref.name) return;
    final err = validateRefName(name);
    if (err != null) {
      tab.app.notify(err, error: true);
      return;
    }
    await tab.run('Rename', () => repo.renameBranch(ref.name, name.trim()));
  }

  Future<void> deleteBranch(GitRef ref) async {
    if (ref.type == RefType.remoteBranch) {
      final ok = await confirm(
        context,
        title: 'Delete remote branch',
        message:
            'Delete ${ref.remoteBranchName} on ${ref.remote}? This affects everyone using that remote.',
        confirmLabel: 'Delete',
        danger: true,
      );
      if (ok) {
        await tab.run(
          'Delete remote branch',
          () => repo.deleteRemoteBranch(ref.remote, ref.remoteBranchName),
        );
      }
      return;
    }
    final ok = await confirm(
      context,
      title: 'Delete branch',
      message: 'Delete local branch ${ref.name}?',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (!ok) return;
    final success = await tab.run(
      'Delete branch',
      () => repo.deleteBranch(ref.name),
    );
    if (!success && context.mounted) {
      final force = await confirm(
        context,
        title: 'Branch not fully merged',
        message:
            '${ref.name} has commits that are not merged. Force delete it?',
        confirmLabel: 'Force delete',
        danger: true,
      );
      if (force) {
        await tab.run(
          'Delete branch',
          () => repo.deleteBranch(ref.name, force: true),
        );
      }
    }
  }

  Future<void> setUpstream(GitRef local) async {
    final remotes = tab.refs
        .where((r) => r.type == RefType.remoteBranch && !r.isRemoteHead)
        .toList();
    if (remotes.isEmpty) {
      tab.app.notify('No remote branches', error: true);
      return;
    }
    final choice = await chooseOption<String>(
      context,
      title: 'Set upstream of ${local.name}',
      options: [for (final r in remotes) (r.name, r.name, _short(r.sha))],
    );
    if (choice != null) {
      await tab.run('Set upstream', () => repo.setUpstream(local.name, choice));
    }
  }

  // --------------------------------------------------------------- merge

  Future<void> merge(String ref, String label) async {
    final branch = tab.currentBranch ?? 'HEAD';
    final mode = await chooseOption<MergeMode>(
      context,
      title: 'Merge $label into $branch',
      options: const [
        (
          MergeMode.auto,
          'Merge',
          'Fast-forward when possible, otherwise create a merge commit.',
        ),
        (
          MergeMode.noFastForward,
          'Merge (no fast-forward)',
          'Always create a merge commit.',
        ),
        (
          MergeMode.fastForwardOnly,
          'Fast-forward only',
          'Refuse if a merge commit would be needed.',
        ),
        (
          MergeMode.squash,
          'Squash',
          'Stage the combined changes without committing.',
        ),
      ],
    );
    if (mode == null) return;
    await tab.run('Merge', () => repo.merge(ref, mode: mode));
  }

  Future<void> rebaseOnto(String ref, String label) async {
    final branch = tab.currentBranch ?? 'HEAD';
    final ok = await confirm(
      context,
      title: 'Rebase',
      message: 'Rebase $branch onto $label?',
      confirmLabel: 'Rebase',
    );
    if (ok) await tab.run('Rebase', () => repo.rebase(ref));
  }

  /// Interactive rebase of [commit] and its descendants up to HEAD.
  Future<void> interactiveRebaseIncluding(Commit commit) async {
    final String? baseRef = commit.parents.isEmpty
        ? null
        : commit.parents.first;
    await showInteractiveRebase(
      context,
      tab,
      baseRef,
      baseLabel: baseRef == null ? 'root' : _short(baseRef),
    );
  }

  // ------------------------------------------------------------- commits

  Future<void> cherryPick(Commit c) async {
    final ok = await confirm(
      context,
      title: 'Cherry-pick',
      message:
          'Apply ${_short(c.sha)} "${c.subject}" onto ${tab.currentBranch ?? 'HEAD'}?',
      confirmLabel: 'Cherry-pick',
    );
    if (ok) await tab.run('Cherry-pick', () => repo.cherryPick(c));
  }

  /// Cherry-picks the multi-selected commits, oldest first.
  Future<void> cherryPickSelected() async {
    final commits = tab.selectedCommits;
    if (commits.isEmpty) return;
    final branch = tab.currentBranch ?? 'HEAD';
    final ok = await confirm(
      context,
      title: 'Cherry-pick ${commits.length} commits',
      message:
          'Apply these commits onto $branch, oldest first?\n\n'
          '${commits.map((c) => '${_short(c.sha)}  ${c.subject}').join('\n')}',
      confirmLabel: 'Cherry-pick',
    );
    if (!ok) return;
    final done = await tab.run(
      'Cherry-pick',
      () => repo.cherryPickAll(commits),
      success: 'Cherry-picked ${commits.length} commits onto $branch',
    );
    if (done) tab.clearMultiSelection();
  }

  /// Squashes the multi-selected commits into the oldest of them, through
  /// the interactive rebase dialog (preset, so the message can be edited).
  /// They must be consecutive commits of the current branch.
  Future<void> squashSelected() async {
    final commits = tab.selectedCommits; // oldest first
    if (commits.length < 2) return;
    final oldest = commits.first;
    final base = oldest.parents.isEmpty ? null : oldest.parents.first;
    final shas = {for (final c in commits) c.sha};
    await showInteractiveRebase(
      context,
      tab,
      base,
      baseLabel: base == null ? 'root' : _short(base),
      initialSelection: shas,
      prepare: (steps) {
        if (presetSquash(steps, shas)) return true;
        tab.app.notify(
          'Only consecutive commits of ${tab.currentBranch ?? 'HEAD'} '
          '(without merges) can be squashed together.',
          error: true,
        );
        return false;
      },
    );
  }

  List<PopupMenuEntry<VoidCallback>> multiCommitMenu() {
    final commits = tab.selectedCommits;
    final n = commits.length;
    return [
      menuItem(
        'Cherry-pick $n commits',
        cherryPickSelected,
        icon: Icons.content_copy,
      ),
      menuItem(
        'Squash $n commits…',
        squashSelected,
        icon: Icons.merge,
        enabled: tab.operation == RepoOperation.none,
      ),
      const PopupMenuDivider(),
      menuItem(
        'Copy SHAs',
        () => copyToClipboard(
          context,
          commits.reversed.map((c) => c.sha).join('\n'),
        ),
        icon: Icons.tag,
      ),
      menuItem(
        'Clear selection',
        tab.clearMultiSelection,
        icon: Icons.deselect,
      ),
    ];
  }

  Future<void> revert(Commit c) async {
    final ok = await confirm(
      context,
      title: 'Revert commit',
      message: 'Create a new commit reverting ${_short(c.sha)} "${c.subject}"?',
      confirmLabel: 'Revert',
    );
    if (ok) await tab.run('Revert', () => repo.revert(c));
  }

  Future<void> reset(Commit c, [ResetMode? mode]) async {
    final branch = tab.currentBranch ?? 'HEAD';
    final m =
        mode ??
        await chooseOption<ResetMode>(
          context,
          title: 'Reset $branch to ${_short(c.sha)}',
          options: const [
            (ResetMode.soft, 'Soft', 'Keep all changes staged.'),
            (
              ResetMode.mixed,
              'Mixed',
              'Keep changes in the working tree, unstaged.',
            ),
            (ResetMode.hard, 'Hard', 'Discard all changes. Cannot be undone.'),
          ],
        );
    if (m == null || !context.mounted) return;
    if (m == ResetMode.hard) {
      final ok = await confirm(
        context,
        title: 'Hard reset',
        message:
            'Reset $branch to ${_short(c.sha)} and discard all uncommitted changes?',
        confirmLabel: 'Reset hard',
        danger: true,
      );
      if (!ok) return;
    }
    await tab.run('Reset', () => repo.reset(c.sha, m));
  }

  Future<void> createTag(String sha) async {
    final r = await promptFields(
      context,
      title: 'Create tag at ${_short(sha)}',
      fields: const [
        FieldSpec('Tag name'),
        FieldSpec(
          'Message',
          optional: true,
          multiline: true,
          hint: 'Annotated tag message',
        ),
      ],
      confirmLabel: 'Create tag',
      validate: (v) => validateRefName(v.first),
    );
    if (r == null) return;
    await tab.run('Tag', () => repo.createTag(r[0].trim(), sha, message: r[1]));
  }

  Future<void> deleteTag(GitRef tag) async {
    final ok = await confirm(
      context,
      title: 'Delete tag',
      message: 'Delete local tag ${tag.name}?',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (ok) await tab.run('Delete tag', () => repo.deleteTag(tag.name));
  }

  Future<void> pushTag(GitRef tag) async {
    final remote = _defaultRemote();
    if (remote == null) return;
    await tab.run(
      'Push tag',
      () => repo.pushTag(remote, tag.name),
      success: 'Pushed tag ${tag.name} to $remote',
    );
  }

  Future<void> deleteRemoteTag(GitRef tag) async {
    final remote = _defaultRemote();
    if (remote == null) return;
    final ok = await confirm(
      context,
      title: 'Delete remote tag',
      message: 'Delete tag ${tag.name} on $remote?',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (ok) {
      await tab.run(
        'Delete remote tag',
        () => repo.deleteRemoteTag(remote, tag.name),
      );
    }
  }

  String? _defaultRemote() {
    if (tab.remotes.isEmpty) {
      tab.app.notify('No remote configured', error: true);
      return null;
    }
    return tab.remotes.any((r) => r.name == 'origin')
        ? 'origin'
        : tab.remotes.first.name;
  }

  // --------------------------------------------------------------- stash

  Future<void> stash() async {
    if (tab.status.isClean) {
      tab.app.notify('Nothing to stash');
      return;
    }
    final msg = await promptText(
      context,
      title: 'Stash changes',
      label: 'Message',
      hint: 'What you were working on',
      optional: true,
      confirmLabel: 'Stash',
    );
    if (msg == null) return;
    await tab.run('Stash', () => repo.stashPush(message: msg));
  }

  Future<void> popStash([int index = 0]) async {
    if (tab.stashes.isEmpty) {
      tab.app.notify('No stashes');
      return;
    }
    await tab.run('Pop stash', () => repo.stashPop(index));
  }

  Future<void> dropStash(StashEntry s) async {
    final ok = await confirm(
      context,
      title: 'Delete stash',
      message: 'Delete ${s.ref} "${s.message}"?',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (ok) await tab.run('Drop stash', () => repo.stashDrop(s.index));
  }

  /// Pushes; if the remote rejects it because it has commits the branch
  /// doesn't, offers a force push.
  Future<void> push() async {
    if (await tab.push() != PushOutcome.rejected) return;
    if (!context.mounted) return;
    final branch = tab.currentBranch;
    final target = tab.status.branch.upstream ?? 'The remote branch';
    final ok = await confirm(
      context,
      title: 'Push rejected',
      message:
          '$target has commits that aren\'t in your local $branch. '
          'Force push (with lease) to replace it with your branch? '
          'Those remote commits will be lost.\n\n'
          'To keep them, cancel and pull first.',
      confirmLabel: 'Force push',
      danger: true,
    );
    if (ok) await tab.push(force: true);
  }

  Future<void> forcePush() async {
    final ok = await confirm(
      context,
      title: 'Force push',
      message:
          'Force push ${tab.currentBranch} (with lease)? Remote commits not in your branch will be lost.',
      confirmLabel: 'Force push',
      danger: true,
    );
    if (ok) await tab.push(force: true);
  }

  Future<void> discard(List<StatusEntry> entries) async {
    if (entries.isEmpty) return;
    final ok = await confirm(
      context,
      title: 'Discard changes',
      message: entries.length == 1
          ? 'Discard all changes to ${entries.first.path}? This cannot be undone.'
          : 'Discard changes to ${entries.length} files? This cannot be undone.',
      confirmLabel: 'Discard',
      danger: true,
    );
    if (ok) await tab.discardEntries(entries);
  }

  // --------------------------------------------------------------- menus

  List<GitRef> refsAt(String sha) => tab.refsBySha[sha] ?? const [];

  List<PopupMenuEntry<VoidCallback>> commitMenu(Commit c) {
    final isHead = c.sha == tab.headSha;
    final branch = tab.currentBranch;
    final refs = refsAt(c.sha);
    final localBranches = refs
        .where((r) => r.type == RefType.localBranch)
        .toList();
    return [
      for (final b in localBranches.where((b) => !b.isHead))
        menuItem('Checkout ${b.name}', () => checkoutRef(b), icon: Icons.login),
      if (!isHead)
        menuItem(
          'Checkout this commit (detached)',
          () => checkoutDetached(c.sha),
          icon: Icons.adjust,
        ),
      menuItem(
        'Create branch here',
        () => createBranch(at: c.sha),
        icon: Icons.call_split,
      ),
      menuItem(
        'Create tag here',
        () => createTag(c.sha),
        icon: Icons.sell_outlined,
      ),
      const PopupMenuDivider(),
      if (!isHead) ...[
        menuItem(
          'Merge into ${branch ?? 'HEAD'}',
          () => merge(c.sha, _short(c.sha)),
          icon: Icons.merge,
        ),
        menuItem(
          'Rebase ${branch ?? 'HEAD'} onto this',
          () => rebaseOnto(c.sha, _short(c.sha)),
          icon: Icons.low_priority,
        ),
        menuItem(
          'Cherry-pick commit',
          () => cherryPick(c),
          icon: Icons.content_copy,
        ),
      ],
      menuItem(
        'Interactive rebase from here…',
        () => interactiveRebaseIncluding(c),
        icon: Icons.format_list_numbered,
        enabled: tab.operation == RepoOperation.none,
      ),
      menuItem('Revert commit', () => revert(c), icon: Icons.undo),
      if (branch != null || !isHead) ...[
        const PopupMenuDivider(),
        menuItem(
          'Reset ${branch ?? 'HEAD'} to this commit…',
          () => reset(c),
          icon: Icons.restore,
        ),
      ],
      const PopupMenuDivider(),
      menuItem(
        'Copy commit SHA',
        () => copyToClipboard(context, c.sha),
        icon: Icons.tag,
      ),
      menuItem(
        'Copy commit message',
        () => copyToClipboard(context, c.subject),
        icon: Icons.notes,
      ),
    ];
  }

  List<PopupMenuEntry<VoidCallback>> refMenu(GitRef ref) {
    final branch = tab.currentBranch ?? 'HEAD';
    switch (ref.type) {
      case RefType.localBranch:
        return [
          if (!ref.isHead)
            menuItem(
              'Checkout ${ref.name}',
              () => checkoutRef(ref),
              icon: Icons.login,
            ),
          if (!ref.isHead) ...[
            menuItem(
              'Merge ${ref.name} into $branch',
              () => merge(ref.name, ref.name),
              icon: Icons.merge,
            ),
            menuItem(
              'Rebase $branch onto ${ref.name}',
              () => rebaseOnto(ref.name, ref.name),
              icon: Icons.low_priority,
            ),
          ],
          const PopupMenuDivider(),
          menuItem(
            'Create branch here',
            () => createBranch(at: ref.name),
            icon: Icons.call_split,
          ),
          menuItem(
            'Rename…',
            () => renameBranch(ref),
            icon: Icons.drive_file_rename_outline,
          ),
          menuItem(
            'Set upstream…',
            () => setUpstream(ref),
            icon: Icons.cloud_outlined,
          ),
          if (!ref.isHead)
            menuItem(
              'Delete ${ref.name}',
              () => deleteBranch(ref),
              icon: Icons.delete_outline,
              danger: true,
            ),
          const PopupMenuDivider(),
          menuItem(
            'Copy branch name',
            () => copyToClipboard(context, ref.name),
            icon: Icons.copy,
          ),
        ];
      case RefType.remoteBranch:
        return [
          menuItem(
            'Checkout ${ref.remoteBranchName}',
            () => checkoutRef(ref),
            icon: Icons.login,
          ),
          menuItem(
            'Merge ${ref.name} into $branch',
            () => merge(ref.name, ref.name),
            icon: Icons.merge,
          ),
          menuItem(
            'Rebase $branch onto ${ref.name}',
            () => rebaseOnto(ref.name, ref.name),
            icon: Icons.low_priority,
          ),
          menuItem(
            'Create branch here',
            () => createBranch(at: ref.name),
            icon: Icons.call_split,
          ),
          const PopupMenuDivider(),
          menuItem(
            'Delete ${ref.name} on remote',
            () => deleteBranch(ref),
            icon: Icons.delete_outline,
            danger: true,
          ),
          menuItem(
            'Copy branch name',
            () => copyToClipboard(context, ref.name),
            icon: Icons.copy,
          ),
        ];
      case RefType.tag:
        return [
          menuItem(
            'Checkout tag (detached)',
            () => checkoutDetached(ref.sha),
            icon: Icons.login,
          ),
          menuItem(
            'Create branch here',
            () => createBranch(at: ref.sha),
            icon: Icons.call_split,
          ),
          menuItem('Push tag', () => pushTag(ref), icon: Icons.cloud_upload),
          const PopupMenuDivider(),
          menuItem(
            'Delete tag',
            () => deleteTag(ref),
            icon: Icons.delete_outline,
            danger: true,
          ),
          menuItem(
            'Delete tag on remote',
            () => deleteRemoteTag(ref),
            icon: Icons.cloud_off,
            danger: true,
          ),
        ];
      case RefType.stash:
      case RefType.head:
        return const [];
    }
  }

  List<PopupMenuEntry<VoidCallback>> stashMenu(StashEntry s) => [
    menuItem(
      'Apply stash',
      () => tab.run('Apply stash', () => repo.stashApply(s.index)),
      icon: Icons.unarchive_outlined,
    ),
    menuItem('Pop stash', () => popStash(s.index), icon: Icons.outbox),
    const PopupMenuDivider(),
    menuItem(
      'Delete stash',
      () => dropStash(s),
      icon: Icons.delete_outline,
      danger: true,
    ),
  ];
}

/// Label chip for a ref kind.
Color refColor(RefType t) => switch (t) {
  RefType.localBranch => AppColors.localBranch,
  RefType.remoteBranch => AppColors.remoteBranch,
  RefType.tag => AppColors.tag,
  _ => AppColors.textDim,
};
