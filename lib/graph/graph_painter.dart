import 'package:flutter/material.dart';

import '../app/theme.dart';
import 'graph_layout.dart';

/// Geometry shared by the graph painter and the graph column width.
class GraphMetrics {
  const GraphMetrics({this.laneWidth = 22, this.rowHeight = 30});

  final double laneWidth;
  final double rowHeight;
  double get nodeRadius => 9.5;
  double get lineWidth => 2;
  double laneX(int lane) => laneWidth * lane + laneWidth / 2 + 6;
  double widthFor(int lanes) => laneWidth * lanes + 12;
}

enum NodeStyle { commit, merge, wip }

/// Paints one row of the commit graph: lower halves of the incoming edges,
/// upper halves of the outgoing ones, and the node.
class GraphRowPainter extends CustomPainter {
  GraphRowPainter({
    required this.layout,
    required this.row,
    required this.metrics,
    required this.style,
    required this.initials,
    this.isHead = false,
    this.dimmed = false,
  });

  final GraphLayout layout;
  final int row;
  final GraphMetrics metrics;
  final NodeStyle style;
  final String initials;
  final bool isHead;
  final bool dimmed;

  static final _textCache = <String, TextPainter>{};

  static TextPainter _initialsPainter(String text) {
    return _textCache.putIfAbsent(text, () {
      return TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 8.5,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final h = metrics.rowHeight;
    final cy = h / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = metrics.lineWidth
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final alpha = dimmed ? 0.35 : 1.0;

    Color c(int color) => AppColors.lane(color).withValues(alpha: alpha);

    // Incoming edges (from row-1), drawn in the top half.
    if (row > 0) {
      final start = layout.edgeOffsets[row - 1];
      final end = layout.edgeOffsets[row];
      for (var e = start; e < end; e++) {
        final from = layout.edges[e * 4];
        final to = layout.edges[e * 4 + 1];
        final color = layout.edges[e * 4 + 2];
        final kind = layout.edges[e * 4 + 3];
        paint.color = c(color);
        final x2 = metrics.laneX(to);
        if (kind == EdgeKind.intoNode) {
          // Down the lane, then a rounded corner into the node.
          final x1 = metrics.laneX(from);
          final r = _cornerRadius(x2 - x1, cy);
          final sign = x2 > x1 ? 1.0 : -1.0;
          final path = Path()
            ..moveTo(x1, 0)
            ..lineTo(x1, cy - r)
            ..quadraticBezierTo(x1, cy, x1 + sign * r, cy)
            ..lineTo(x2, cy);
          canvas.drawPath(path, paint);
        } else {
          canvas.drawLine(Offset(x2, 0), Offset(x2, cy), paint);
        }
      }
    }

    // Outgoing edges (to row+1), drawn in the bottom half.
    final start = layout.edgeOffsets[row];
    final end = layout.edgeOffsets[row + 1];
    for (var e = start; e < end; e++) {
      final from = layout.edges[e * 4];
      final to = layout.edges[e * 4 + 1];
      final color = layout.edges[e * 4 + 2];
      final kind = layout.edges[e * 4 + 3];
      paint.color = c(color);
      final x1 = metrics.laneX(from);
      if (kind == EdgeKind.fromNode) {
        // Out of the node sideways, then a rounded corner down the lane.
        final x2 = metrics.laneX(to);
        final r = _cornerRadius(x2 - x1, cy);
        final sign = x2 > x1 ? 1.0 : -1.0;
        final path = Path()
          ..moveTo(x1, cy)
          ..lineTo(x2 - sign * r, cy)
          ..quadraticBezierTo(x2, cy, x2, cy + r)
          ..lineTo(x2, h);
        canvas.drawPath(path, paint);
      } else {
        canvas.drawLine(Offset(x1, cy), Offset(x1, h), paint);
      }
    }

    // Node.
    final lane = layout.nodeLane[row];
    final color = c(layout.nodeColor[row]);
    final center = Offset(metrics.laneX(lane), cy);
    switch (style) {
      case NodeStyle.wip:
        final p = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color;
        _drawDashedCircle(canvas, center, metrics.nodeRadius - 1.5, p);
        canvas.drawCircle(
          center,
          metrics.nodeRadius - 3,
          Paint()..color = AppColors.background,
        );
      case NodeStyle.merge:
        canvas.drawCircle(center, 5, Paint()..color = color);
      case NodeStyle.commit:
        final r = metrics.nodeRadius;
        canvas.drawCircle(center, r, Paint()..color = color);
        canvas.drawCircle(
          center,
          r - 2,
          Paint()
            ..color = Color.lerp(
              AppColors.lane(layout.nodeColor[row]),
              Colors.black,
              0.45,
            )!.withValues(alpha: alpha),
        );
        final tp = _initialsPainter(initials);
        tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    }
    if (isHead) {
      canvas.drawCircle(
        center,
        metrics.nodeRadius + 2.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white.withValues(alpha: 0.85),
      );
    }
  }

  static double _cornerRadius(double dx, double half) {
    final a = dx.abs();
    return a < half ? a : half;
  }

  void _drawDashedCircle(Canvas canvas, Offset c, double r, Paint p) {
    const dashes = 10;
    const sweep = 3.14159265 * 2 / dashes;
    final rect = Rect.fromCircle(center: c, radius: r);
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect, i * sweep, sweep * 0.55, false, p);
    }
  }

  @override
  bool shouldRepaint(GraphRowPainter old) =>
      old.layout != layout ||
      old.row != row ||
      old.style != style ||
      old.isHead != isHead ||
      old.dimmed != dimmed ||
      old.initials != initials ||
      old.metrics.laneWidth != metrics.laneWidth;
}
