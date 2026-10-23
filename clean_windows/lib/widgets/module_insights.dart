import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'common.dart';

export '../services/file_types.dart';

const insightColors = <Color>[
  AppColors.primary,
  AppColors.accent,
  AppColors.success,
  AppColors.warning,
  Color(0xFF82718B),
  AppColors.textTertiary,
];

class InsightSegment {
  const InsightSegment({
    required this.label,
    required this.amount,
    required this.value,
    required this.color,
    this.onTap,
    this.selected = false,
  });
  final String label;
  final double amount;
  final String value;
  final Color color;
  final VoidCallback? onTap;
  final bool selected;
}

/// Compact, real-data distribution. Segment buttons filter or navigate; they
/// never change destructive selections.
class ModuleInsights extends StatelessWidget {
  const ModuleInsights({
    super.key,
    required this.label,
    required this.value,
    required this.segments,
    this.hint,
    this.busy = false,
    this.icon = Icons.donut_small_rounded,
  });
  final String label;
  final String value;
  final String? hint;
  final List<InsightSegment> segments;
  final bool busy;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: Theme.of(context).colorScheme.outlineVariant,
        width: 1.2,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 660;
              final heading = Row(
                children: [
                  Semantics(
                    label: '$label，$value',
                    child: SizedBox.square(
                      dimension: compact ? 48 : 64,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: 1),
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 450),
                            builder: (context, t, _) => CustomPaint(
                              size: Size.square(compact ? 48 : 64),
                              painter: _DistributionPainter(segments, t),
                            ),
                          ),
                          Icon(
                            icon,
                            color: Theme.of(context).colorScheme.primary,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            if (hint != null) InfoHint(hint!),
                          ],
                        ),
                        const SizedBox(height: 4),
                        AnimatedSwitcher(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 200),
                          layoutBuilder: (current, previous) => Stack(
                            alignment: Alignment.centerLeft,
                            children: [...previous, ?current],
                          ),
                          child: Text(
                            value,
                            key: ValueKey(value),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 26,
                              color: AppColors.textPrimary,
                              fontFeatures: [FontFeature.tabularFigures()],
                              height: 1.15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
              final legend = Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final segment in segments) _SegmentButton(segment),
                ],
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    heading,
                    if (segments.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      legend,
                    ],
                  ],
                );
              }
              return Row(
                children: [
                  SizedBox(width: 280, child: heading),
                  const SizedBox(width: 18),
                  Expanded(child: legend),
                ],
              );
            },
          ),
        ),
        if (busy) const LinearProgressIndicator(minHeight: 2),
      ],
    ),
  );
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton(this.segment);
  final InsightSegment segment;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: segment.selected,
    child: Material(
      color: segment.selected
          ? segment.color.withValues(alpha: .12)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: ValueKey('insight-${segment.label}'),
        onTap: segment.onTap,
        borderRadius: BorderRadius.circular(10),
        child: Tooltip(
          message:
              '${segment.label} · ${segment.value}${segment.onTap == null ? '' : ' · 点击查看'}',
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(maxWidth: 215),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                width: 1.2,
                color: segment.selected
                    ? segment.color.withValues(alpha: .4)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _segmentIcon(segment.label),
                  size: 14,
                  color: segment.color,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    segment.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  segment.value,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: segment.color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _DistributionPainter extends CustomPainter {
  _DistributionPainter(this.segments, this.progress);
  final List<InsightSegment> segments;
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(5);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7;
    canvas.drawOval(rect, paint..color = AppColors.border);
    final total = segments.fold<double>(
      0,
      (sum, s) => sum + math.max(0, s.amount),
    );
    if (total <= 0) return;
    var start = -math.pi / 2;
    for (final segment in segments) {
      final sweep =
          math.max(0, segment.amount) / total * math.pi * 2 * progress;
      if (sweep > .01) {
        canvas.drawArc(
          rect,
          start,
          math.max(.001, sweep - .04),
          false,
          paint..color = segment.color,
        );
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DistributionPainter oldDelegate) => true;
}

class ShareBar extends StatelessWidget {
  const ShareBar({
    super.key,
    required this.fraction,
    this.color = AppColors.primary,
  });
  final double fraction;
  final Color color;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: fraction.clamp(0, 1)),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 320),
    curve: Curves.easeOutCubic,
    builder: (_, value, _) => ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 4,
        color: color,
        backgroundColor: color.withValues(alpha: .08),
      ),
    ),
  );
}

IconData _segmentIcon(String label) => switch (label) {
  '压缩 / 镜像' => Icons.folder_zip_rounded,
  '影音' => Icons.movie_rounded,
  '安装包' => Icons.install_desktop_rounded,
  '其他' => Icons.more_horiz_rounded,
  '已启用' => Icons.play_circle_rounded,
  '已禁用' => Icons.pause_circle_rounded,
  '状态未知' || '未知大小' => Icons.help_outline_rounded,
  '已知大小' => Icons.pie_chart_rounded,
  '显示全部' => Icons.apps_rounded,
  '扫描范围' => Icons.radar_rounded,
  '行为设置' => Icons.tune_rounded,
  '已关闭' => Icons.remove_circle_outline_rounded,
  _ => Icons.circle,
};
