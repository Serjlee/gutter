import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A dialog's content, resized by dragging its edges and corners. The dialog
/// stays centered, so it grows on both sides and the dragged edge follows
/// the pointer. It shrinks to fit a smaller window.
class ResizableBox extends StatefulWidget {
  const ResizableBox({
    super.key,
    required this.size,
    this.minSize = const Size(560, 400),
    this.onResized,
    required this.child,
  });

  /// The size it opens at.
  final Size size;
  final Size minSize;

  /// Called with the new size when a drag ends.
  final ValueChanged<Size>? onResized;
  final Widget child;

  @override
  State<ResizableBox> createState() => _ResizableBoxState();
}

class _ResizableBoxState extends State<ResizableBox> {
  late Size _size = widget.size;
  BoxConstraints _limits = const BoxConstraints();

  Size _fit(Size s) => Size(
    s.width.clamp(
      min(widget.minSize.width, _limits.maxWidth),
      _limits.maxWidth,
    ),
    s.height.clamp(
      min(widget.minSize.height, _limits.maxHeight),
      _limits.maxHeight,
    ),
  );

  /// Moves the edges [dx] (-1 left, 1 right) and [dy] (-1 top, 1 bottom).
  void _drag(DragUpdateDetails d, int dx, int dy) {
    final from = _fit(_size);
    setState(() {
      _size = _fit(
        Size(
          from.width + 2 * dx * d.delta.dx,
          from.height + 2 * dy * d.delta.dy,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        _limits = c;
        Widget handle(int dx, int dy, MouseCursor cursor) => MouseRegion(
          cursor: cursor,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // From where the button went down: the edge stays under the
            // pointer.
            dragStartBehavior: DragStartBehavior.down,
            onPanUpdate: (d) => _drag(d, dx, dy),
            onPanEnd: (_) => widget.onResized?.call(_fit(_size)),
          ),
        );
        const edge = 6.0, corner = 14.0;
        const updown = SystemMouseCursors.resizeUpDown;
        const leftright = SystemMouseCursors.resizeLeftRight;
        const nwse = SystemMouseCursors.resizeUpLeftDownRight;
        const nesw = SystemMouseCursors.resizeUpRightDownLeft;
        return SizedBox.fromSize(
          size: _fit(_size),
          child: Stack(
            children: [
              Positioned.fill(child: widget.child),
              Positioned(
                key: const ValueKey('resize-top'),
                left: corner,
                right: corner,
                top: 0,
                height: edge,
                child: handle(0, -1, updown),
              ),
              Positioned(
                key: const ValueKey('resize-bottom'),
                left: corner,
                right: corner,
                bottom: 0,
                height: edge,
                child: handle(0, 1, updown),
              ),
              Positioned(
                key: const ValueKey('resize-left'),
                top: corner,
                bottom: corner,
                left: 0,
                width: edge,
                child: handle(-1, 0, leftright),
              ),
              Positioned(
                key: const ValueKey('resize-right'),
                top: corner,
                bottom: corner,
                right: 0,
                width: edge,
                child: handle(1, 0, leftright),
              ),
              Positioned(
                left: 0,
                top: 0,
                width: corner,
                height: corner,
                child: handle(-1, -1, nwse),
              ),
              Positioned(
                right: 0,
                top: 0,
                width: corner,
                height: corner,
                child: handle(1, -1, nesw),
              ),
              Positioned(
                left: 0,
                bottom: 0,
                width: corner,
                height: corner,
                child: handle(-1, 1, nesw),
              ),
              Positioned(
                key: const ValueKey('resize-corner'),
                right: 0,
                bottom: 0,
                width: corner,
                height: corner,
                child: handle(1, 1, nwse),
              ),
            ],
          ),
        );
      },
    );
  }
}
