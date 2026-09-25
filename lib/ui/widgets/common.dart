import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../git/models.dart';

/// Vertical drag handle between two panes.
class ResizeHandle extends StatelessWidget {
  const ResizeHandle({super.key, required this.onDrag, this.onEnd});

  final ValueChanged<double> onDrag;
  final VoidCallback? onEnd;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
        onHorizontalDragEnd: (_) => onEnd?.call(),
        child: const SizedBox(
          width: 5,
          child: Center(
            child: VerticalDivider(width: 1, color: AppColors.border),
          ),
        ),
      ),
    );
  }
}

/// Small toolbar button with icon above a label, GitKraken style.
class ToolbarButton extends StatelessWidget {
  const ToolbarButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.tooltip,
    this.busy = false,
    this.menu,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool busy;

  /// Optional dropdown shown by a small arrow.
  final List<PopupMenuEntry<VoidCallback>>? menu;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final color = enabled ? AppColors.text : AppColors.textFaint;
    final hasMenu = menu != null;
    final iconBox = SizedBox(
      height: 20,
      width: 20,
      child: busy
          ? const Padding(
              padding: EdgeInsets.all(2),
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 19, color: color),
    );
    // Every button has the same width, whatever its label; the icon and the
    // label are centered in it. A menu's arrow sits right of the icon.
    Widget button = InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              iconBox,
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: color),
              ),
            ],
          ),
        ),
      ),
    );
    if (tooltip != null) button = Tooltip(message: tooltip, child: button);
    if (hasMenu) {
      // The arrow is a button of its own, from the icon to the button's
      // right edge and from its top down to the label.
      button = Stack(
        children: [
          button,
          Positioned(
            top: 0,
            right: 0,
            width: _arrowSlot,
            height: 4 + 20 + 2,
            child: PopupMenuButton<VoidCallback>(
              popUpAnimationStyle: AnimationStyle.noAnimation,
              tooltip: 'More options',
              itemBuilder: (_) => menu!,
              onSelected: (cb) => cb(),
              borderRadius: BorderRadius.circular(4),
              child: const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    height: 20,
                    child: Icon(
                      Icons.arrow_drop_down,
                      size: 18,
                      color: AppColors.textDim,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    // Its own (transparent) Material: ink is painted on the nearest one,
    // which would otherwise sit under the toolbar's background.
    return Material(type: MaterialType.transparency, child: button);
  }

  /// Width of every toolbar button, with or without a menu.
  static const width = 60.0;

  /// Width of the menu arrow's button, between the icon and the edge.
  static const _arrowSlot = (width - 20) / 2;
}

PopupMenuItem<VoidCallback> menuItem(
  String label,
  VoidCallback onTap, {
  IconData? icon,
  bool enabled = true,
  bool danger = false,
}) {
  return PopupMenuItem<VoidCallback>(
    value: onTap,
    enabled: enabled,
    height: 34,
    child: Row(
      children: [
        SizedBox(
          width: 24,
          child: icon == null
              ? null
              : Icon(
                  icon,
                  size: 16,
                  color: danger ? AppColors.danger : AppColors.textDim,
                ),
        ),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: !enabled
                  ? AppColors.textFaint
                  : (danger ? AppColors.danger : AppColors.text),
            ),
          ),
        ),
      ],
    ),
  );
}

/// A compact dropdown that opens instantly (Flutter's DropdownButton has a
/// fixed open animation).
class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.style,
    this.expand = false,
  });

  final T value;

  /// (value, label, color) triples.
  final List<(T, String, Color?)> items;
  final ValueChanged<T> onChanged;
  final TextStyle? style;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final current = items.firstWhere(
      (i) => i.$1 == value,
      orElse: () => items.first,
    );
    final base = style ?? const TextStyle(fontSize: 13, color: AppColors.text);
    final label = Text(
      current.$2,
      overflow: TextOverflow.ellipsis,
      style: current.$3 == null ? base : base.copyWith(color: current.$3),
    );
    return PopupMenuButton<T>(
      tooltip: '',
      popUpAnimationStyle: AnimationStyle.noAnimation,
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final (v, text, color) in items)
          PopupMenuItem<T>(
            value: v,
            height: 32,
            child: Text(
              text,
              style: color == null ? base : base.copyWith(color: color),
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          children: [
            if (expand) Expanded(child: label) else label,
            const Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: AppColors.textDim,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows a context menu at a global pointer position (zoom-aware).
Future<void> showContextMenu(
  BuildContext context,
  Offset globalPosition,
  List<PopupMenuEntry<VoidCallback>> items,
) async {
  if (items.isEmpty) return;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final local = overlay.globalToLocal(globalPosition);
  final cb = await showMenu<VoidCallback>(
    context: context,
    popUpAnimationStyle: AnimationStyle.noAnimation,
    position: RelativeRect.fromRect(
      Rect.fromLTWH(local.dx, local.dy, 0, 0),
      Offset.zero & overlay.size,
    ),
    items: items,
  );
  cb?.call();
}

/// Section header used in side panels.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.count,
    this.expanded,
    this.onToggle,
    this.actions = const [],
  });

  final String title;
  final int? count;
  final bool? expanded;
  final VoidCallback? onToggle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Container(
        height: 30,
        padding: const EdgeInsets.only(left: 6, right: 4),
        color: AppColors.panelAlt,
        child: Row(
          children: [
            if (expanded != null)
              Icon(
                expanded! ? Icons.expand_more : Icons.chevron_right,
                size: 16,
                color: AppColors.textDim,
              ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                title.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: AppColors.textDim,
                ),
              ),
            ),
            if (count != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textFaint,
                  ),
                ),
              ),
            ...actions,
          ],
        ),
      ),
    );
  }
}

class SmallIconButton extends StatelessWidget {
  const SmallIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
    this.size = 16,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      // Own Material so the ink shows on colored backgrounds.
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              icon,
              size: size,
              color: onPressed == null
                  ? AppColors.textFaint
                  : (color ?? AppColors.textDim),
            ),
          ),
        ),
      ),
    );
  }
}

/// Colored letter badge for a change kind (M, A, D, R, ...).
class ChangeKindBadge extends StatelessWidget {
  const ChangeKindBadge(this.kind, {super.key});
  final ChangeKind kind;

  static (String, Color) info(ChangeKind k) => switch (k) {
    ChangeKind.added => ('A', AppColors.success),
    ChangeKind.untracked => ('U', AppColors.success),
    ChangeKind.modified => ('M', AppColors.warning),
    ChangeKind.typeChanged => ('T', AppColors.warning),
    ChangeKind.deleted => ('D', AppColors.danger),
    ChangeKind.renamed => ('R', AppColors.accent),
    ChangeKind.copied => ('C', AppColors.accent),
    ChangeKind.conflicted => ('!', AppColors.danger),
    ChangeKind.unknown => ('?', AppColors.textDim),
  };

  @override
  Widget build(BuildContext context) {
    final (letter, color) = info(kind);
    return Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// Path with dimmed directory and bright file name.
class PathLabel extends StatelessWidget {
  const PathLabel(this.path, {super.key, this.oldPath, this.fontSize = 12.5});
  final String path;
  final String? oldPath;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final i = path.lastIndexOf('/');
    final dir = i < 0 ? '' : path.substring(0, i + 1);
    final file = i < 0 ? path : path.substring(i + 1);
    return Text.rich(
      TextSpan(
        children: [
          if (oldPath != null && oldPath != path)
            TextSpan(
              text: '$oldPath → ',
              style: const TextStyle(color: AppColors.textFaint),
            ),
          TextSpan(
            text: dir,
            style: const TextStyle(color: AppColors.textDim),
          ),
          TextSpan(
            text: file,
            style: const TextStyle(color: AppColors.text),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: fontSize),
    );
  }
}

Future<void> copyToClipboard(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
}

/// [path] for display, with the home folder shortened to `~`.
String displayPath(String path, {String? home}) {
  home ??= Platform.environment['HOME'];
  if (home == null || home.isEmpty || home == '/') return path;
  if (path == home) return '~';
  final prefix = home.endsWith('/') ? home : '$home/';
  return path.startsWith(prefix) ? '~/${path.substring(prefix.length)}' : path;
}

String formatDate(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

String relativeTime(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays < 30) return '${diff.inDays} d ago';
  return formatDate(d).substring(0, 10);
}

/// Opens a file or URL with the platform's default handler.
Future<void> openWithSystem(String target) async {
  final cmd = Platform.isMacOS
      ? 'open'
      : Platform.isWindows
      ? 'explorer'
      : 'xdg-open';
  await Process.start(cmd, [target], mode: ProcessStartMode.detached);
}
