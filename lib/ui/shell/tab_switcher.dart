import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../app/tab_groups.dart';
import '../../app/theme.dart';
import '../repo/repo_tab_controller.dart';
import '../widgets/common.dart';
import 'tab_strip.dart' show groupLabel;

/// Lists every open tab under its group, filtered as you type: ↑/↓ pick,
/// Enter shows the tab, Esc closes. Opens under the tab strip's right end.
Future<void> showTabSwitcher(BuildContext context, AppController app) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.12),
    animationStyle: AnimationStyle.noAnimation,
    builder: (ctx) => Stack(
      children: [Positioned(top: 40, right: 8, child: TabSwitcher(app: app))],
    ),
  );
}

class TabSwitcher extends StatefulWidget {
  const TabSwitcher({super.key, required this.app});
  final AppController app;

  @override
  State<TabSwitcher> createState() => _TabSwitcherState();
}

/// A row of the list: a group's header, or a tab.
typedef _Row = ({TabGroup? group, RepoTabController? tab});

class _TabSwitcherState extends State<TabSwitcher> {
  final _query = TextEditingController();
  final _scroll = ScrollController();
  static const _rowHeight = 30.0;
  static const _listPadding = 4.0;

  /// The picked tab (Enter shows it).
  RepoTabController? _picked;

  AppController get app => widget.app;

  @override
  void initState() {
    super.initState();
    _picked = app.activeTab;
    var text = '';
    _query.addListener(() {
      if (_query.text == text) return; // (the cursor moved)
      text = _query.text;
      setState(() => _picked = _tabs().firstOrNull);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool _matches(RepoTabController t) {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return t.name.toLowerCase().contains(q) ||
        t.repo.path.toLowerCase().contains(q) ||
        (t.group?.name.toLowerCase().contains(q) ?? false);
  }

  List<_Row> _rows() {
    final rows = <_Row>[];
    TabGroup? current;
    for (final t in app.tabs.where(_matches)) {
      final g = t.group;
      if (g != null && g != current) rows.add((group: g, tab: null));
      // Ungrouped tabs after a group get a header of their own.
      if (g == null && current != null) rows.add((group: null, tab: null));
      current = g;
      rows.add((group: g, tab: t));
    }
    return rows;
  }

  List<RepoTabController> _tabs() => [
    for (final r in _rows())
      if (r.tab != null) r.tab!,
  ];

  void _move(int delta) {
    final tabs = _tabs();
    if (tabs.isEmpty) return;
    final i = _picked == null ? -1 : tabs.indexOf(_picked!);
    setState(() => _picked = tabs[(i + delta).clamp(0, tabs.length - 1)]);
    _reveal();
  }

  /// Scrolls the picked tab into view.
  void _reveal() {
    if (!_scroll.hasClients || _picked == null) return;
    final i = _rows().indexWhere((r) => r.tab == _picked);
    if (i < 0) return;
    final top = _listPadding + i * _rowHeight;
    final pos = _scroll.position;
    if (top < pos.pixels) {
      _scroll.jumpTo(top);
    } else if (top + _rowHeight > pos.pixels + pos.viewportDimension) {
      _scroll.jumpTo(top + _rowHeight - pos.viewportDimension);
    }
  }

  void _show(RepoTabController t) {
    Navigator.pop(context);
    app.activate(app.tabs.indexOf(t));
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    final height = MediaQuery.sizeOf(context).height;
    return Material(
      color: AppColors.panel,
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 380,
        constraints: BoxConstraints(maxHeight: height * 0.7),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                      _move(1),
                  const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                      _move(-1),
                },
                child: TextField(
                  key: const ValueKey('tab-search'),
                  controller: _query,
                  autofocus: true,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    prefixIconConstraints: const BoxConstraints(minWidth: 32),
                    hintText:
                        'Search ${app.tabs.length} tab${app.tabs.length == 1 ? '' : 's'}',
                  ),
                  onSubmitted: (_) {
                    if (_picked != null) _show(_picked!);
                  },
                ),
              ),
            ),
            const Divider(),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No tabs match',
                  style: TextStyle(color: AppColors.textDim, fontSize: 13),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  controller: _scroll,
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: _listPadding),
                  itemExtent: _rowHeight,
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    return r.tab == null ? _header(r.group) : _tabRow(r.tab!);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _header(TabGroup? g) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: Row(
        children: [
          if (g != null) ...[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: AppColors.group(g.color),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              g == null ? 'NOT IN A GROUP' : groupLabel(g).toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
                color: AppColors.textDim,
              ),
            ),
          ),
          if (g != null && g.collapsed)
            Text(
              'collapsed',
              style: TextStyle(fontSize: 11, color: AppColors.textFaint),
            ),
        ],
      ),
    );
  }

  Widget _tabRow(RepoTabController t) {
    final picked = t == _picked;
    final active = t == app.activeTab;
    return _HoverRow(
      picked: picked,
      onTap: () => _show(t),
      builder: (hover) => Row(
        children: [
          SizedBox(width: t.group == null ? 12 : 30),
          Flexible(
            child: Text(
              t.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.text,
                fontWeight: active ? FontWeight.w600 : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              displayPath(t.repo.path),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: AppColors.textFaint),
            ),
          ),
          // A fixed slot, so the path doesn't shift on hover.
          SizedBox(
            width: 28,
            child: hover
                ? InkWell(
                    borderRadius: BorderRadius.circular(3),
                    onTap: () {
                      app.closeTab(app.tabs.indexOf(t));
                      if (app.tabs.isEmpty) {
                        Navigator.pop(context);
                      } else {
                        setState(() {
                          if (!app.tabs.contains(_picked)) {
                            _picked = _tabs().firstOrNull;
                          }
                        });
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.close,
                        size: 14,
                        color: AppColors.textDim,
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _HoverRow extends StatefulWidget {
  const _HoverRow({
    required this.picked,
    required this.onTap,
    required this.builder,
  });
  final bool picked;
  final VoidCallback onTap;
  final Widget Function(bool hover) builder;

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: widget.picked
                ? AppColors.selection
                : _hover
                ? AppColors.hover
                : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: widget.builder(_hover),
        ),
      ),
    );
  }
}
