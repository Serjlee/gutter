import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/tab_groups.dart';
import '../../app/theme.dart';
import '../repo/repo_tab_controller.dart';
import '../widgets/common.dart';
import 'tab_switcher.dart';

/// What's being dragged in the tab strip: a tab, or a group (by its chip).
sealed class _Drag {
  const _Drag();
}

class _TabDrag extends _Drag {
  const _TabDrag(this.tab);
  final RepoTabController tab;
}

class _GroupDrag extends _Drag {
  const _GroupDrag(this.group);
  final TabGroup group;
}

/// Where a drag would drop on a tab or chip: beside it, or onto it (into
/// its group, or a new one with it).
enum _Zone { before, onto, after }

/// The open repositories as tabs, after the home tab. Groups show as
/// colored chips followed by their tabs (underlined in the group's color);
/// clicking a chip collapses the group into it. Tabs and chips are dragged
/// to reorder, group and ungroup; the strip scrolls with the mouse wheel,
/// and "All tabs" at its end lists and searches every tab.
class TabStrip extends StatefulWidget {
  const TabStrip({super.key, required this.app});
  final AppController app;

  @override
  State<TabStrip> createState() => _TabStripState();
}

class _TabStripState extends State<TabStrip> {
  final _scroll = ScrollController();
  final _tabKeys = <RepoTabController, GlobalKey>{};
  final _chipKeys = <TabGroup, GlobalKey>{};

  /// The drop the current drag would make: on which item, where.
  (Object, _Zone)? _hint;

  /// Whether a tab or chip is being dragged (tooltips would get in the way).
  bool _dragging = false;

  /// The widget built for each tab and chip, with what it was built from:
  /// reused while that's unchanged, so a change (a drag hint, a group
  /// collapsing, a tab becoming active) rebuilds the few items it touches
  /// instead of all of them (a hundred tabs take about 10 ms to rebuild).
  final _built = <Object, ({List<Object?> from, Widget widget})>{};
  final _inUse = <Object>{};
  RepoTabController? _shownActive;

  AppController get app => widget.app;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  GlobalKey _tabKey(RepoTabController t) => _tabKeys[t] ??= GlobalKey();
  GlobalKey _chipKey(TabGroup g) => _chipKeys[g] ??= GlobalKey();

  void _setHint((Object, _Zone)? hint) {
    if (hint != _hint) setState(() => _hint = hint);
  }

  /// Scrolls the active tab into view when it changes.
  void _revealActive() {
    final active = app.activeTab;
    if (active == _shownActive) return;
    _shownActive = active;
    if (active == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _tabKeys[active]?.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
        Scrollable.ensureVisible(
          ctx,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        );
      }
    });
  }

  /// The mouse wheel scrolls the strip sideways.
  void _onWheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || !_scroll.hasClients) return;
    final d = e.scrollDelta.dx != 0 ? e.scrollDelta.dx : e.scrollDelta.dy;
    final pos = _scroll.position;
    _scroll.jumpTo((pos.pixels + d).clamp(0, pos.maxScrollExtent));
  }

  // ------------------------------------------------------------- drops

  int _first(TabGroup g) => app.tabs.indexWhere((t) => t.group == g);
  int _last(TabGroup g) => app.tabs.lastIndexWhere((t) => t.group == g);

  void _drop(_Drag drag, Object? target, _Zone zone) {
    switch ((drag, target)) {
      case (_TabDrag(:final tab), final RepoTabController t):
        final i = app.tabs.indexOf(t);
        if (zone == _Zone.onto && t.group == null) {
          app.placeTab(tab, i + 1);
          app.createGroup([t, tab]);
        } else {
          app.placeTab(tab, zone == _Zone.before ? i : i + 1, group: t.group);
        }
      case (_TabDrag(:final tab), final TabGroup g):
        if (zone == _Zone.before) {
          app.placeTab(tab, _first(g));
        } else if (g.collapsed) {
          app.addToGroup(tab, g);
        } else {
          app.placeTab(tab, _first(g), group: g);
        }
      case (_TabDrag(:final tab), null):
        app.placeTab(tab, app.tabs.length);
      case (_GroupDrag(:final group), final RepoTabController t):
        if (t.group == group) return;
        final i = app.tabs.indexOf(t);
        final (start, end) = t.group == null
            ? (i, i)
            : (_first(t.group!), _last(t.group!));
        app.moveGroup(group, zone == _Zone.before ? start : end + 1);
      case (_GroupDrag(:final group), final TabGroup g):
        if (g == group) return;
        app.moveGroup(group, zone == _Zone.before ? _first(g) : _last(g) + 1);
      case (_GroupDrag(:final group), null):
        app.moveGroup(group, app.tabs.length);
      case (_, _):
        return;
    }
  }

  /// The zone under the pointer at [global] on [context]'s box.
  _Zone _zoneAt(BuildContext context, Offset global, _Drag drag, Object on) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return _Zone.after;
    final f = box.globalToLocal(global).dx / box.size.width;
    if (drag is _GroupDrag) return f < 0.5 ? _Zone.before : _Zone.after;
    if (on is TabGroup) return f < 0.35 ? _Zone.before : _Zone.onto;
    return f < 0.3
        ? _Zone.before
        : f > 0.7
        ? _Zone.after
        : _Zone.onto;
  }

  /// A drop target over one tab or chip ([on]).
  Widget _target(Object on, Widget child) {
    bool accepts(_Drag d) => switch (d) {
      _TabDrag(:final tab) => tab != on,
      _GroupDrag(:final group) =>
        group != on && !(on is RepoTabController && on.group == group),
    };
    return Builder(
      builder: (context) => DragTarget<_Drag>(
        onWillAcceptWithDetails: (d) => accepts(d.data),
        onMove: (d) {
          if (!accepts(d.data)) return;
          _setHint((on, _zoneAt(context, d.offset, d.data, on)));
        },
        onLeave: (_) {
          if (_hint?.$1 == on) _setHint(null);
        },
        onAcceptWithDetails: (d) {
          final zone = _zoneAt(context, d.offset, d.data, on);
          _setHint(null);
          _drop(d.data, on, zone);
        },
        builder: (context, _, _) => child,
      ),
    );
  }

  // ------------------------------------------------------------- menus

  void _tabMenu(RepoTabController tab, Offset at) {
    final others = app.tabs.where((t) => t != tab).toList();
    final i = app.tabs.indexOf(tab);
    showContextMenu(context, at, [
      menuItem('Add to new group', () {
        final g = app.createGroup([tab]);
        _editGroupSoon(g);
      }, icon: Icons.add_box_outlined),
      for (final g in app.groups)
        if (g != tab.group) _moveToGroupItem(tab, g),
      if (tab.group != null)
        menuItem(
          'Remove from group',
          () => app.removeFromGroup(tab),
          icon: Icons.remove_circle_outline,
        ),
      const PopupMenuDivider(),
      menuItem('Close', () => app.closeTab(i), icon: Icons.close),
      menuItem(
        'Close other tabs',
        () => app.closeTabs(others),
        enabled: others.isNotEmpty,
      ),
      menuItem(
        'Close tabs to the right',
        () => app.closeTabs(app.tabs.skip(i + 1).toList()),
        enabled: i < app.tabs.length - 1,
      ),
    ]);
  }

  PopupMenuItem<VoidCallback> _moveToGroupItem(
    RepoTabController tab,
    TabGroup g,
  ) {
    return PopupMenuItem<VoidCallback>(
      value: () => app.addToGroup(tab, g),
      height: 34,
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _Dot(color: AppColors.group(g.color)),
            ),
          ),
          Flexible(
            child: Text(
              'Move to ${groupLabel(g)}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: AppColors.text),
            ),
          ),
        ],
      ),
    );
  }

  /// Opens the editor of a group just made, once its chip is laid out.
  void _editGroupSoon(TabGroup g) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _chipKeys[g]?.currentContext;
      if (ctx != null && ctx.mounted) _editGroup(g, ctx);
    });
  }

  void _editGroup(TabGroup g, BuildContext chip) {
    final box = chip.findRenderObject() as RenderBox?;
    if (box == null) return;
    showGroupEditor(chip, app, g, box.localToGlobal(Offset.zero) & box.size);
  }

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    // Also redrawn alone for changes of order and groups.
    return ValueListenableBuilder<int>(
      valueListenable: app.tabLayout,
      builder: (context, _, _) => _strip(context),
    );
  }

  Widget _strip(BuildContext context) {
    _revealActive();
    final tabs = app.tabs;
    _tabKeys.removeWhere((t, _) => !tabs.contains(t));
    _chipKeys.removeWhere((g, _) => !app.groups.contains(g));
    final items = <Widget>[];
    _inUse.clear();
    TabGroup? current;
    for (var i = 0; i < tabs.length; i++) {
      final tab = tabs[i];
      final g = tab.group;
      if (g != null && g != current) items.add(_chip(g));
      current = g;
      if (g != null && g.collapsed) continue;
      items.add(_tab(tab));
    }
    _built.removeWhere((on, _) => !_inUse.contains(on));
    return TooltipVisibility(
      visible: !_dragging,
      child: Container(
        height: 36,
        color: AppColors.background,
        child: Row(
          children: [
            _HomeTab(
              active: app.activeIndex == -1,
              onTap: () => app.activate(-1),
            ),
            Expanded(
              child: DragTarget<_Drag>(
                // Past the last tab: to the end, out of groups.
                onMove: (_) => _setHint(null),
                onAcceptWithDetails: (d) => _drop(d.data, null, _Zone.after),
                builder: (context, candidates, _) => Listener(
                  onPointerSignal: _onWheel,
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context)
                        .copyWith(scrollbars: false),
                    child: SingleChildScrollView(
                      controller: _scroll,
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ...items,
                          if (candidates.isNotEmpty && _hint == null)
                            Container(
                              width: 2,
                              height: 28,
                              color: AppColors.accent,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (tabs.isNotEmpty) _AllTabsButton(app: app),
          ],
        ),
      ),
    );
  }

  /// The drop target for [on] (a tab or group), reused from the last build
  /// unless [from] (what its look depends on), the drop hint on it or the
  /// palette changed.
  Widget _item(
    Object on,
    List<Object?> from,
    Widget Function(_Zone? zone) build,
  ) {
    final zone = _hint?.$1 == on ? _hint!.$2 : null;
    final key = [AppColors.current, zone, ...from];
    _inUse.add(on);
    final hit = _built[on];
    if (hit != null && listEquals(hit.from, key)) return hit.widget;
    final widget = KeyedSubtree(
      key: ValueKey(on),
      child: _target(on, build(zone)),
    );
    _built[on] = (from: key, widget: widget);
    return widget;
  }

  Widget _chip(TabGroup g) {
    final count = app.tabsIn(g).length;
    return _item(g, [g.name, g.color, g.collapsed, count], (zone) {
      final chip = _GroupChip(
        key: _chipKey(g),
        group: g,
        count: count,
        dropOnto: zone == _Zone.onto,
        onTap: () => app.setGroupCollapsed(g, !g.collapsed),
        onEdit: (ctx) => _editGroup(g, ctx),
      );
      return _DropMarks(
        zone: zone,
        child: Draggable<_Drag>(
          onDragStarted: () => setState(() => _dragging = true),
          onDragEnd: (_) => setState(() => _dragging = false),
          data: _GroupDrag(g),
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: _Feedback(
            child: _GroupChip(group: g, count: count, onTap: () {}),
          ),
          childWhenDragging: Opacity(opacity: 0.4, child: chip),
          child: chip,
        ),
      );
    });
  }

  Widget _tab(RepoTabController tab) {
    final g = tab.group;
    final active = app.activeTab == tab;
    return _item(tab, [active, g?.color], (zone) {
      final view = _RepoTab(
        key: _tabKey(tab),
        tab: tab,
        active: active,
        groupColor: g == null ? null : AppColors.group(g.color),
        dropOnto: zone == _Zone.onto,
        onTap: () => app.activate(app.tabs.indexOf(tab)),
        onClose: () => app.closeTab(app.tabs.indexOf(tab)),
        onMenu: (at) => _tabMenu(tab, at),
      );
      return _DropMarks(
        zone: zone,
        child: Draggable<_Drag>(
          onDragStarted: () => setState(() => _dragging = true),
          onDragEnd: (_) => setState(() => _dragging = false),
          data: _TabDrag(tab),
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: _Feedback(
            child: SizedBox(
              height: 36,
              child: _RepoTab(
                tab: tab,
                active: true,
                groupColor: g == null ? null : AppColors.group(g.color),
                onTap: () {},
                onClose: () {},
                onMenu: (_) {},
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.4, child: view),
          child: view,
        ),
      );
    });
  }
}

/// [child] with a tooltip after a second over it, built only while the
/// pointer is [hover]ing: a strip of a hundred tabs would otherwise keep a
/// hundred tooltips alive, all rebuilt whenever they're hidden for a drag.
Widget _tipWhenHovered({
  required bool hover,
  required String message,
  required Widget child,
}) => hover
    ? Tooltip(
        message: message,
        waitDuration: const Duration(seconds: 1),
        child: child,
      )
    : child;

/// A group's name for menus and lists: its name, else its color.
String groupLabel(TabGroup g) => g.name.isNotEmpty
    ? g.name
    : '${groupColorNames[g.color % groupColorNames.length]} group';

/// The dragged item, just below the pointer: the tab or chip under it
/// stays visible, with where the drop would go.
class _Feedback extends StatelessWidget {
  const _Feedback({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FractionalTranslation(
      translation: const Offset(-0.5, 0.45),
      child: Material(
        color: Colors.transparent,
        elevation: 6,
        child: Opacity(opacity: 0.9, child: child),
      ),
    );
  }
}

/// The insertion line beside a tab or chip a drag would drop next to.
class _DropMarks extends StatelessWidget {
  const _DropMarks({required this.zone, required this.child});
  final _Zone? zone;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (zone == null || zone == _Zone.onto) return child;
    return Stack(
      children: [
        child,
        Positioned(
          top: 4,
          bottom: 4,
          left: zone == _Zone.before ? 0 : null,
          right: zone == _Zone.after ? 0 : null,
          child: Container(width: 2, color: AppColors.accent),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, this.size = 10});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// A group's chip: its color and name (and, collapsed, its tab count).
/// Click collapses or expands it; right-click edits it.
class _GroupChip extends StatefulWidget {
  const _GroupChip({
    super.key,
    required this.group,
    required this.count,
    required this.onTap,
    this.onEdit,
    this.dropOnto = false,
  });

  final TabGroup group;
  final int count;
  final VoidCallback onTap;
  final void Function(BuildContext chip)? onEdit;
  final bool dropOnto;

  @override
  State<_GroupChip> createState() => _GroupChipState();
}

class _GroupChipState extends State<_GroupChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    final color = AppColors.group(g.color);
    final named = g.name.isNotEmpty;
    final label = [if (named) g.name, if (g.collapsed) '${widget.count}'];
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: _tipWhenHovered(
        hover: _hover,
        message:
            '${groupLabel(g)}: ${widget.count} tab${widget.count == 1 ? '' : 's'}'
            '\nClick to ${g.collapsed ? 'expand' : 'collapse'}, right-click to '
            'edit',
        child: GestureDetector(
          onTap: widget.onTap,
          onSecondaryTapUp: widget.onEdit == null
              ? null
              : (_) => widget.onEdit!(context),
          child: Container(
            height: 36,
            padding: const EdgeInsets.only(left: 8, right: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // Joins the underline of the group's tabs.
              border: Border(
                bottom: BorderSide(
                  color: g.collapsed ? Colors.transparent : color,
                  width: 2,
                ),
                top: const BorderSide(color: Colors.transparent, width: 2),
              ),
            ),
            // Not animated: an AnimatedContainer interpolates between the
            // dot's and the badge's different constraints, and swells the
            // chip in between (a click mid-animation starts from there).
            child: Container(
              // Unnamed and expanded: a dot.
              width: label.isEmpty ? 14 : null,
              height: label.isEmpty ? 14 : 22,
              constraints: label.isEmpty
                  ? null
                  : const BoxConstraints(minWidth: 22, maxWidth: 160),
              padding: EdgeInsets.symmetric(horizontal: label.isEmpty ? 0 : 9),
              decoration: BoxDecoration(
                color: _hover || widget.dropOnto
                    ? Color.lerp(color, AppColors.text, 0.15)
                    : color,
                borderRadius: BorderRadius.circular(11),
                border: widget.dropOnto
                    ? Border.all(color: AppColors.text, width: 1.5)
                    : null,
              ),
              child: label.isEmpty
                  ? null
                  : Center(
                      widthFactor: 1,
                      child: Text(
                        label.join('  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.groupText,
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Edits [group] in a popup under its chip at [anchor]: name, color,
/// collapse, ungroup, close.
Future<void> showGroupEditor(
  BuildContext context,
  AppController app,
  TabGroup group,
  Rect anchor,
) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final topLeft = overlay.globalToLocal(anchor.bottomLeft);
  return showDialog<void>(
    context: context,
    barrierColor: Colors.transparent,
    animationStyle: AnimationStyle.noAnimation,
    builder: (ctx) {
      final size = MediaQuery.sizeOf(ctx);
      return Stack(
        children: [
          Positioned(
            left: topLeft.dx.clamp(8, size.width - 298),
            top: topLeft.dy + 4,
            child: _GroupEditor(app: app, group: group),
          ),
        ],
      );
    },
  );
}

class _GroupEditor extends StatefulWidget {
  const _GroupEditor({required this.app, required this.group});
  final AppController app;
  final TabGroup group;

  @override
  State<_GroupEditor> createState() => _GroupEditorState();
}

class _GroupEditorState extends State<_GroupEditor> {
  late final _name = TextEditingController(text: widget.group.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _then(VoidCallback action) {
    Navigator.pop(context);
    action();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final g = widget.group;
    Widget action(
      String label,
      IconData icon,
      VoidCallback onTap, {
      bool danger = false,
    }) {
      final color = danger ? AppColors.danger : AppColors.text;
      return InkWell(
        onTap: () => _then(onTap),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: danger ? AppColors.danger : AppColors.textDim,
              ),
              const SizedBox(width: 10),
              Text(label, style: TextStyle(fontSize: 13, color: color)),
            ],
          ),
        ),
      );
    }

    return Material(
      key: const ValueKey('group-editor'),
      color: AppColors.panel,
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 290,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: TextField(
                key: const ValueKey('group-name'),
                controller: _name,
                autofocus: true,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Name this group',
                ),
                onChanged: (v) => app.renameGroup(g, v),
                onSubmitted: (_) => Navigator.pop(context),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var c = 0; c < groupColorNames.length; c++)
                    Tooltip(
                      message: groupColorNames[c],
                      waitDuration: const Duration(milliseconds: 600),
                      child: InkWell(
                        key: ValueKey('group-color-$c'),
                        customBorder: const CircleBorder(),
                        onTap: () => setState(() => app.setGroupColor(g, c)),
                        child: Container(
                          width: 22,
                          height: 22,
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: g.color == c
                                  ? AppColors.text
                                  : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: _Dot(color: AppColors.group(c), size: 14),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(),
            const SizedBox(height: 4),
            action(
              g.collapsed ? 'Expand' : 'Collapse',
              g.collapsed ? Icons.unfold_more : Icons.unfold_less,
              () => app.setGroupCollapsed(g, !g.collapsed),
            ),
            action(
              'Ungroup',
              Icons.layers_clear_outlined,
              () => app.ungroup(g),
            ),
            action(
              'Close group',
              Icons.close,
              () => app.closeGroup(g),
              danger: true,
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Repositories (${shortcut('T')})',
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.toolbar : null,
            border: Border(right: BorderSide(color: AppColors.border)),
          ),
          child: Icon(
            Icons.grid_view_rounded,
            size: 18,
            color: active ? AppColors.accent : AppColors.textDim,
          ),
        ),
      ),
    );
  }
}

/// Opens the list of all tabs; shows how many there are.
class _AllTabsButton extends StatelessWidget {
  const _AllTabsButton({required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'All tabs (${shortcut('A', shift: true)})',
      child: InkWell(
        key: const ValueKey('all-tabs'),
        onTap: () => showTabSwitcher(context, app),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Text(
                '${app.tabs.length}',
                style: TextStyle(fontSize: 12, color: AppColors.textDim),
              ),
              const SizedBox(width: 2),
              Icon(Icons.expand_more, size: 18, color: AppColors.textDim),
            ],
          ),
        ),
      ),
    );
  }
}

class _RepoTab extends StatefulWidget {
  const _RepoTab({
    super.key,
    required this.tab,
    required this.active,
    required this.onTap,
    required this.onClose,
    required this.onMenu,
    this.groupColor,
    this.dropOnto = false,
  });

  final RepoTabController tab;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final void Function(Offset globalPosition) onMenu;

  /// Its group's color, underlining it.
  final Color? groupColor;

  /// A dragged tab would group with this one.
  final bool dropOnto;

  @override
  State<_RepoTab> createState() => _RepoTabState();
}

class _RepoTabState extends State<_RepoTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.tab,
      builder: (context, _) {
        final tab = widget.tab;
        final working =
            tab.busy != null || tab.fetching || (tab.loading && tab.started);
        return MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: Listener(
            onPointerDown: (e) {
              if (e.buttons == kMiddleMouseButton) widget.onClose();
            },
            child: GestureDetector(
              onTap: widget.onTap,
              onSecondaryTapUp: (d) => widget.onMenu(d.globalPosition),
              child: _tipWhenHovered(
                hover: _hover,
                message: tab.repo.path,
                child: Stack(
                  children: [
                    Container(
                      height: 36,
                      constraints: const BoxConstraints(
                        minWidth: 120,
                        maxWidth: 220,
                      ),
                      padding: const EdgeInsets.only(left: 12, right: 4),
                      foregroundDecoration: widget.dropOnto
                          ? BoxDecoration(
                              border: Border.all(
                                color: AppColors.accent,
                                width: 1.5,
                              ),
                            )
                          : null,
                      decoration: BoxDecoration(
                        color: widget.dropOnto
                            ? AppColors.selection
                            : widget.active
                            ? AppColors.toolbar
                            : (_hover ? AppColors.hover : null),
                        border: Border(
                          right: BorderSide(color: AppColors.border),
                          // (The progress bar draws it while working.)
                          top: BorderSide(
                            color: widget.active && !working
                                ? AppColors.accent
                                : Colors.transparent,
                            width: 2,
                          ),
                          bottom: BorderSide(
                            color: widget.groupColor ?? Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      // The minimum width can exceed a short name's: keep the
                      // close button at the right edge anyway.
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (tab.operation.name != 'none')
                                  Padding(
                                    padding: EdgeInsets.only(right: 6),
                                    child: Icon(
                                      Icons.warning_amber,
                                      size: 13,
                                      color: AppColors.warning,
                                    ),
                                  ),
                                Flexible(
                                  child: Text(
                                    tab.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: widget.active
                                          ? AppColors.text
                                          : AppColors.textDim,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 22,
                            child: (_hover || widget.active)
                                ? InkWell(
                                    onTap: widget.onClose,
                                    borderRadius: BorderRadius.circular(3),
                                    child: Icon(
                                      Icons.close,
                                      size: 14,
                                      color: AppColors.textDim,
                                    ),
                                  )
                                : null,
                          ),
                        ],
                      ),
                    ),
                    // Working: the top edge is an indeterminate progress
                    // bar, which unlike a spinner doesn't resize the tab.
                    if (working)
                      Positioned(
                        left: 0,
                        right: 1, // the tab's right border
                        top: 0,
                        height: 2,
                        child: _TabProgress(
                          key: const ValueKey('tab-progress'),
                          active: widget.active,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// An indeterminate progress bar along a tab's top edge: a segment sweeping
/// across a faint track, over and over. Built only while the tab works, so
/// the other tabs run no animation.
class _TabProgress extends StatefulWidget {
  const _TabProgress({super.key, required this.active});
  final bool active;

  @override
  State<_TabProgress> createState() => _TabProgressState();
}

class _TabProgressState extends State<_TabProgress>
    with SingleTickerProviderStateMixin {
  late final _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _sweep
        ..stop()
        ..value = 0.5; // a still segment, for those who asked for no motion
    } else if (!_sweep.isAnimating) {
      _sweep.repeat();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _TabProgressPainter(
            _sweep,
            AppColors.accent,
            track: widget.active ? 0.3 : 0.12,
          ),
        ),
      ),
    );
  }
}

class _TabProgressPainter extends CustomPainter {
  _TabProgressPainter(this.sweep, this.color, {required this.track})
    : super(repaint: sweep);

  final Animation<double> sweep;
  final Color color;

  /// The track's opacity.
  final double track;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..clipRect(Offset.zero & size)
      ..drawRect(
        Offset.zero & size,
        Paint()..color = color.withValues(alpha: track),
      );
    // Enters from the left, leaves on the right, quickest in the middle.
    final segment = size.width * 0.4;
    final at = Curves.easeInOut.transform(sweep.value);
    final x = -segment + (size.width + segment) * at;
    canvas.drawRect(
      Rect.fromLTWH(x, 0, segment, size.height),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_TabProgressPainter old) =>
      old.color != color || old.track != track || old.sweep != sweep;
}
