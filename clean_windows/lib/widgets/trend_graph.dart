import 'package:flutter/material.dart';

/// Missing measurements break the line instead of inventing zero readings.
class TrendGraph extends StatelessWidget {
  const TrendGraph({
    super.key,
    required this.values,
    required this.color,
    this.height = 30,
  });
  final List<double?> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '最近 ${values.length} 次成功采样趋势',
    child: Tooltip(
      message: values.whereType<double>().isEmpty
          ? '暂无可用测量值'
          : '最近 ${values.length} 次成功采样 · 最低 ${values.whereType<double>().reduce((a, b) => a < b ? a : b).toStringAsFixed(1)} · 最高 ${values.whereType<double>().reduce((a, b) => a > b ? a : b).toStringAsFixed(1)}',
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _TrendPainter(values, color)),
      ),
    ),
  );
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.values, this.color);
  final List<double?> values;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = color.withValues(alpha: .1)
      ..strokeWidth = 1;
    for (final fraction in [.25, .75]) {
      canvas.drawLine(
        Offset(0, size.height * fraction),
        Offset(size.width, size.height * fraction),
        grid,
      );
    }
    final line = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    Offset? previous;
    final segment = <Offset>[];
    void paintArea() {
      if (segment.length >= 2) {
        final area = Path()..moveTo(segment.first.dx, size.height);
        for (final point in segment) {
          area.lineTo(point.dx, point.dy);
        }
        area.lineTo(segment.last.dx, size.height);
        area.close();
        canvas.drawPath(
          area,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: .18),
                color.withValues(alpha: .015),
              ],
            ).createShader(Offset.zero & size),
        );
      }
      segment.clear();
    }

    for (var i = 0; i < values.length; i++) {
      final value = values[i];
      if (value == null || !value.isFinite) {
        paintArea();
        previous = null;
        continue;
      }
      final point = Offset(
        size.width * (i + 60 - values.length) / 59,
        3 + (size.height - 6) * (1 - value.clamp(0, 100) / 100),
      );
      if (previous == null) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
      segment.add(point);
      previous = point;
    }
    paintArea();
    canvas.drawPath(path, line);
    if (previous != null) {
      canvas.drawCircle(previous, 3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_TrendPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}
