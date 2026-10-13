import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Moves the panel while its child is dragged (its title, say).
typedef MoveHandle = Widget Function(Widget child);

/// A window-like panel floating over the rest of the UI without blocking
/// it: dragged by a handle its [builder] places, resized from its edges and
/// corners, and always kept within the area it floats in. Put it in a
/// [Stack] filling that area.
class FloatingPanel extends StatefulWidget {
  const FloatingPanel({
    super.key,
    required this.size,
    this.minSize = const Size(600, 420),
    this.onResized,
    required this.builder,
  });

  /// The size it opens at (centered).
  final Size size;
  final Size minSize;

  /// Called with the new size when a resize ends.
  final ValueChanged<Size>? onResized;
  final Widget Function(BuildContext context, MoveHandle moveHandle) builder;

  @override
  State<FloatingPanel> createState() => _FloatingPanelState();
}

class _FloatingPanelState extends State<FloatingPanel> {
  /// Where and how big, as last placed; null until first laid out.
  Rect? _rect;
  Size _area = Size.zero;

  /// [r] within the area, no smaller than the minimum (or the area).
  Rect _fit(Rect r) {
    final w = r.width
        .clamp(min(widget.minSize.width, _area.width), _area.width)
        .toDouble();
    final h = r.height
        .clamp(min(widget.minSize.height, _area.height), _area.height)
        .toDouble();
    return Rect.fromLTWH(
      r.left.clamp(0.0, _area.width - w),
      r.top.clamp(0.0, _area.height - h),
      w,
      h,
    );
  }

  void _move(DragUpdateDetails d) =>
      setState(() => _rect = _fit(_rect!.shift(d.delta)));

  /// Moves the edges [dx] (-1 left, 1 right) and [dy] (-1 top, 1 bottom)
  /// with the pointer; the other ones stay.
  void _resize(DragUpdateDetails d, int dx, int dy) {
    final r = _rect!;
    var left = r.left, top = r.top, right = r.right, bottom = r.bottom;
    final minW = min(widget.minSize.width, _area.width);
    final minH = min(widget.minSize.height, _area.height);
    if (dx < 0) left = (left + d.delta.dx).clamp(0.0, right - minW);
    if (dx > 0) right = (right + d.delta.dx).clamp(left + minW, _area.width);
    if (dy < 0) top = (top + d.delta.dy).clamp(0.0, bottom - minH);
    if (dy > 0) {
      bottom = (bottom + d.delta.dy).clamp(top + minH, _area.height);
    }
    setState(() => _rect = Rect.fromLTRB(left, top, right, bottom));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        _area = c.biggest;
        final rect = _rect = _fit(
          _rect ??
              Rect.fromCenter(
                center: _area.center(Offset.zero),
                width: widget.size.width,
                height: widget.size.height,
              ),
        );
        Widget move(Widget child) => MouseRegion(
          cursor: SystemMouseCursors.move,
          child: GestureDetector(
            key: const ValueKey('panel-move'),
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onPanUpdate: _move,
            child: child,
          ),
        );
        Widget handle(Key key, int dx, int dy, MouseCursor cursor) =>
            MouseRegion(
              cursor: cursor,
              child: GestureDetector(
                key: key,
                behavior: HitTestBehavior.opaque,
                // From where the button went down: the edge stays under the
                // pointer.
                dragStartBehavior: DragStartBehavior.down,
                onPanUpdate: (d) => _resize(d, dx, dy),
                onPanEnd: (_) => widget.onResized?.call(_rect!.size),
              ),
            );
        const edge = 6.0, corner = 14.0;
        const updown = SystemMouseCursors.resizeUpDown;
        const leftright = SystemMouseCursors.resizeLeftRight;
        const nwse = SystemMouseCursors.resizeUpLeftDownRight;
        const nesw = SystemMouseCursors.resizeUpRightDownLeft;
        return Stack(
          children: [
            Positioned.fromRect(
              rect: rect,
              child: Material(
                key: const ValueKey('floating-panel'),
                color: AppColors.panel,
                elevation: 16,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: AppColors.border),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(child: widget.builder(context, move)),
                    Positioned(
                      left: corner,
                      right: corner,
                      top: 0,
                      height: edge,
                      child: handle(
                        const ValueKey('resize-top'),
                        0,
                        -1,
                        updown,
                      ),
                    ),
                    Positioned(
                      left: corner,
                      right: corner,
                      bottom: 0,
                      height: edge,
                      child: handle(
                        const ValueKey('resize-bottom'),
                        0,
                        1,
                        updown,
                      ),
                    ),
                    Positioned(
                      top: corner,
                      bottom: corner,
                      left: 0,
                      width: edge,
                      child: handle(
                        const ValueKey('resize-left'),
                        -1,
                        0,
                        leftright,
                      ),
                    ),
                    Positioned(
                      top: corner,
                      bottom: corner,
                      right: 0,
                      width: edge,
                      child: handle(
                        const ValueKey('resize-right'),
                        1,
                        0,
                        leftright,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      width: corner,
                      height: corner,
                      child: handle(
                        const ValueKey('resize-top-left'),
                        -1,
                        -1,
                        nwse,
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      width: corner,
                      height: corner,
                      child: handle(
                        const ValueKey('resize-top-right'),
                        1,
                        -1,
                        nesw,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      bottom: 0,
                      width: corner,
                      height: corner,
                      child: handle(
                        const ValueKey('resize-bottom-left'),
                        -1,
                        1,
                        nesw,
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      width: corner,
                      height: corner,
                      child: handle(
                        const ValueKey('resize-corner'),
                        1,
                        1,
                        nwse,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
