import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Open arc with a fixed footprint; missing values have no progress arc.
class ResourceDial extends StatelessWidget {
  const ResourceDial({
    super.key,
    required this.fraction,
    required this.color,
    required this.icon,
    this.size = 40,
    this.child,
  });
  final double? fraction;
  final Color color;
  final IconData icon;
  final double size;
  final Widget? child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: fraction?.clamp(0, 1) ?? 0),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 360),
    curve: Curves.easeOutCubic,
    builder: (_, value, child) => SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _DialPainter(fraction == null ? null : value, color),
        child: child,
      ),
    ),
    child:
        child ??
        Center(
          child: Icon(
            icon,
            size: 17,
            color: fraction == null
                ? Theme.of(context).colorScheme.onSurfaceVariant
                : color,
          ),
        ),
  );
}

class _DialPainter extends CustomPainter {
  const _DialPainter(this.fraction, this.color);
  final double? fraction;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(4);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const start = math.pi * .75, sweep = math.pi * 1.5;
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      stroke..color = color.withValues(alpha: .12),
    );
    if (fraction != null && fraction! > 0) {
      canvas.drawArc(
        rect,
        start,
        sweep * fraction!,
        false,
        stroke..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.fraction != fraction || old.color != color;
}
