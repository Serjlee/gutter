import 'dart:math';

import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Where HEAD and the main/master remotes are in the whole list, drawn at
/// the right edge of the graph like scrollbar markers.
class ScrollMarks extends StatelessWidget {
  const ScrollMarks({
    super.key,
    required this.rowCount,
    required this.rowHeight,
    required this.head,
    required this.headColor,
    required this.trunk,
  });

  final int rowCount;
  final double rowHeight;
  final int? head;
  final Color headColor;
  final List<int> trunk;

  static Color get trunkColor => AppColors.trunk;

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: CustomPaint(painter: _MarksPainter(this)));
}

/// One mark: from [top] to [bottom] on the track (in pixels), in [color].
typedef ScrollMark = ({double top, double bottom, Color color});

/// The marks for the [head] and [trunk] rows on a track [height] tall, on
/// the scrollbar's scale: the whole list, or the track when the list is
/// shorter (then each mark is level with its row). A trunk mark that would
/// overlap HEAD's merges with it, in between the two colors.
List<ScrollMark> scrollMarks({
  required double height,
  required int rowCount,
  required double rowHeight,
  required int? head,
  required Color headColor,
  required List<int> trunk,
}) {
  if (rowCount == 0) return const [];
  final total = max(rowCount * rowHeight, height);
  double at(int row) => (row + 0.5) * rowHeight / total * height;
  final headAt = head == null ? null : at(head);
  final marks = <ScrollMark>[];
  var merged = false;
  for (final r in trunk) {
    final y = at(r);
    if (headAt != null && (y - headAt).abs() < 4) {
      merged = true;
      marks.add((
        top: min(y, headAt),
        bottom: max(y, headAt),
        color: Color.lerp(ScrollMarks.trunkColor, headColor, 0.5)!,
      ));
    } else {
      marks.add((top: y, bottom: y, color: ScrollMarks.trunkColor));
    }
  }
  if (headAt != null && !merged) {
    marks.add((top: headAt, bottom: headAt, color: headColor));
  }
  return marks;
}

class _MarksPainter extends CustomPainter {
  _MarksPainter(this.w);
  final ScrollMarks w;

  @override
  void paint(Canvas canvas, Size size) {
    final marks = scrollMarks(
      height: size.height,
      rowCount: w.rowCount,
      rowHeight: w.rowHeight,
      head: w.head,
      headColor: w.headColor,
      trunk: w.trunk,
    );
    for (final m in marks) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(0, m.top - 2, size.width, m.bottom + 2),
          const Radius.circular(1),
        ),
        Paint()..color = m.color,
      );
    }
  }

  @override
  bool shouldRepaint(_MarksPainter old) => true;
}
