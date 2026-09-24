import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../git/models.dart';
import '../repo/repo_actions.dart';
import '../repo/repo_tab_controller.dart';
import '../widgets/common.dart';
import 'file_tree.dart';

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
    this.depth = 0,
    this.nameOnly = false,
  });

  final ChangeKind kind;
  final String path;
  final String? oldPath;
  final bool selected;
  final VoidCallback onTap;
  final List<Widget> actions;
  final void Function(Offset)? onSecondaryTap;

  /// Tree nesting level; with [nameOnly] only the file name is shown.
  final int depth;
  final bool nameOnly;

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
          padding: EdgeInsets.only(
            left: 12 + widget.depth * _treeIndent,
            right: 12,
          ),
          child: Row(
            children: [
              if (widget.nameOnly) const SizedBox(width: 18),
              ChangeKindBadge(widget.kind),
              const SizedBox(width: 8),
              Expanded(
                child: PathLabel(
                  widget.nameOnly
                      ? widget.path.substring(widget.path.lastIndexOf('/') + 1)
                      : widget.path,
                  oldPath: widget.oldPath,
                ),
              ),
              if (_hover || widget.selected) ...widget.actions,
            ],
          ),
        ),
      ),
    );
  }
}

/// Which list a working-tree file row belongs to.
enum _WipSection { conflicts, unstaged, staged }

const _treeIndent = 16.0;

/// One row of the staging list: a section header, a folder (tree mode) or
/// a file.
class _WipItem {
  const _WipItem.header(this.section)
    : entry = null,
      dir = null,
      depth = 0,
      nameOnly = false;
  const _WipItem.file(
    this.section,
    StatusEntry this.entry, {
    this.depth = 0,
    this.nameOnly = false,
  }) : dir = null;
  _WipItem.dir(this.section, FileTreeRow<StatusEntry> this.dir)
    : entry = null,
      depth = dir.depth,
      nameOnly = false;

  final _WipSection section;
  final StatusEntry? entry;
  final FileTreeRow<StatusEntry>? dir;
  final int depth;
  final bool nameOnly;
}

/// Staging area and commit composer.
class WipPanel extends StatelessWidget {
  const WipPanel({super.key, required this.tab});
  final RepoTabController tab;

  @override
  Widget build(BuildContext context) {
    final s = tab.status;
    final conflicts = <StatusEntry>[];
    final unstaged = <StatusEntry>[];
    final staged = <StatusEntry>[];
    for (final e in s.entries) {
      if (e.conflicted) {
        conflicts.add(e);
        continue;
      }
      if (e.hasUnstaged) unstaged.add(e);
      if (e.hasStaged) staged.add(e);
    }

    // Flat item list for a lazily built ListView: large working trees
    // (thousands of changes) only build the visible rows.
    final tree = tab.app.settings.fileTree;
    final items = <_WipItem>[];
    void addFiles(_WipSection section, List<StatusEntry> files) {
      if (!tree) {
        for (final e in files) {
          items.add(_WipItem.file(section, e));
        }
        return;
      }
      final prefix = '${section.name}:';
      final collapsed = <String>{
        for (final k in tab.collapsedDirs)
          if (k.startsWith(prefix)) k.substring(prefix.length),
      };
      final rows = flattenFileTree(files, (e) => e.path, collapsed: collapsed);
      for (final row in rows) {
        final entry = row.item;
        items.add(
          entry == null
              ? _WipItem.dir(section, row)
              : _WipItem.file(section, entry, depth: row.depth, nameOnly: true),
        );
      }
    }

    if (conflicts.isNotEmpty) {
      items.add(const _WipItem.header(_WipSection.conflicts));
      addFiles(_WipSection.conflicts, conflicts);
    }
    items.add(const _WipItem.header(_WipSection.unstaged));
    addFiles(_WipSection.unstaged, unstaged);
    items.add(const _WipItem.header(_WipSection.staged));
    addFiles(_WipSection.staged, staged);

    final actions = RepoActions(context, tab);
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
                      : '${s.entries.length} file change'
                            '${s.entries.length == 1 ? '' : 's'}'
                            ' on ${tab.currentBranch ?? 'detached HEAD'}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SmallIconButton(
                key: const ValueKey('file-view-toggle'),
                icon: tree
                    ? Icons.format_list_bulleted
                    : Icons.account_tree_outlined,
                tooltip: tree ? 'Show files as a list' : 'Show files as a tree',
                onPressed: () => tab.app.setFileTree(!tree),
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
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              final dir = item.dir;
              if (dir != null) {
                final files = switch (item.section) {
                  _WipSection.conflicts => conflicts,
                  _WipSection.unstaged => unstaged,
                  _WipSection.staged => staged,
                };
                return _dirRow(context, actions, item.section, dir, files);
              }
              final entry = item.entry;
              if (entry == null) {
                return _header(item.section, conflicts, unstaged, staged);
              }
              return _fileRow(
                context,
                actions,
                item.section,
                entry,
                depth: item.depth,
                nameOnly: item.nameOnly,
              );
            },
          ),
        ),
        const Divider(),
        _CommitComposer(tab: tab),
      ],
    );
  }

  Widget _header(
    _WipSection section,
    List<StatusEntry> conflicts,
    List<StatusEntry> unstaged,
    List<StatusEntry> staged,
  ) {
    switch (section) {
      case _WipSection.conflicts:
        return SectionHeader(title: 'Conflicts', count: conflicts.length);
      case _WipSection.unstaged:
        return SectionHeader(
          title: 'Unstaged files',
          count: unstaged.length,
          actions: [
            TextButton(
              onPressed: unstaged.isEmpty
                  ? null
                  : () => tab.stageEntries(unstaged),
              child: const Text('Stage all', style: TextStyle(fontSize: 12)),
            ),
          ],
        );
      case _WipSection.staged:
        return SectionHeader(
          title: 'Staged files',
          count: staged.length,
          actions: [
            TextButton(
              onPressed: staged.isEmpty
                  ? null
                  : () => tab.run('Unstage', tab.repo.unstageAll),
              child: const Text('Unstage all', style: TextStyle(fontSize: 12)),
            ),
          ],
        );
    }
  }

  bool _isSelected(StatusEntry e, bool staged) {
    final target = tab.diffTarget;
    return target is WorkingFileTarget &&
        target.entry.path == e.path &&
        target.staged == staged;
  }

  Widget _dirRow(
    BuildContext context,
    RepoActions actions,
    _WipSection section,
    FileTreeRow<StatusEntry> dir,
    List<StatusEntry> sectionFiles,
  ) {
    List<StatusEntry> inside() =>
        itemsUnder(sectionFiles, (e) => e.path, dir.path);
    return _DirRow(
      key: ValueKey('dir:${section.name}:${dir.path}'),
      label: dir.label,
      path: dir.path,
      depth: dir.depth,
      fileCount: dir.fileCount,
      collapsed: dir.collapsed,
      onTap: () => tab.toggleDir('${section.name}:${dir.path}'),
      actions: switch (section) {
        _WipSection.unstaged => [
          SmallIconButton(
            icon: Icons.delete_outline,
            tooltip: 'Discard folder',
            color: AppColors.danger,
            onPressed: () => actions.discard(inside()),
          ),
          SmallIconButton(
            icon: Icons.add_circle_outline,
            tooltip: 'Stage folder',
            color: AppColors.success,
            onPressed: () => tab.stageEntries(inside()),
          ),
        ],
        _WipSection.staged => [
          SmallIconButton(
            icon: Icons.remove_circle_outline,
            tooltip: 'Unstage folder',
            color: AppColors.warning,
            onPressed: () => tab.unstageEntries(inside()),
          ),
        ],
        _WipSection.conflicts => const [],
      },
    );
  }

  Widget _fileRow(
    BuildContext context,
    RepoActions actions,
    _WipSection section,
    StatusEntry e, {
    int depth = 0,
    bool nameOnly = false,
  }) {
    switch (section) {
      case _WipSection.conflicts:
        return _FileRow(
          depth: depth,
          nameOnly: nameOnly,
          kind: ChangeKind.conflicted,
          path: e.path,
          selected: _isSelected(e, false),
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
              onPressed: () =>
                  tab.run('Resolve', () => tab.repo.markResolved([e.path])),
            ),
            SmallIconButton(
              icon: Icons.open_in_new,
              tooltip: 'Open in external editor',
              onPressed: () => openExternally(tab, e.path),
            ),
          ],
        );
      case _WipSection.unstaged:
        return _FileRow(
          depth: depth,
          nameOnly: nameOnly,
          kind: e.worktree ?? ChangeKind.modified,
          path: e.path,
          selected: _isSelected(e, false),
          onTap: () => tab.openWorkingFile(e, staged: false),
          onSecondaryTap: (pos) => showContextMenu(context, pos, [
            menuItem('Stage', () => tab.stageEntries([e]), icon: Icons.add),
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
        );
      case _WipSection.staged:
        return _FileRow(
          depth: depth,
          nameOnly: nameOnly,
          kind: e.index ?? ChangeKind.modified,
          path: e.path,
          oldPath: e.oldPath,
          selected: _isSelected(e, true),
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
        );
    }
  }
}

class _DirRow extends StatefulWidget {
  const _DirRow({
    super.key,
    required this.label,
    required this.path,
    required this.depth,
    required this.fileCount,
    required this.collapsed,
    required this.onTap,
    required this.actions,
  });

  final String label;
  final String path;
  final int depth;
  final int fileCount;
  final bool collapsed;
  final VoidCallback onTap;
  final List<Widget> actions;

  @override
  State<_DirRow> createState() => _DirRowState();
}

class _DirRowState extends State<_DirRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Tooltip(
          message: widget.path,
          waitDuration: const Duration(seconds: 1),
          child: Container(
            height: 28,
            color: _hover ? AppColors.hover : null,
            padding: EdgeInsets.only(
              left: 12 + widget.depth * _treeIndent,
              right: 12,
            ),
            child: Row(
              children: [
                Icon(
                  widget.collapsed ? Icons.chevron_right : Icons.expand_more,
                  size: 16,
                  color: AppColors.textDim,
                ),
                const SizedBox(width: 2),
                Icon(
                  widget.collapsed ? Icons.folder : Icons.folder_open,
                  size: 15,
                  color: AppColors.textDim,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
                if (_hover)
                  ...widget.actions
                else
                  Text(
                    '${widget.fileCount}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textFaint,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
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
