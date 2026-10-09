import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../git/models.dart';
import '../../git/repository.dart';
import '../details/details_panel.dart';
import '../dialogs/dialogs.dart';
import '../diff/diff_view.dart';
import '../graph_view/commit_graph_view.dart';
import '../sidebar/sidebar.dart';
import '../widgets/common.dart';
import 'output_panel.dart';
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

  /// Holds focus for the tab's own keys (Esc) when nothing in it has focus.
  final _viewFocus = FocusNode(debugLabel: 'repo view');

  @override
  void initState() {
    super.initState();
    widget.tab.addListener(_offerForceTagFetch);
    _offerForceTagFetch();
  }

  @override
  void didUpdateWidget(RepoView old) {
    super.didUpdateWidget(old);
    if (old.tab != widget.tab) {
      old.tab.removeListener(_offerForceTagFetch);
      widget.tab.addListener(_offerForceTagFetch);
    }
  }

  @override
  void dispose() {
    widget.tab.removeListener(_offerForceTagFetch);
    searchFocus.dispose();
    _viewFocus.dispose();
    super.dispose();
  }

  /// Pops up Force Tag Fetch when a fetch found tags moved on the remote.
  void _offerForceTagFetch() {
    if (widget.tab.movedTags.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Not over another dialog (asked, not subscribed to: depending on the
      // route would rebuild this view whenever a dialog opens).
      if (!mounted || (Navigator.maybeOf(context)?.canPop() ?? false)) return;
      if (widget.tab.takeMovedTagsPrompt()) {
        showMovedTags(context, widget.tab);
      }
    });
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
        // Fields and views with their own Esc (search, diff) handle it
        // first; text fields don't, so it's left alone while typing.
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!_typing) tab.back();
        },
      },
      child: Focus(
        focusNode: _viewFocus,
        child: ListenableBuilder(
          listenable: tab,
          builder: (context, _) {
            if (tab.loadError != null && tab.graph.rowCount == 0) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: AppColors.danger,
                      size: 32,
                    ),
                    const SizedBox(height: 8),
                    Text(tab.loadError!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: tab.load,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }
            final settings = tab.app.settings;
            // The mouse's back button works like Esc.
            return Listener(
              onPointerDown: (e) {
                if (e.buttons & kBackMouseButton != 0) {
                  tab.back();
                } else if (!_viewFocus.hasFocus) {
                  // A click in the tab focuses it, so Esc reaches it (what
                  // was clicked can still take focus itself).
                  _viewFocus.requestFocus();
                }
              },
              child: Column(
                children: [
                  RepoToolbar(tab: tab, searchFocus: searchFocus),
                  if (tab.operation != RepoOperation.none ||
                      tab.stashConflict != null ||
                      tab.status.conflicted.isNotEmpty)
                    OperationBanner(tab: tab),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) {
                        // Keep side panels from squeezing the graph out.
                        final maxSide = max(200.0, c.maxWidth * 0.3);
                        final minSide = min(120.0, maxSide);
                        final minDetails = min(220.0, maxSide);
                        final sideW = min(
                          settings.sidebarWidth,
                          maxSide * 0.8,
                        ).clamp(minSide, maxSide);
                        final detailsW = settings.detailsWidth.clamp(
                          minDetails,
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
                                () => settings.sidebarWidth = (sideW + dx)
                                    .clamp(minSide, maxSide),
                              ),
                              onEnd: tab.app.save,
                            ),
                            Expanded(
                              child: tab.diffTarget != null
                                  ? DiffView(tab: tab)
                                  : CommitGraphView(tab: tab),
                            ),
                            if (tab.detailsOpen) ...[
                              ResizeHandle(
                                onDrag: (dx) => setState(
                                  () => settings.detailsWidth = (detailsW - dx)
                                      .clamp(220.0, maxSide),
                                ),
                                onEnd: tab.app.save,
                              ),
                              SizedBox(
                                width: detailsW,
                                child: DetailsPanel(tab: tab),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                  OutputPanel(tab: tab),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Whether a text field has focus.
  bool get _typing =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<EditableText>() !=
      null;
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
      decoration: BoxDecoration(
        color: AppColors.toolbar,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, c) => Row(
          children: [
            // Branch and actions scroll sideways when the toolbar is narrow.
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
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
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textDim,
                            ),
                          ),
                          InkWell(
                            onTap: tab.jumpToHead,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.call_split,
                                  size: 14,
                                  color: AppColors.accent,
                                ),
                                const SizedBox(width: 4),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 220,
                                  ),
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
                                if (head != null &&
                                    (head.ahead > 0 || head.behind > 0))
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: Text(
                                      '↑${head.ahead} ↓${head.behind}',
                                      style: TextStyle(
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
                      onPressed: idle
                          ? () => actions.pull(PullMode.ffOnly)
                          : null,
                      menu: [
                        menuItem(
                          'Fetch all',
                          () => tab.fetch(),
                          icon: Icons.sync,
                        ),
                        menuItem(
                          'Pull (fast-forward only)',
                          () => actions.pull(PullMode.ffOnly),
                          icon: Icons.fast_forward,
                        ),
                        menuItem(
                          'Pull (merge)',
                          () => actions.pull(PullMode.merge),
                          icon: Icons.merge,
                        ),
                        menuItem(
                          'Pull (rebase)',
                          () => actions.pull(PullMode.rebase),
                          icon: Icons.low_priority,
                        ),
                      ],
                    ),
                    ToolbarButton(
                      icon: Icons.upload,
                      label: 'Push',
                      busy: busy == 'Push' || busy == 'Force push',
                      onPressed: idle ? actions.push : null,
                      menu: [
                        menuItem('Push', actions.push, icon: Icons.upload),
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
                  ],
                ),
              ),
            ),
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
                      style: TextStyle(fontSize: 12, color: AppColors.textDim),
                    ),
                  ],
                ),
              ),
            if (tab.fetchError != null) _FetchFailed(tab: tab),
            if (tab.movedTags.isNotEmpty) _TagsMoved(tab: tab),
            _SearchBox(
              tab: tab,
              focus: searchFocus,
              width: c.maxWidth < 900 ? 170 : 260,
            ),
            SmallIconButton(
              icon: Icons.refresh,
              tooltip: 'Refresh (F5)',
              onPressed: () => tab.refresh(forceLog: true),
            ),
            SmallIconButton(
              key: const ValueKey('toggle-details'),
              icon: Icons.view_sidebar_outlined,
              tooltip:
                  '${tab.detailsOpen ? 'Hide' : 'Show'} the details panel '
                  '(${shortcut('I')})',
              color: tab.detailsOpen ? AppColors.accent : null,
              onPressed: tab.toggleDetails,
            ),
          ],
        ),
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

/// Shown while the last fetch failed; opens the failed command's output.
class _FetchFailed extends StatelessWidget {
  const _FetchFailed({required this.tab});
  final RepoTabController tab;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Tooltip(
      message: 'Last fetch failed: ${tab.fetchError}\nClick for details',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: const ValueKey('fetch-failed'),
          borderRadius: BorderRadius.circular(4),
          onTap: () => tab.showOutput(tab.fetchErrorEntry),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off, size: 16, color: AppColors.warning),
                SizedBox(width: 5),
                Text(
                  'Fetch failed',
                  style: TextStyle(fontSize: 12, color: AppColors.warning),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Shown while tags that moved on the remote weren't moved here; offers
/// Force Tag Fetch.
class _TagsMoved extends StatelessWidget {
  const _TagsMoved({required this.tab});
  final RepoTabController tab;

  @override
  Widget build(BuildContext context) {
    final n = tab.movedTags.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: '$n ${n == 1 ? 'tag' : 'tags'} moved on the remote',
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: const ValueKey('tags-moved'),
            borderRadius: BorderRadius.circular(4),
            onTap: () => showMovedTags(context, tab),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sell_outlined, size: 16, color: AppColors.warning),
                  SizedBox(width: 5),
                  Text(
                    'Tags moved',
                    style: TextStyle(fontSize: 12, color: AppColors.warning),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lists the tags that moved on the remote, and offers to move the local
/// ones too (once, or on every fetch from now on).
Future<void> showMovedTags(BuildContext context, RepoTabController tab) async {
  final tags = tab.movedTags;
  if (tags.isEmpty) return;
  var always = false;
  final one = tags.length == 1;
  final go = await showAppDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(
          one ? 'A tag moved on the remote' : 'Tags moved on the remote',
          style: const TextStyle(fontSize: 17),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                one
                    ? 'This tag points to a different commit on the remote. '
                          'Force Tag Fetch replaces your local tag with the '
                          'remote\'s.'
                    : 'These tags point to different commits on the remote. '
                          'Force Tag Fetch replaces your local tags with the '
                          'remote\'s.',
                style: TextStyle(color: AppColors.textDim),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  child: SelectableText(
                    tags.join('\n'),
                    style: monoStyle(size: 12.5),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                key: const ValueKey('force-tag-fetch-always'),
                onTap: () => setState(() => always = !always),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: Checkbox(
                        value: always,
                        onChanged: (v) => setState(() => always = v ?? false),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Always force tag fetch',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            key: const ValueKey('force-tag-fetch'),
            autofocus: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Force Tag Fetch'),
          ),
        ],
      ),
    ),
  );
  if (go != true) return;
  if (always) tab.app.setForceTagFetch(true);
  await tab.fetch(forceTags: true);
}

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider();
  @override
  Widget build(BuildContext context) => Container(
    // No margin: it sits in the usual gap between two buttons, so the
    // spacing stays even.
    width: 1,
    height: 28,
    color: AppColors.border,
  );
}

class _SearchBox extends StatefulWidget {
  const _SearchBox({required this.tab, required this.focus, this.width = 260});
  final RepoTabController tab;
  final FocusNode focus;
  final double width;

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
      width: widget.width,
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
            hintText: 'Search commits (${shortcut('F')})',
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
                          style: TextStyle(
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

/// Shown while a merge / rebase / cherry-pick / revert is in progress, or
/// while a stash applied with conflicts: what's being combined, how many
/// files still have conflicts, and the ways forward.
class OperationBanner extends StatelessWidget {
  const OperationBanner({super.key, required this.tab});
  final RepoTabController tab;

  @override
  Widget build(BuildContext context) {
    final op = tab.operation;
    final conflicts = tab.status.conflicted.length;
    final total = max(tab.conflictTotal, conflicts);
    final progress = tab.rebaseProgress;
    final idle = tab.busy == null;
    final sides = tab.conflictSides;
    final what = op == RepoOperation.none
        ? (tab.stashConflict != null
              ? sides?.description ?? 'Applying a stash'
              : 'Conflicts in the working tree')
        : sides?.description ?? '${op.label} in progress';
    final String state;
    if (conflicts > 0) {
      state = total > 1
          ? '$conflicts of $total files still have conflicts.'
          : '1 file has conflicts.';
    } else if (op == RepoOperation.none) {
      state = 'All conflicts resolved: click Done to finish.';
    } else if (tab.commitFinishesOperation) {
      state =
          'All conflicts resolved: continue to commit the '
          '${op.label.toLowerCase()} (message below).';
    } else {
      state = 'Continue when ready.';
    }
    final color = conflicts > 0 ? AppColors.warning : AppColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      color: color.withValues(alpha: 0.16),
      child: Row(
        children: [
          Icon(
            conflicts > 0 ? Icons.warning_amber : Icons.check_circle_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$what${progress != null ? ' ($progress)' : ''}. ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: state),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if (conflicts > 0)
            TextButton(
              key: const ValueKey('banner-resolve'),
              onPressed: () {
                final t = tab.diffTarget;
                tab.openNextConflict(
                  t is WorkingFileTarget && t.entry.conflicted ? t.path : null,
                );
              },
              child: const Text('Resolve…'),
            ),
          if (op == RepoOperation.none && tab.stashConflict != null)
            FilledButton(
              onPressed: idle && conflicts == 0
                  ? tab.finishStashConflict
                  : null,
              child: const Text('Done'),
            ),
          if (op != RepoOperation.none && op != RepoOperation.bisect) ...[
            TextButton(
              onPressed: idle
                  ? () => tab.run('Abort', () => tab.repo.abortOperation(op))
                  : null,
              child: Text('Abort', style: TextStyle(color: AppColors.danger)),
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
              key: const ValueKey('banner-continue'),
              onPressed: idle && conflicts == 0 ? tab.continueOperation : null,
              child: const Text('Continue'),
            ),
          ],
        ],
      ),
    );
  }
}
