import 'package:flutter/material.dart';

import '../models/clean_models.dart';
import '../services/path_utils.dart';
import '../theme/app_theme.dart';

class CategoryIcon extends StatelessWidget {
  const CategoryIcon({super.key, required this.category, this.size = 40});

  final CleanCategory category;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_fg.withValues(alpha: 0.18), _fg.withValues(alpha: 0.08)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(_icon, color: _fg, size: size * 0.48),
    );
  }

  Color get _fg {
    switch (category) {
      case CleanCategory.systemCache:
        return AppColors.primary;
      case CleanCategory.browserCache:
        return const Color(0xFF7C3AED);
      case CleanCategory.appCache:
        return const Color(0xFF0EA5E9);
      case CleanCategory.systemLogs:
        return AppColors.warning;
      case CleanCategory.recycleBin:
        return AppColors.success;
      case CleanCategory.nvidiaCache:
        return const Color(0xFF059669);
      case CleanCategory.appLeftovers:
        return const Color(0xFFE11D48);
      case CleanCategory.downloads:
        return const Color(0xFF0284C7);
      case CleanCategory.memoryDumps:
        return const Color(0xFFDB2777);
      case CleanCategory.windowsUpdate:
        return AppColors.accent;
      case CleanCategory.registryJunk:
        return const Color(0xFF9333EA);
      case CleanCategory.usageTraces:
        return const Color(0xFFEA580C);
      case CleanCategory.softwareUsage:
        return const Color(0xFF0D9488);
    }
  }

  IconData get _icon {
    switch (category) {
      case CleanCategory.systemCache:
        return Icons.bolt_rounded;
      case CleanCategory.browserCache:
        return Icons.public_rounded;
      case CleanCategory.appCache:
        return Icons.apps_rounded;
      case CleanCategory.systemLogs:
        return Icons.article_outlined;
      case CleanCategory.recycleBin:
        return Icons.delete_outline_rounded;
      case CleanCategory.nvidiaCache:
        return Icons.memory_rounded;
      case CleanCategory.appLeftovers:
        return Icons.folder_delete_outlined;
      case CleanCategory.downloads:
        return Icons.download_rounded;
      case CleanCategory.memoryDumps:
        return Icons.bug_report_outlined;
      case CleanCategory.windowsUpdate:
        return Icons.system_update_alt_rounded;
      case CleanCategory.registryJunk:
        return Icons.handyman_rounded;
      case CleanCategory.usageTraces:
        return Icons.history_rounded;
      case CleanCategory.softwareUsage:
        return Icons.schedule_rounded;
    }
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = AppColors.primary,
    this.subtitle,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        color.withValues(alpha: 0.16),
                        color.withValues(alpha: 0.06),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.4,
                color: AppColors.textPrimary,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.action,
    this.actionLabel,
  });

  final String title;
  final VoidCallback? action;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              gradient: AppColors.gradientMain,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          if (action != null)
            TextButton(onPressed: action, child: Text(actionLabel ?? '查看全部')),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.actionLabel,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? action;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(constraints.maxHeight < 220 ? 12 : 22),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.12),
                      AppColors.accent.withValues(alpha: 0.08),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: constraints.maxHeight < 220 ? 28 : 38,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: action,
                  child: Text(actionLabel ?? '开始'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SizeText extends StatelessWidget {
  const SizeText(this.bytes, {super.key, this.style, this.highlight = false});

  final int bytes;
  final TextStyle? style;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Text(
      formatBytes(bytes),
      style:
          style ??
          TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
            color: highlight ? AppColors.primary : AppColors.textSecondary,
          ),
    );
  }
}

/// 页面统一外边距
const EdgeInsets kPagePadding = EdgeInsets.fromLTRB(28, 22, 28, 22);

/// 玻璃提示条
class InfoHint extends StatelessWidget {
  const InfoHint(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: message,
    child: Semantics(
      label: message,
      child: const Padding(
        padding: EdgeInsets.all(2),
        child: Icon(
          Icons.info_outline_rounded,
          size: 16,
          color: AppColors.textTertiary,
        ),
      ),
    ),
  );
}

class GlassBanner extends StatelessWidget {
  const GlassBanner({
    super.key,
    required this.icon,
    required this.text,
    this.color = AppColors.warning,
    this.background,
  });

  final IconData icon;
  final String text;
  final Color color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: (background ?? color).withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.18), width: 1.2),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
