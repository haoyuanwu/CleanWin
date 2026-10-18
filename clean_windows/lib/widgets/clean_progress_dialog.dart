import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/clean_models.dart';
import '../services/path_utils.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// 清理进度 + 结果弹窗
class CleanProgressDialog extends StatefulWidget {
  const CleanProgressDialog({super.key, this.categories});
  final Set<CleanCategory>? categories;

  @override
  State<CleanProgressDialog> createState() => _CleanProgressDialogState();
}

class _CleanProgressDialogState extends State<CleanProgressDialog> {
  double _ratio = 0;
  String _current = '准备清理…';
  int _done = 0;
  int _total = 0;
  int _freed = 0;
  CleanReport? _report;
  bool _running = true;
  bool _cancelling = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted) return;
    final state = context.read<AppState>();
    final total = state.results.values
        .where(
          (category) =>
              widget.categories == null ||
              widget.categories!.contains(category.category),
        )
        .expand((category) => category.items)
        .where((item) => item.selected)
        .length;
    setState(() {
      _total = total;
      _done = 0;
    });

    try {
      final report = await state.cleanSelected(
        categories: widget.categories,
        onProgress: (item, message, done, totalItems) {
          if (!mounted) return;
          setState(() {
            _current = message;
            _done = done;
            _total = totalItems;
            _ratio = totalItems == 0 ? 1 : done / totalItems;
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _report = report;
        if (!report.cancelled) _ratio = 1;
        _freed = report.freedBytes;
        _current = report.cancelled ? '已取消清理' : '清理完成';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = '清理未完成，请重新扫描后重试。');
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final journalError = context.watch<AppState>().journal.error;

    return PopScope(
      canPop: !_running,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              _running
                  ? Icons.cleaning_services_rounded
                  : _error != null
                  ? Icons.error_outline_rounded
                  : report?.cancelled == true
                  ? Icons.stop_circle_outlined
                  : Icons.check_circle_rounded,
              color: _error != null
                  ? AppColors.warning
                  : report?.cancelled == true
                  ? AppColors.textSecondary
                  : _running
                  ? AppColors.primary
                  : AppColors.success,
              size: 22,
            ),
            const SizedBox(width: 10),
            Text(
              _running
                  ? (_cancelling ? '正在取消…' : '正在清理')
                  : _error != null
                  ? '清理未完成'
                  : report?.cancelled == true
                  ? '已取消清理'
                  : '清理完成',
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_running) ...[
                if (_cancelling) ...[
                  const Text(
                    '当前操作结束后停止，不再处理后续文件。',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _total == 0 || _ratio == 0 ? null : _ratio,
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 14),
                Tooltip(
                  message: _current,
                  child: Text(
                    _current,
                    style: const TextStyle(fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '$_done / $_total 项',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '已释放 ${formatBytes(_freed)}',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ] else if (_error != null) ...[
                Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ] else if (report != null) ...[
                if (journalError != null)
                  Text(
                    journalError,
                    style: const TextStyle(
                      color: AppColors.warning,
                      fontSize: 12,
                    ),
                  ),
                if (report.recycledBytes > 0) ...[
                  Text(
                    '已移到回收站 ${formatBytes(report.recycledBytes)}。可在 Windows 回收站恢复；清空回收站后才释放磁盘空间。',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                ],
                if (report.cancelled) ...[
                  const Text(
                    '已完成的清理已保留，剩余项目可稍后继续清理。',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.successSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.storage_rounded,
                        color: AppColors.success,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '已释放空间',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            formatBytes(report.freedBytes),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              color: AppColors.success,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _StatChip(
                      label: '成功',
                      value: '${report.deletedCount}',
                      color: AppColors.success,
                    ),
                    if (report.skippedCount > 0)
                      _StatChip(
                        label: '跳过',
                        value: '${report.skippedCount}',
                        color: AppColors.warning,
                      ),
                    if (report.failedCount > 0)
                      _StatChip(
                        label: '失败',
                        value: '${report.failedCount}',
                        color: AppColors.danger,
                      ),
                  ],
                ),
                if (report.failures.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.dangerSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        const Text(
                          '未能清理的项目：',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.danger,
                          ),
                        ),
                        const SizedBox(height: 4),
                        for (final f in report.failures.take(8))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              f,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
        actions: [
          if (_running)
            OutlinedButton.icon(
              onPressed: _cancelling
                  ? null
                  : () {
                      context.read<AppState>().cancelCleaning();
                      setState(() => _cancelling = true);
                    },
              icon: const Icon(Icons.stop_rounded, size: 18),
              label: Text(_cancelling ? '正在取消…' : '取消清理'),
            ),
          if (!_running)
            TextButton(
              onPressed: () => Navigator.pop(context, _report),
              child: Text(
                _error != null || report?.cancelled == true ? '关闭' : '完成',
              ),
            ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 显示清理进度弹窗
Future<CleanReport?> showCleanProgress(
  BuildContext context, {
  Set<CleanCategory>? categories,
}) async {
  return showDialog<CleanReport>(
    context: context,
    barrierDismissible: false,
    builder: (_) => CleanProgressDialog(categories: categories),
  );
}
