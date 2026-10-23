import 'package:flutter/material.dart';

import '../models/clean_models.dart';
import '../services/memory_boost_service.dart';
import '../services/path_utils.dart';
import '../state/app_state.dart';
import 'clean_progress_dialog.dart';

class QuickBoostDialog extends StatefulWidget {
  const QuickBoostDialog({super.key, required this.state, this.service});
  final AppState state;
  final MemoryBoostService? service;
  @override
  State<QuickBoostDialog> createState() => _QuickBoostDialogState();
}

class _QuickBoostDialogState extends State<QuickBoostDialog> {
  late final service = widget.service ?? MemoryBoostService();
  bool memory = true, temporary = true, cancelled = false;
  int stage = 0, generation = 0;
  MemoryBoostResult? preview, result;
  CleanReport? cleaned;
  String? error;
  List<CleanItem> temps = [];
  bool get busy => stage == 1 || stage == 3;
  Future<void> inspect() async {
    if (widget.state.scanning ||
        widget.state.cleaning ||
        widget.state.systemCleanup.busy) {
      setState(() => error = '当前有扫描或清理任务，请稍后重试');
      return;
    }
    setState(() {
      stage = 1;
      cancelled = false;
      error = null;
      temps = [];
      preview = null;
    });
    try {
      if (memory) preview = await service.inspect();
      if (temporary && !cancelled) {
        await widget.state.scanTemporaryFiles();
        if (widget.state.scanError != null) {
          throw StateError(widget.state.scanError!);
        }
        temps = widget.state.categories
            .where((c) => c.category == CleanCategory.systemCache)
            .expand((c) => c.items)
            .where(
              (i) =>
                  {'user_temp', 'windows_temp'}.contains(i.id) &&
                  i.hasCleanableFiles,
            )
            .toList();
        generation = widget.state.scanGeneration;
      }
      if (mounted) setState(() => stage = cancelled ? 0 : 2);
    } catch (e) {
      if (mounted) {
        setState(() {
          stage = 0;
          error = e.toString();
        });
      }
    }
  }

  Future<void> boost() async {
    if (widget.state.scanning ||
        widget.state.cleaning ||
        widget.state.systemCleanup.busy) {
      setState(() => error = '当前有其他任务，请稍后重试');
      return;
    }
    if (temporary && widget.state.scanGeneration != generation) {
      setState(() => error = '扫描结果已变化，请重新分析');
      return;
    }
    setState(() {
      stage = 3;
      cancelled = false;
      error = null;
    });
    try {
      if (memory) result = await service.optimize();
      if (temporary && !cancelled && temps.isNotEmpty) {
        for (final item in temps) {
          item.selected = true;
        }
        cleaned = await widget.state.cleanSelected(
          categories: {CleanCategory.systemCache},
          itemIds: temps.map((i) => i.id).toSet(),
        );
        if (cleaned!.failedCount > 0) error = '部分临时文件未完成，已保留供重试';
      }
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => stage = 4);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) => PopScope(
      canPop: !busy,
      child: CleanDialogSurface(
        accent: Theme.of(context).colorScheme.primary,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      stage == 4
                          ? Icons.check_circle_outline_rounded
                          : Icons.bolt_rounded,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        stage == 4
                            ? (error != null
                                  ? '加速未完整完成'
                                  : cancelled
                                  ? '已取消加速'
                                  : '加速处理完成')
                            : '立即加速',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (stage == 0) ...[
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('整理后台内存'),
                    subtitle: const Text('仅当前用户的后台进程，不关闭软件；再次使用时内存可能回升。'),
                    value: memory,
                    onChanged: (v) => setState(() => memory = v ?? false),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('清理旧临时文件'),
                    subtitle: const Text(
                      '仅用户和 Windows 临时目录中七天前的 .tmp / .temp 文件。',
                    ),
                    value: temporary,
                    onChanged: (v) => setState(() => temporary = v ?? false),
                  ),
                ],
                if (stage == 1 || stage == 3) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    stage == 1
                        ? '正在分析加速项'
                        : (widget.state.cleaning ? '正在清理临时文件' : '正在整理后台内存'),
                  ),
                  if (widget.state.scanning)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        widget.state.progress.currentPath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                if (stage == 2) ...[
                  if (memory) Text('可整理后台进程 ${preview?.candidates ?? 0} 个'),
                  if (temporary) ...[
                    const SizedBox(height: 12),
                    Text(
                      '旧临时文件 ${formatBytes(temps.fold<int>(0, (s, i) => s + i.sizeBytes))}',
                    ),
                    for (final item in temps)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '${item.name} · ${formatBytes(item.sizeBytes)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                  const SizedBox(height: 16),
                  const Text(
                    '确认后整理工作集并清理所列临时文件。不会关闭软件；内存变化以系统实测为准。',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
                if (stage == 4) ...[
                  if (result != null) ...[
                    Text(
                      '已整理 ${result!.trimmed} / ${result!.candidates} 个后台进程',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      result!.availableChange > 0
                          ? '可用内存增加 ${formatBytes(result!.availableChange)}'
                          : '本次未观察到可用内存增加',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '这是操作前后的系统内存变化，可能受其他程序影响，软件重新使用时内存可回升。',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                  if (cleaned != null) ...[
                    const SizedBox(height: 12),
                    Text('临时文件已释放 ${formatBytes(cleaned!.freedBytes)}'),
                    if (cleaned!.recycledBytes > 0)
                      Text('已移入回收站 ${formatBytes(cleaned!.recycledBytes)}'),
                    if (cleaned!.failedCount > 0)
                      Text('${cleaned!.failedCount} 项未完成，结果已保留'),
                  ] else if (temporary && !cancelled && error == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text('未发现可清理的旧临时文件'),
                    ),
                  if (cancelled) const Text('已取消后续步骤'),
                ],
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 22),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    if (busy)
                      OutlinedButton(
                        onPressed: cancelled
                            ? null
                            : () {
                                setState(() => cancelled = true);
                                widget.state.cancelScan();
                                widget.state.cancelCleaning();
                              },
                        child: Text(cancelled ? '正在取消' : '取消'),
                      )
                    else
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(stage == 4 ? '完成' : '关闭'),
                      ),
                    if (stage == 0)
                      FilledButton(
                        onPressed: memory || temporary ? inspect : null,
                        child: const Text('分析加速项'),
                      ),
                    if (stage == 2) ...[
                      TextButton(
                        onPressed: () => setState(() => stage = 0),
                        child: const Text('重新选择'),
                      ),
                      FilledButton(onPressed: boost, child: const Text('确认加速')),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
