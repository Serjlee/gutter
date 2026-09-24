import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../git/models.dart';
import '../repo/repo_actions.dart';
import '../repo/repo_tab_controller.dart';
import '../widgets/common.dart';

class Sidebar extends StatefulWidget {
  const Sidebar({super.key, required this.tab});
  final RepoTabController tab;

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final _filter = TextEditingController();
  final _collapsed = <String>{'tags'};

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  bool _matches(String name) {
    final q = _filter.text.trim().toLowerCase();
    return q.isEmpty || name.toLowerCase().contains(q);
  }

  void _toggle(String key) => setState(() {
    if (!_collapsed.remove(key)) _collapsed.add(key);
  });

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    final actions = RepoActions(context, tab);
    final locals = tab.refs
        .where((r) => r.type == RefType.localBranch && _matches(r.name))
        .toList();
    final remoteRefs = tab.refs
        .where(
          (r) =>
              r.type == RefType.remoteBranch &&
              !r.isRemoteHead &&
              _matches(r.name),
        )
        .toList();
    final byRemote = <String, List<GitRef>>{};
    for (final r in remoteRefs) {
      (byRemote[r.remote] ??= []).add(r);
    }
    for (final remote in tab.remotes) {
      byRemote.putIfAbsent(remote.name, () => []);
    }
    final tags =
        tab.refs
            .where((r) => r.type == RefType.tag && _matches(r.name))
            .toList()
          ..sort((a, b) => b.name.compareTo(a.name));
    final stashes = tab.stashes.where((s) => _matches(s.message)).toList();

    final items = <Widget>[
      SectionHeader(
        title: 'Local',
        count: locals.length,
        expanded: !_collapsed.contains('local'),
        onToggle: () => _toggle('local'),
        actions: [
          SmallIconButton(
            icon: Icons.add,
            tooltip: 'Create branch',
            onPressed: () => actions.createBranch(),
          ),
        ],
      ),
      if (!_collapsed.contains('local'))
        for (final r in locals)
          _RefTile(
            key: ValueKey(r.fullName),
            label: r.name,
            icon: r.isHead ? Icons.check : Icons.call_split,
            iconColor: r.isHead ? AppColors.success : AppColors.localBranch,
            bold: r.isHead,
            trailing: _AheadBehind(ref: r),
            onTap: () => tab.jumpToSha(r.sha),
            onDoubleTap: r.isHead ? null : () => actions.checkoutRef(r),
            menu: () => actions.refMenu(r),
          ),
      for (final entry in byRemote.entries) ...[
        SectionHeader(
          title: 'Remote · ${entry.key}',
          count: entry.value.length,
          expanded: !_collapsed.contains('remote:${entry.key}'),
          onToggle: () => _toggle('remote:${entry.key}'),
        ),
        if (!_collapsed.contains('remote:${entry.key}'))
          for (final r in entry.value)
            _RefTile(
              key: ValueKey(r.fullName),
              label: r.remoteBranchName,
              icon: Icons.cloud_outlined,
              iconColor: AppColors.remoteBranch,
              onTap: () => tab.jumpToSha(r.sha),
              onDoubleTap: () => actions.checkoutRef(r),
              menu: () => actions.refMenu(r),
            ),
      ],
      SectionHeader(
        title: 'Tags',
        count: tags.length,
        expanded: !_collapsed.contains('tags'),
        onToggle: () => _toggle('tags'),
      ),
      if (!_collapsed.contains('tags'))
        for (final r in tags)
          _RefTile(
            key: ValueKey(r.fullName),
            label: r.name,
            icon: Icons.sell_outlined,
            iconColor: AppColors.tag,
            onTap: () => tab.jumpToSha(r.sha),
            menu: () => actions.refMenu(r),
          ),
      SectionHeader(
        title: 'Stashes',
        count: stashes.length,
        expanded: !_collapsed.contains('stashes'),
        onToggle: () => _toggle('stashes'),
      ),
      if (!_collapsed.contains('stashes'))
        for (final s in stashes)
          _RefTile(
            key: ValueKey('stash-${s.sha}'),
            label: s.message,
            icon: Icons.inventory_2_outlined,
            iconColor: AppColors.textDim,
            tooltip:
                '${s.ref} · ${formatDate(DateTime.fromMillisecondsSinceEpoch(s.time * 1000))}',
            onDoubleTap: () =>
                tab.run('Apply stash', () => tab.repo.stashApply(s.index)),
            menu: () => actions.stashMenu(s),
          ),
    ];

    return Container(
      color: AppColors.panel,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: _filter,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'Filter',
                  prefixIcon: Icon(Icons.filter_list, size: 16),
                  prefixIconConstraints: BoxConstraints(minWidth: 30),
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ),
          Expanded(child: ListView(children: items)),
        ],
      ),
    );
  }
}

class _AheadBehind extends StatelessWidget {
  const _AheadBehind({required this.ref});
  final GitRef ref;

  @override
  Widget build(BuildContext context) {
    if (ref.upstreamGone) {
      return const Tooltip(
        message: 'Upstream branch is gone',
        child: Icon(Icons.cloud_off, size: 13, color: AppColors.textFaint),
      );
    }
    if (ref.ahead == 0 && ref.behind == 0) return const SizedBox();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (ref.ahead > 0) ...[
          const Icon(Icons.arrow_upward, size: 11, color: AppColors.textDim),
          Text(
            '${ref.ahead}',
            style: const TextStyle(fontSize: 11, color: AppColors.textDim),
          ),
        ],
        if (ref.behind > 0) ...[
          const SizedBox(width: 3),
          const Icon(Icons.arrow_downward, size: 11, color: AppColors.textDim),
          Text(
            '${ref.behind}',
            style: const TextStyle(fontSize: 11, color: AppColors.textDim),
          ),
        ],
      ],
    );
  }
}

class _RefTile extends StatefulWidget {
  const _RefTile({
    super.key,
    required this.label,
    required this.icon,
    required this.iconColor,
    this.bold = false,
    this.trailing,
    this.tooltip,
    this.onTap,
    this.onDoubleTap,
    required this.menu,
  });

  final String label;
  final IconData icon;
  final Color iconColor;
  final bool bold;
  final Widget? trailing;
  final String? tooltip;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final List<PopupMenuEntry<VoidCallback>> Function() menu;

  @override
  State<_RefTile> createState() => _RefTileState();
}

class _RefTileState extends State<_RefTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    Widget tile = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        onSecondaryTapUp: (d) => unawaited(
          showContextMenu(context, d.globalPosition, widget.menu()),
        ),
        child: Container(
          height: 26,
          color: _hover ? AppColors.hover : null,
          padding: const EdgeInsets.only(left: 18, right: 8),
          child: Row(
            children: [
              Icon(widget.icon, size: 14, color: widget.iconColor),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: widget.bold ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
              ?widget.trailing,
            ],
          ),
        ),
      ),
    );
    if (widget.tooltip != null) {
      tile = Tooltip(message: widget.tooltip, child: tile);
    }
    return tile;
  }
}
