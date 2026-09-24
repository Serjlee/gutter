import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../git/models.dart';
import '../../git/repository.dart';
import '../details/details_panel.dart';
import '../diff/diff_view.dart';
import '../graph_view/commit_graph_view.dart';
import '../sidebar/sidebar.dart';
import '../widgets/common.dart';
import 'repo_actions.dart';
import 'repo_tab_controller.dart';

class RepoView extends StatefulWidget {
  const RepoView({super.key, required this.tab});
  final RepoTabController tab;

  @override
  State<RepoView> createState() => _RepoViewState();
}

class _RepoViewState extends State<RepoView> {
  final searchFocus = FocusNode(debugLabel: 'search');

  @override
  void dispose() {
    searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
            searchFocus.requestFocus,
      },
      child: ListenableBuilder(
        listenable: tab,
        builder: (context, _) {
          if (tab.loadError != null && tab.graph.rowCount == 0) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: AppColors.danger,
                    size: 32,
                  ),
                  const SizedBox(height: 8),
                  Text(tab.loadError!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: tab.load, child: const Text('Retry')),
                ],
              ),
            );
          }
          final settings = tab.app.settings;
          return Column(
            children: [
              RepoToolbar(tab: tab, searchFocus: searchFocus),
              if (tab.operation != RepoOperation.none)
                OperationBanner(tab: tab),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    // Keep side panels from squeezing the graph out.
                    final maxSide = max(200.0, c.maxWidth * 0.3);
                    final sideW = min(
                      settings.sidebarWidth,
                      maxSide * 0.8,
                    ).clamp(120.0, maxSide);
                    final detailsW = settings.detailsWidth.clamp(
                      220.0,
                      maxSide,
                    );
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: sideW,
                          child: Sidebar(tab: tab),
                        ),
                        ResizeHandle(
                          onDrag: (dx) => setState(
                            () => settings.sidebarWidth = (sideW + dx).clamp(
                              120.0,
                              maxSide,
                            ),
                          ),
                          onEnd: tab.app.save,
                        ),
                        Expanded(
                          child: tab.diffTarget != null
                              ? DiffView(tab: tab)
                              : CommitGraphView(tab: tab),
                        ),
                        ResizeHandle(
                          onDrag: (dx) => setState(
                            () => settings.detailsWidth = (detailsW - dx).clamp(
                              220.0,
                              maxSide,
                            ),
                          ),
                          onEnd: tab.app.save,
                        ),
                        SizedBox(
                          width: detailsW,
                          child: DetailsPanel(tab: tab),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class RepoToolbar extends StatelessWidget {
  const RepoToolbar({super.key, required this.tab, required this.searchFocus});
  final RepoTabController tab;
  final FocusNode searchFocus;

  @override
  Widget build(BuildContext context) {
    final actions = RepoActions(context, tab);
    final branch = tab.currentBranch;
    final head = tab.headRef;
    final busy = tab.busy;
    final idle = busy == null;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: AppColors.toolbar,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // Repo + branch.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tab.name,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textDim,
                  ),
                ),
                InkWell(
                  onTap: tab.jumpToHead,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.call_split,
                        size: 14,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Text(
                          branch ??
                              'detached ${tab.headSha?.substring(0, 7) ?? ''}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (head != null && (head.ahead > 0 || head.behind > 0))
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text(
                            '↑${head.ahead} ↓${head.behind}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textDim,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ToolbarButton(
            icon: Icons.download,
            label: 'Pull',
            tooltip: 'Pull (fast-forward only)',
            busy: busy == 'Pull',
            onPressed: idle ? () => tab.pull(PullMode.ffOnly) : null,
            menu: [
              menuItem('Fetch all', () => tab.fetch(), icon: Icons.sync),
              menuItem(
                'Pull (fast-forward only)',
                () => tab.pull(PullMode.ffOnly),
                icon: Icons.fast_forward,
              ),
              menuItem(
                'Pull (merge)',
                () => tab.pull(PullMode.merge),
                icon: Icons.merge,
              ),
              menuItem(
                'Pull (rebase)',
                () => tab.pull(PullMode.rebase),
                icon: Icons.low_priority,
              ),
            ],
          ),
          ToolbarButton(
            icon: Icons.upload,
            label: 'Push',
            busy: busy == 'Push' || busy == 'Force push',
            onPressed: idle ? () => tab.push() : null,
            menu: [
              menuItem('Push', () => tab.push(), icon: Icons.upload),
              menuItem(
                'Force push (with lease)…',
                actions.forcePush,
                icon: Icons.warning_amber,
                danger: true,
              ),
            ],
          ),
          ToolbarButton(
            icon: Icons.sync,
            label: 'Fetch',
            tooltip: _fetchTooltip(),
            busy: tab.fetching,
            onPressed: tab.fetching ? null : () => tab.fetch(),
          ),
          const _ToolbarDivider(),
          ToolbarButton(
            icon: Icons.call_split,
            label: 'Branch',
            onPressed: idle ? () => actions.createBranch() : null,
          ),
          ToolbarButton(
            icon: Icons.inventory_2_outlined,
            label: 'Stash',
            busy: busy == 'Stash',
            onPressed: idle && tab.isDirty ? actions.stash : null,
          ),
          ToolbarButton(
            icon: Icons.outbox,
            label: 'Pop',
            busy: busy == 'Pop stash',
            onPressed: idle && tab.stashes.isNotEmpty
                ? () => actions.popStash()
                : null,
          ),
          const Spacer(),
          if (busy != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$busy…',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
          if (tab.fetchError != null)
            Tooltip(
              message: 'Last auto-fetch failed:\n${tab.fetchError}',
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  Icons.cloud_off,
                  size: 18,
                  color: AppColors.warning,
                ),
              ),
            ),
          _SearchBox(tab: tab, focus: searchFocus),
          SmallIconButton(
            icon: Icons.refresh,
            tooltip: 'Refresh (F5)',
            onPressed: () => tab.refresh(forceLog: true),
          ),
        ],
      ),
    );
  }

  String _fetchTooltip() {
    final last = tab.lastFetch;
    final minutes = tab.app.settings.fetchIntervalMinutes;
    final auto = minutes > 0
        ? 'Auto-fetch every $minutes min'
        : 'Auto-fetch off';
    return last == null
        ? 'Fetch all remotes\n$auto'
        : 'Fetch all remotes\nLast fetch: ${relativeTime(last)}\n$auto';
  }
}

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider();
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 28,
    margin: const EdgeInsets.symmetric(horizontal: 6),
    color: AppColors.border,
  );
}

class _SearchBox extends StatefulWidget {
  const _SearchBox({required this.tab, required this.focus});
  final RepoTabController tab;
  final FocusNode focus;

  @override
  State<_SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<_SearchBox> {
  late final _controller = TextEditingController(text: widget.tab.search);
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    final hits = tab.searchHits.length;
    return SizedBox(
      width: 260,
      height: 32,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): () =>
              tab.searchStep(1),
          const SingleActivator(LogicalKeyboardKey.enter, shift: true): () =>
              tab.searchStep(-1),
          const SingleActivator(LogicalKeyboardKey.escape): () {
            _controller.clear();
            tab.setSearch('');
            widget.focus.unfocus();
          },
        },
        child: TextField(
          controller: _controller,
          focusNode: widget.focus,
          style: const TextStyle(fontSize: 13),
          onChanged: (v) {
            _debounce?.cancel();
            _debounce = Timer(
              const Duration(milliseconds: 150),
              () => tab.setSearch(v),
            );
          },
          decoration: InputDecoration(
            hintText: 'Search commits (Ctrl+F)',
            prefixIcon: const Icon(Icons.search, size: 16),
            prefixIconConstraints: const BoxConstraints(minWidth: 30),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            suffixIcon: tab.search.isEmpty
                ? null
                : Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$hits',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textDim,
                          ),
                        ),
                        SmallIconButton(
                          icon: Icons.keyboard_arrow_up,
                          tooltip: 'Previous (Shift+Enter)',
                          onPressed: () => tab.searchStep(-1),
                        ),
                        SmallIconButton(
                          icon: Icons.keyboard_arrow_down,
                          tooltip: 'Next (Enter)',
                          onPressed: () => tab.searchStep(1),
                        ),
                      ],
                    ),
                  ),
            suffixIconConstraints: const BoxConstraints(minWidth: 0),
          ),
        ),
      ),
    );
  }
}

/// Shown while a merge / rebase / cherry-pick / revert is in progress.
class OperationBanner extends StatelessWidget {
  const OperationBanner({super.key, required this.tab});
  final RepoTabController tab;

  @override
  Widget build(BuildContext context) {
    final op = tab.operation;
    final conflicts = tab.status.conflicted.length;
    final progress = tab.rebaseProgress;
    final idle = tab.busy == null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: AppColors.warning.withValues(alpha: 0.16),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, size: 18, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${op.label} in progress${progress != null ? ' ($progress)' : ''}. '
              '${conflicts > 0 ? '$conflicts conflicted file${conflicts == 1 ? '' : 's'}: resolve them in the WIP panel, then continue.' : 'Continue when ready.'}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if (op != RepoOperation.bisect) ...[
            TextButton(
              onPressed: idle
                  ? () => tab.run('Abort', () => tab.repo.abortOperation(op))
                  : null,
              child: const Text(
                'Abort',
                style: TextStyle(color: AppColors.danger),
              ),
            ),
            if (op == RepoOperation.rebase ||
                op == RepoOperation.cherryPick ||
                op == RepoOperation.revert)
              TextButton(
                onPressed: idle
                    ? () => tab.run('Skip', () => tab.repo.skipOperation(op))
                    : null,
                child: const Text('Skip'),
              ),
            const SizedBox(width: 6),
            FilledButton(
              onPressed: idle && conflicts == 0
                  ? () => tab.run(
                      'Continue',
                      () => tab.repo.continueOperation(op),
                    )
                  : null,
              child: const Text('Continue'),
            ),
          ],
        ],
      ),
    );
  }
}
