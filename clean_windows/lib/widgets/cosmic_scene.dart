import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/clean_models.dart';
import '../services/path_utils.dart';

class CosmicColors {
  static const background = Color(0xFF070C20);
  static const panel = Color(0xE6101830);
  static const line = Color(0xFF263452);
  static const muted = Color(0xFF9BAECE);
  static const cyan = Color(0xFF70E5E5);
  static const violet = Color(0xFFB09BFF);
}

/// Smart cleanup uses the existing deletion service, with a narrower scope.
const cosmicSmartCategories = {
  CleanCategory.systemCache,
  CleanCategory.browserCache,
  CleanCategory.appCache,
  CleanCategory.nvidiaCache,
};

class CosmicBackdrop extends StatelessWidget {
  const CosmicBackdrop({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: CosmicColors.background,
    child: Stack(
      children: [
        const Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(child: CustomPaint(painter: _Starfield())),
          ),
        ),
        child,
      ],
    ),
  );
}

class _Starfield extends CustomPainter {
  const _Starfield();
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    for (final cloud in const [
      (x: .65, y: .25, color: Color(0x384A31A0)),
      (x: .97, y: .62, color: Color(0x25249AB6)),
      (x: .07, y: .85, color: Color(0x223B469F)),
    ]) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader =
              RadialGradient(
                colors: [cloud.color, cloud.color.withValues(alpha: 0)],
              ).createShader(
                Rect.fromCircle(
                  center: Offset(size.width * cloud.x, size.height * cloud.y),
                  radius: size.width * .65,
                ),
              ),
      );
    }
    final random = math.Random(82);
    for (var i = 0; i < 180; i++) {
      final point = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      final radius = random.nextDouble() * 1.1 + .25;
      canvas.drawCircle(
        point,
        radius,
        Paint()
          ..color = Colors.white.withValues(
            alpha: random.nextDouble() * .55 + .12,
          ),
      );
      if (i % 23 == 0) {
        final paint = Paint()
          ..color = CosmicColors.cyan.withValues(alpha: .35)
          ..strokeWidth = .7;
        canvas.drawLine(
          point - const Offset(4, 0),
          point + const Offset(4, 0),
          paint,
        );
        canvas.drawLine(
          point - const Offset(0, 4),
          point + const Offset(0, 4),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_Starfield oldDelegate) => false;
}

class CosmicOrbit extends StatefulWidget {
  const CosmicOrbit({
    super.key,
    required this.scanning,
    required this.cleaning,
    required this.progress,
    required this.hasResults,
    required this.center,
    required this.results,
    required this.onCategory,
    this.celebrating = false,
  });
  final bool scanning, cleaning, hasResults, celebrating;
  final double progress;
  final Widget center;
  final Map<CleanCategory, ScanCategory> results;
  final ValueChanged<CleanCategory> onCategory;
  @override
  State<CosmicOrbit> createState() => _CosmicOrbitState();
}

class _CosmicOrbitState extends State<CosmicOrbit>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );
  Offset _pointer = Offset.zero;
  static const _satellites = [
    (
      category: CleanCategory.systemCache,
      label: '系统',
      icon: Icons.memory_rounded,
      angle: -2.65,
      color: CosmicColors.cyan,
    ),
    (
      category: CleanCategory.browserCache,
      label: '浏览器',
      icon: Icons.public_rounded,
      angle: -.6,
      color: CosmicColors.violet,
    ),
    (
      category: CleanCategory.appCache,
      label: '软件',
      icon: Icons.apps_rounded,
      angle: 2.62,
      color: Color(0xFF91BEFF),
    ),
    (
      category: CleanCategory.nvidiaCache,
      label: '显卡',
      icon: Icons.bolt_rounded,
      angle: .6,
      color: Color(0xFFF5C985),
    ),
  ];
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant CosmicOrbit oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  void _syncMotion() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.stop();
      return;
    }
    if (widget.scanning || widget.cleaning) {
      if (!_motion.isAnimating) _motion.repeat();
    } else {
      _motion.stop();
      if (widget.celebrating) _motion.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final side = math.min(
        constraints.maxWidth,
        widget.hasResults ? 280.0 : 390.0,
      );
      final radius = side * .40;
      return Center(
        child: SizedBox(
          width: side,
          height: side,
          child: MouseRegion(
            onHover: (event) {
              if (MediaQuery.disableAnimationsOf(context)) return;
              setState(
                () => _pointer =
                    (event.localPosition - Offset(side / 2, side / 2)) / 45,
              );
            },
            onExit: (_) => setState(() => _pointer = Offset.zero),
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 240),
              transform: Matrix4.translationValues(_pointer.dx, _pointer.dy, 0),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _OrbitPainter(
                            animation: _motion,
                            scanning: widget.scanning,
                            cleaning: widget.cleaning,
                            progress: widget.progress,
                            celebrating: widget.celebrating,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: side * .50,
                    height: side * .50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        center: Alignment(-.5, -.5),
                        colors: [
                          Color(0xFF3D6592),
                          Color(0xFF293B7A),
                          Color(0xFF121936),
                        ],
                      ),
                      border: Border.all(
                        color: CosmicColors.cyan.withValues(alpha: .45),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: CosmicColors.violet.withValues(alpha: .2),
                          blurRadius: 55,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: Center(child: widget.center),
                  ),
                  for (final node in _satellites)
                    Positioned(
                      left: side / 2 + math.cos(node.angle) * radius - 35,
                      top: side / 2 + math.sin(node.angle) * radius - 35,
                      width: 70,
                      height: 76,
                      child: Tooltip(
                        message:
                            widget.hasResults &&
                                widget.results.containsKey(node.category)
                            ? '查看${node.category.title}'
                            : '${node.category.title} · 等待扫描',
                        child: TextButton(
                          key: ValueKey('orbit-${node.category.name}'),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            foregroundColor: node.color,
                            disabledForegroundColor: node.color.withValues(
                              alpha: .55,
                            ),
                          ),
                          onPressed:
                              widget.hasResults &&
                                  widget.results.containsKey(node.category)
                              ? () => widget.onCategory(node.category)
                              : null,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedContainer(
                                duration:
                                    MediaQuery.disableAnimationsOf(context)
                                    ? Duration.zero
                                    : const Duration(milliseconds: 300),
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF15223D),
                                  border: Border.all(
                                    color: node.color.withValues(
                                      alpha:
                                          widget.results.containsKey(
                                                node.category,
                                              ) &&
                                              widget.hasResults
                                          ? .8
                                          : .25,
                                    ),
                                  ),
                                  boxShadow: [
                                    if (widget.results.containsKey(
                                          node.category,
                                        ) &&
                                        widget.hasResults)
                                      BoxShadow(
                                        color: node.color.withValues(
                                          alpha: .15,
                                        ),
                                        blurRadius: 16,
                                      ),
                                  ],
                                ),
                                child: Icon(node.icon, size: 18),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                node.label,
                                style: const TextStyle(fontSize: 11),
                              ),
                              if (widget.hasResults &&
                                  widget.results.containsKey(node.category))
                                Text(
                                  formatBytes(
                                    widget
                                        .results[node.category]!
                                        .totalSizeBytes,
                                  ),
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: node.color,
                                  ),
                                ),
                            ],
                          ),
                        ),
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

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({
    required this.animation,
    required this.scanning,
    required this.cleaning,
    required this.progress,
    required this.celebrating,
  }) : super(repaint: animation);
  final Animation<double> animation;
  final bool scanning, cleaning, celebrating;
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width * .34;
    final orbit = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8
      ..color = CosmicColors.cyan.withValues(alpha: .15);
    canvas.drawCircle(center, radius, orbit);
    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: radius * 2.8,
        height: radius * 1.3,
      ),
      orbit,
    );
    canvas.drawCircle(
      center,
      radius * 1.16,
      orbit..color = CosmicColors.violet.withValues(alpha: .10),
    );
    final ring = Rect.fromCircle(center: center, radius: size.width * .275);
    canvas.drawArc(
      ring,
      -math.pi / 2,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withValues(alpha: .06),
    );
    final value = scanning ? progress.clamp(0.0, 1.0) : 1.0;
    canvas.drawArc(
      ring,
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(
          colors: [CosmicColors.violet, CosmicColors.cyan, CosmicColors.violet],
        ).createShader(ring),
    );
    if (scanning || cleaning) {
      final angle = animation.value * math.pi * 2 - math.pi / 2;
      final point = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      canvas.drawCircle(
        point,
        5,
        Paint()
          ..color = CosmicColors.cyan
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawCircle(point, 2.5, Paint()..color = Colors.white);
      for (var i = 0; i < 14; i++) {
        final phase = (animation.value + i / 14) % 1;
        final a = i * 2.399;
        final distance = cleaning ? radius * (1 - phase) : radius * phase;
        canvas.drawCircle(
          center + Offset(math.cos(a), math.sin(a)) * distance,
          1.5,
          Paint()..color = CosmicColors.cyan.withValues(alpha: .6),
        );
      }
    }
    if (celebrating && animation.value < 1) {
      canvas.drawCircle(
        center,
        size.width * (.27 + animation.value * .25),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = CosmicColors.cyan.withValues(
            alpha: (1 - animation.value) * .6,
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_OrbitPainter oldDelegate) =>
      scanning != oldDelegate.scanning ||
      cleaning != oldDelegate.cleaning ||
      progress != oldDelegate.progress ||
      celebrating != oldDelegate.celebrating;
}
