import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../git/command_log.dart';
import '../widgets/common.dart';
import 'repo_tab_controller.dart';

/// The git commands run for a tab, newest at the bottom, VS Code "Output"
/// style: a header bar that toggles a resizable log. Failed commands show
/// their first line of output; clicking a command shows all of it.
class OutputPanel extends StatefulWidget {
  const OutputPanel({super.key, required this.tab});
  final RepoTabController tab;

  static const rowHeight = 22.0;
  static const previewHeight = 16.0;
  static const minHeight = 80.0;

  @override
  State<OutputPanel> createState() => _OutputPanelState();
}

class _OutputPanelState extends State<OutputPanel> {
  final _scroll = ScrollController();
  final _expanded = <int>{};
  bool _atBottom = true;

  RepoTabController get tab => widget.tab;
  CommandLog get log => tab.repo.commands;

  @override
  void initState() {
    super.initState();
    log.addListener(_onLog);
    tab.outputFocus.addListener(_onFocus);
    if (tab.outputFocus.value != null) _onFocus();
  }

  @override
  void didUpdateWidget(OutputPanel old) {
    super.didUpdateWidget(old);
    if (old.tab != tab) {
      old.tab.repo.commands.removeListener(_onLog);
      old.tab.outputFocus.removeListener(_onFocus);
      log.addListener(_onLog);
      tab.outputFocus.addListener(_onFocus);
      _expanded.clear();
    }
  }

  @override
  void dispose() {
    log.removeListener(_onLog);
    tab.outputFocus.removeListener(_onFocus);
    _scroll.dispose();
    super.dispose();
  }

  List<GitLogEntry> get _visible => [
    for (final e in log.entries)
      if (tab.outputShowsBackground || !e.background) e,
  ];

  void _onLog() {
    if (!mounted) return;
    setState(() {});
    if (_atBottom) _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  /// Expands the focused entry (only it) and scrolls to it. Rows above it
  /// are then collapsed, so its offset is known without laying them out.
  void _onFocus() {
    final id = tab.outputFocus.value;
    if (id == null || !mounted) return;
    setState(() {
      _expanded
        ..clear()
        ..add(id);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      var offset = 0.0;
      for (final e in _visible) {
        if (e.id == id) break;
        offset += _collapsedHeight(e);
      }
      final pos = _scroll.position;
      _scroll.jumpTo(offset.clamp(0.0, pos.maxScrollExtent));
      _atBottom = _scroll.offset >= pos.maxScrollExtent - 4;
    });
  }

  static double _collapsedHeight(GitLogEntry e) =>
      OutputPanel.rowHeight + (e.failed ? OutputPanel.previewHeight : 0);

  @override
  Widget build(BuildContext context) {
    final open = tab.outputOpen;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (open)
          ResizeHandle(
            vertical: true,
            onDrag: (dy) => setState(() {
              final max = MediaQuery.sizeOf(context).height * 0.7;
              tab.outputHeight = (tab.outputHeight - dy).clamp(
                OutputPanel.minHeight,
                max < OutputPanel.minHeight ? OutputPanel.minHeight : max,
              );
            }),
          )
        else
          const Divider(height: 1, color: AppColors.border),
        _header(open),
        if (open)
          SizedBox(
            height: tab.outputHeight,
            child: ColoredBox(color: AppColors.background, child: _list()),
          ),
      ],
    );
  }

  Widget _header(bool open) {
    GitLogEntry? latest;
    for (var i = log.entries.length - 1; i >= 0; i--) {
      if (!log.entries[i].background) {
        latest = log.entries[i];
        break;
      }
    }
    return Container(
      height: 26,
      color: AppColors.panel,
      child: Row(
        children: [
          Expanded(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                key: const ValueKey('output-toggle'),
                onTap: tab.toggleOutput,
                child: Row(
                  children: [
                    const SizedBox(width: 6),
                    Icon(
                      open ? Icons.expand_more : Icons.expand_less,
                      size: 16,
                      color: AppColors.textDim,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Output',
                      style: TextStyle(fontSize: 12, color: AppColors.textDim),
                    ),
                    const SizedBox(width: 12),
                    if (latest != null) ...[
                      _StatusIcon(latest),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          latest.commandLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: monoStyle(
                            size: 11.5,
                            color: latest.failed
                                ? AppColors.danger
                                : AppColors.textFaint,
                          ),
                        ),
                      ),
                    ] else
                      const Spacer(),
                  ],
                ),
              ),
            ),
          ),
          if (open) ...[
            Tooltip(
              message: 'Also list the commands of the automatic refreshes',
              child: InkWell(
                key: const ValueKey('output-background'),
                onTap: () => setState(
                  () => tab.outputShowsBackground = !tab.outputShowsBackground,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    children: [
                      Icon(
                        tab.outputShowsBackground
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        size: 14,
                        color: AppColors.textDim,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Background refreshes',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SmallIconButton(
              icon: Icons.block,
              size: 14,
              tooltip: 'Clear',
              onPressed: () {
                _expanded.clear();
                log.clear();
              },
            ),
            const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }

  Widget _list() {
    final entries = _visible;
    if (entries.isEmpty) {
      return const Center(
        child: Text(
          'No git commands yet',
          style: TextStyle(fontSize: 12, color: AppColors.textFaint),
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.axis == Axis.vertical && n.depth == 0) {
          _atBottom = n.metrics.pixels >= n.metrics.maxScrollExtent - 4;
        }
        return false;
      },
      child: ListView.builder(
        controller: _scroll,
        itemCount: entries.length,
        itemBuilder: (context, i) {
          final e = entries[i];
          return _EntryRow(
            key: ValueKey(e.id),
            entry: e,
            expanded: _expanded.contains(e.id),
            focused: tab.outputFocus.value == e.id,
            onTap: () => setState(() {
              if (!_expanded.remove(e.id)) _expanded.add(e.id);
            }),
          );
        },
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    super.key,
    required this.entry,
    required this.expanded,
    required this.focused,
    required this.onTap,
  });

  final GitLogEntry entry;
  final bool expanded;
  final bool focused;
  final VoidCallback onTap;

  static const _textLeft = 10 + 62 + 14 + 6.0;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final dim = e.background ? AppColors.textFaint : AppColors.text;
    final output = e.output;
    return Material(
      color: focused ? AppColors.selection : Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: OutputPanel.rowHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 62,
                          child: Text(
                            _time(e.started),
                            style: monoStyle(
                              size: 11,
                              color: AppColors.textFaint,
                            ),
                          ),
                        ),
                        _StatusIcon(e),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            e.commandLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: monoStyle(size: 12, color: dim),
                          ),
                        ),
                        if (e.duration != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              _duration(e.duration!),
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textFaint,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (e.failed && !expanded)
                  SizedBox(
                    height: OutputPanel.previewHeight,
                    child: Padding(
                      padding: const EdgeInsets.only(
                        left: _textLeft,
                        right: 10,
                      ),
                      child: Text(
                        _firstLine(output),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: monoStyle(size: 11.5, color: AppColors.danger),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (expanded) _details(e, output),
        ],
      ),
    );
  }

  Widget _details(GitLogEntry e, String output) {
    final facts = [
      if (e.startError != null)
        'not started'
      else if (e.exitCode != null)
        'exit code ${e.exitCode}'
      else
        'running',
      if (e.duration != null) _duration(e.duration!),
      displayPath(e.cwd),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(_textLeft, 0, 10, 8),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.panel,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    facts,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textDim,
                    ),
                  ),
                ),
                SmallIconButton(
                  icon: Icons.copy,
                  size: 13,
                  tooltip: 'Copy command and output',
                  onPressed: () => Clipboard.setData(
                    ClipboardData(
                      text:
                          '\$ ${e.commandLine}\n'
                          '${output.isEmpty ? '' : '$output\n'}',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(
                child: SelectableText(
                  output.isEmpty ? '(no output)' : output,
                  style: monoStyle(
                    size: 11.5,
                    color: e.failed ? AppColors.danger : AppColors.text,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _firstLine(String s) => s
      .split('\n')
      .map((l) => l.trim())
      .firstWhere((l) => l.isNotEmpty, orElse: () => '');

  static String _time(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}

String _duration(Duration d) => d.inMilliseconds < 1000
    ? '${d.inMilliseconds} ms'
    : '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s';

class _StatusIcon extends StatelessWidget {
  const _StatusIcon(this.e);
  final GitLogEntry e;

  @override
  Widget build(BuildContext context) {
    if (e.running) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: Padding(
          padding: EdgeInsets.all(2),
          child: CircularProgressIndicator(strokeWidth: 1.5),
        ),
      );
    }
    final (icon, color) = e.failed
        ? (Icons.error, AppColors.danger)
        : e.exitCode == 0
        ? (Icons.check, AppColors.success)
        : (Icons.remove, AppColors.textFaint); // an expected non-zero exit
    return Icon(icon, size: 14, color: color);
  }
}
