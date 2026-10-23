import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/clean_models.dart';
import '../services/path_utils.dart';
import '../state/app_state.dart';

/// One workspace and one set of reviewable snapshots for both entry points.
class SpaceCleanupPanel extends StatelessWidget {
  const SpaceCleanupPanel({super.key, required this.onViewResults});
  final VoidCallback onViewResults;

  Future<void> _scan(BuildContext context, AppState state) async {
    try {
      await state.scanSpaceCleanup();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('空间扫描未完成，已读取的结果保留供查看')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final busy =
        state.scanning ||
        state.cleaning ||
        state.savingOptions ||
        state.systemCleanup.busy;
    final results = state.categories
        .where((s) => spaceCleanupScanCategories.contains(s.category))
        .toList();
    final total = results.fold(0, (n, s) => n + s.totalSizeBytes);
    final selected = results.fold(0, (n, s) => n + s.selectedSizeBytes);
    final count = results.fold(0, (n, s) => n + s.items.length);
    final hasResults = state.scanGeneration > 0 && results.isNotEmpty;
    return Container(
      key: const ValueKey('space-cleanup-panel'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.cleaning_services_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '空间清理',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              Tooltip(
                message: '扩展扫描旧日志、崩溃转储与使用痕迹；复用概览的扫描结果。新增内容需手动勾选，不扫描组件存储或浏览器会话。',
                child: Icon(
                  Icons.info_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (hasResults)
            Wrap(
              spacing: 18,
              runSpacing: 6,
              children: [
                Text(
                  '可审查 ${formatBytes(total)}',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '$count 项 · 已选 ${formatBytes(selected)}',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            )
          else
            const Text(
              '临时文件 · 软件缓存 · 旧日志 · 转储 · 使用痕迹',
              style: TextStyle(fontSize: 12),
            ),
          if (state.scanning) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: state.progress.totalCategories > 0
                  ? state.progress.completedCategories /
                        state.progress.totalCategories
                  : null,
            ),
            const SizedBox(height: 8),
            Text(state.progress.message, style: const TextStyle(fontSize: 12)),
            if (state.progress.currentPath.isNotEmpty)
              Text(
                state.progress.currentPath,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
          ],
          if (!state.scanning && state.scanError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                state.scanError!,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const ValueKey('scan-space-cleanup'),
                onPressed: busy ? null : () => _scan(context, state),
                icon: const Icon(Icons.radar_rounded),
                label: Text(hasResults ? '重新扫描空间' : '扫描空间'),
              ),
              if (state.scanning)
                TextButton.icon(
                  onPressed: state.cancelScan,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('取消扫描'),
                ),
              TextButton.icon(
                onPressed: onViewResults,
                icon: const Icon(Icons.chevron_right_rounded),
                label: const Text('查看与清理'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
