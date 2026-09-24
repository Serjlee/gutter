import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../git/models.dart';
import '../repo/repo_actions.dart';
import '../repo/repo_tab_controller.dart';
import '../widgets/common.dart';

/// Right-hand panel: WIP (staging + commit) or commit details.
class DetailsPanel extends StatelessWidget {
  const DetailsPanel({super.key, required this.tab});
  final RepoTabController tab;

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (tab.selectedSha == wipSha || (tab.selectedSha == null && tab.isDirty)) {
      child = WipPanel(tab: tab);
    } else if (tab.selectedSha != null) {
      child = CommitDetailsPanel(tab: tab);
    } else {
      child = const Center(
        child: Text(
          'Select a commit',
          style: TextStyle(color: AppColors.textDim),
        ),
      );
    }
    return Container(color: AppColors.panel, child: child);
  }
}

class CommitDetailsPanel extends StatelessWidget {
  const CommitDetailsPanel({super.key, required this.tab});
  final RepoTabController tab;

  @override
  Widget build(BuildContext context) {
    final d = tab.details;
    if (d == null) {
      return Center(
        child: tab.detailsLoading
            ? const CircularProgressIndicator()
            : const Text(
                'No details',
                style: TextStyle(color: AppColors.textDim),
              ),
      );
    }
    final row = tab.graph.rowOf(d.sha);
    final commit = row == null ? null : tab.graph.commitAt(row);
    final refs = tab.refsBySha[d.sha] ?? const <GitRef>[];
    final authorDate = DateTime.fromMillisecondsSinceEpoch(d.authorTime * 1000);
    final differentCommitter =
        d.committerEmail != d.authorEmail || d.committerName != d.authorName;
    final files = tab.commitFiles;
    final selectedPath = tab.diffTarget is CommitFileTarget
        ? tab.diffTarget!.path
        : null;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 4,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'commit ',
                    style: monoStyle(size: 12, color: AppColors.textDim),
                  ),
                  InkWell(
                    onTap: () => copyToClipboard(context, d.sha),
                    child: Tooltip(
                      message: 'Copy full SHA',
                      child: Text(
                        d.sha.substring(0, 10),
                        style: monoStyle(size: 12, color: AppColors.accent),
                      ),
                    ),
                  ),
                ],
              ),
              if (d.parents.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      d.parents.length > 1 ? 'parents ' : 'parent ',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textDim,
                      ),
                    ),
                    for (final p in d.parents)
                      InkWell(
                        onTap: () => tab.jumpToSha(p),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text(
                            p.substring(0, 7),
                            style: monoStyle(size: 12, color: AppColors.accent),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: SelectableText(
            d.subject,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        if (d.body.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: SelectableText(
              d.body,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textDim,
                height: 1.4,
              ),
            ),
          ),
        if (refs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final r in refs.where((r) => !r.isRemoteHead))
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: refColor(r.type).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      r.name,
                      style: TextStyle(fontSize: 11.5, color: refColor(r.type)),
                    ),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Row(
            children: [
              _Avatar(name: d.authorName, sha: d.sha),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${d.authorName} <${d.authorEmail}>',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    Text(
                      'authored ${formatDate(authorDate)}'
                      '${differentCommitter ? ' · committed by ${d.committerName}' : ''}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SectionHeader(title: '${files.length} changed files'),
        if (tab.detailsLoading) const LinearProgressIndicator(minHeight: 2),
        if (commit != null)
          for (final f in files)
            _FileRow(
              kind: f.kind,
              path: f.path,
              oldPath: f.oldPath,
              selected: selectedPath == f.path,
              onTap: () => tab.openCommitFile(commit, f),
            ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.sha});
  final String name;
  final String sha;

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final initials = parts.isEmpty || parts.first.isEmpty
        ? '?'
        : (parts.first[0] + (parts.length > 1 ? parts.last[0] : ''))
              .toUpperCase();
    final color = AppColors.lane(name.hashCode.abs());
    return CircleAvatar(
      radius: 16,
      backgroundColor: color.withValues(alpha: 0.8),
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _FileRow extends StatefulWidget {
  const _FileRow({
    required this.kind,
    required this.path,
    this.oldPath,
    required this.selected,
    required this.onTap,
    this.actions = const [],
    this.onSecondaryTap,
  });

  final ChangeKind kind;
  final String path;
  final String? oldPath;
  final bool selected;
  final VoidCallback onTap;
  final List<Widget> actions;
  final void Function(Offset)? onSecondaryTap;

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onSecondaryTapUp: widget.onSecondaryTap == null
            ? null
            : (d) => widget.onSecondaryTap!(d.globalPosition),
        child: Container(
          height: 28,
          color: widget.selected
              ? AppColors.selection
              : (_hover ? AppColors.hover : null),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              ChangeKindBadge(widget.kind),
              const SizedBox(width: 8),
              Expanded(child: PathLabel(widget.path, oldPath: widget.oldPath)),
              if (_hover || widget.selected) ...widget.actions,
            ],
          ),
        ),
      ),
    );
  }
}

/// Staging area and commit composer.
class WipPanel extends StatelessWidget {
  const WipPanel({super.key, required this.tab});
  final RepoTabController tab;

  @override
  Widget build(BuildContext context) {
    final actions = RepoActions(context, tab);
    final s = tab.status;
    final conflicts = s.conflicted;
    final unstaged = s.unstaged.where((e) => !e.conflicted).toList();
    final staged = s.staged;
    final target = tab.diffTarget;

    bool isSel(StatusEntry e, bool st) =>
        target is WorkingFileTarget &&
        target.entry.path == e.path &&
        target.staged == st;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  s.isClean
                      ? 'No changes'
                      : '${s.entries.length} file change${s.entries.length == 1 ? '' : 's'}'
                            ' on ${tab.currentBranch ?? 'detached HEAD'}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (unstaged.isNotEmpty)
                SmallIconButton(
                  icon: Icons.delete_sweep_outlined,
                  tooltip: 'Discard all changes',
                  color: AppColors.danger,
                  onPressed: () => actions.discard(unstaged),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              if (conflicts.isNotEmpty) ...[
                SectionHeader(title: 'Conflicts', count: conflicts.length),
                for (final e in conflicts)
                  _FileRow(
                    kind: ChangeKind.conflicted,
                    path: e.path,
                    selected: isSel(e, false),
                    onTap: () => tab.openWorkingFile(e, staged: false),
                    actions: [
                      SmallIconButton(
                        icon: Icons.person_outline,
                        tooltip: 'Use ours (${e.conflictCode})',
                        onPressed: () => tab.run(
                          'Resolve',
                          () => tab.repo.resolveWith(e.path, ours: true),
                        ),
                      ),
                      SmallIconButton(
                        icon: Icons.people_outline,
                        tooltip: 'Use theirs',
                        onPressed: () => tab.run(
                          'Resolve',
                          () => tab.repo.resolveWith(e.path, ours: false),
                        ),
                      ),
                      SmallIconButton(
                        icon: Icons.check,
                        tooltip: 'Mark resolved (stage file as is)',
                        color: AppColors.success,
                        onPressed: () => tab.run(
                          'Resolve',
                          () => tab.repo.markResolved([e.path]),
                        ),
                      ),
                      SmallIconButton(
                        icon: Icons.open_in_new,
                        tooltip: 'Open in external editor',
                        onPressed: () => openExternally(tab, e.path),
                      ),
                    ],
                  ),
              ],
              SectionHeader(
                title: 'Unstaged files',
                count: unstaged.length,
                actions: [
                  TextButton(
                    onPressed: unstaged.isEmpty
                        ? null
                        : () => tab.stageEntries(unstaged),
                    child: const Text(
                      'Stage all',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              for (final e in unstaged)
                _FileRow(
                  kind: e.worktree ?? ChangeKind.modified,
                  path: e.path,
                  selected: isSel(e, false),
                  onTap: () => tab.openWorkingFile(e, staged: false),
                  onSecondaryTap: (pos) => showContextMenu(context, pos, [
                    menuItem(
                      'Stage',
                      () => tab.stageEntries([e]),
                      icon: Icons.add,
                    ),
                    menuItem(
                      'Discard changes',
                      () => actions.discard([e]),
                      icon: Icons.delete_outline,
                      danger: true,
                    ),
                    menuItem(
                      'Open in external editor',
                      () => openExternally(tab, e.path),
                      icon: Icons.open_in_new,
                    ),
                    menuItem(
                      'Copy path',
                      () => copyToClipboard(context, e.path),
                      icon: Icons.copy,
                    ),
                  ]),
                  actions: [
                    SmallIconButton(
                      icon: Icons.delete_outline,
                      tooltip: 'Discard',
                      color: AppColors.danger,
                      onPressed: () => actions.discard([e]),
                    ),
                    SmallIconButton(
                      icon: Icons.add_circle_outline,
                      tooltip: 'Stage file',
                      color: AppColors.success,
                      onPressed: () => tab.stageEntries([e]),
                    ),
                  ],
                ),
              SectionHeader(
                title: 'Staged files',
                count: staged.length,
                actions: [
                  TextButton(
                    onPressed: staged.isEmpty
                        ? null
                        : () => tab.run('Unstage', tab.repo.unstageAll),
                    child: const Text(
                      'Unstage all',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              for (final e in staged)
                _FileRow(
                  kind: e.index ?? ChangeKind.modified,
                  path: e.path,
                  oldPath: e.oldPath,
                  selected: isSel(e, true),
                  onTap: () => tab.openWorkingFile(e, staged: true),
                  onSecondaryTap: (pos) => showContextMenu(context, pos, [
                    menuItem(
                      'Unstage',
                      () => tab.unstageEntries([e]),
                      icon: Icons.remove,
                    ),
                    menuItem(
                      'Copy path',
                      () => copyToClipboard(context, e.path),
                      icon: Icons.copy,
                    ),
                  ]),
                  actions: [
                    SmallIconButton(
                      icon: Icons.remove_circle_outline,
                      tooltip: 'Unstage file',
                      color: AppColors.warning,
                      onPressed: () => tab.unstageEntries([e]),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const Divider(),
        _CommitComposer(tab: tab),
      ],
    );
  }
}

class _CommitComposer extends StatelessWidget {
  const _CommitComposer({required this.tab});
  final RepoTabController tab;

  @override
  Widget build(BuildContext context) {
    final stagedCount = tab.status.staged.length;
    final canCommit = (stagedCount > 0 || tab.amend) && tab.busy == null;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CallbackShortcuts(
            bindings: {
              const SingleActivator(
                LogicalKeyboardKey.enter,
                control: true,
              ): () =>
                  unawaited(tab.commit()),
              const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
                  unawaited(tab.commit()),
            },
            child: TextField(
              controller: tab.commitMessage,
              minLines: 4,
              maxLines: 10,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Commit message\n\nFirst line is the summary. Ctrl+Enter to commit.',
                hintMaxLines: 4,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              SizedBox(
                height: 24,
                width: 24,
                child: Checkbox(
                  value: tab.amend,
                  onChanged: (v) => tab.setAmend(v ?? false),
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'Amend previous commit',
                style: TextStyle(fontSize: 12.5),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: canCommit ? () => tab.commit() : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.success,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text(
              tab.amend
                  ? 'Amend commit'
                  : (stagedCount == 0
                        ? 'Stage files to commit'
                        : 'Commit $stagedCount file${stagedCount == 1 ? '' : 's'}'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens a working tree file with the platform's default application.
Future<void> openExternally(RepoTabController tab, String relPath) async {
  final full = '${tab.repo.path}/$relPath';
  try {
    await openWithSystem(full);
  } catch (e) {
    tab.app.notify('Could not open $relPath: $e', error: true);
  }
}
