import 'package:flutter/material.dart';

const monitorInk = Color(0xFF122735);
const monitorPanel = Color(0xFF1C3544);
const monitorMuted = Color(0xFFB1C5D2);
const monitorCyan = Color(0xFF8DDFDA);
const monitorBlue = Color(0xFF9EBEFF);

class MonitorSurface extends StatelessWidget {
  const MonitorSurface({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: monitorCyan,
        surface: monitorPanel,
      ),
      iconTheme: const IconThemeData(color: monitorCyan),
      dialogTheme: Theme.of(context).dialogTheme.copyWith(
        backgroundColor: monitorPanel,
        titleTextStyle: const TextStyle(
          fontFamily: 'Segoe UI',
          color: Colors.white,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: 'Segoe UI',
          color: monitorMuted,
          fontSize: 14,
        ),
      ),
      textTheme: Theme.of(context).textTheme
          .apply(bodyColor: Colors.white, displayColor: Colors.white),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: monitorCyan,
          disabledForegroundColor: monitorMuted.withValues(alpha: .55),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: monitorCyan,
          backgroundColor: monitorPanel,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: monitorCyan),
      ),
    ),
    child: Material(
      color: monitorInk,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(painter: _Grid(), child: child),
    ),
  );
}

class MonitorTile extends StatelessWidget {
  const MonitorTile({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: monitorPanel,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: Color(0xFF365464), width: 1.2),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    ),
  );
}

class _Grid extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x0A9BE4DF)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _Grid oldDelegate) => false;
}
