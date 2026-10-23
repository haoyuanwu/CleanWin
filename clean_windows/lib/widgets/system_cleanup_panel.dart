import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/system_cleanup_service.dart';
import '../state/app_state.dart';
import 'cosmic_scene.dart';

/// Windows component-store maintenance shown directly in the cleanup workspace.
class SystemCleanupPanel extends StatefulWidget {
  const SystemCleanupPanel({super.key, required this.state});

  final AppState state;

  @override
  State<SystemCleanupPanel> createState() => _SystemCleanupPanelState();
}

class _SystemCleanupPanelState extends State<SystemCleanupPanel> {
  bool _confirm = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final state = widget.state;
    final task = state.systemCleanup;
    final active = task.busy;
    final ordinaryBusy =
        state.scanning || state.cleaning || state.savingOptions;
    final status = switch (task.phase) {
      SystemCleanupPhase.idle => '分析 Windows 组件存储中的可回收旧组件',
      SystemCleanupPhase.analyzing => '正在分析系统组件',
      SystemCleanupPhase.ready =>
        task.report!.recommended && task.report!.packages > 0
            ? '${task.report!.packages} 个组件包可清理'
            : '当前无需清理系统组件',
      SystemCleanupPhase.cleaning => '正在清理系统组件',
      SystemCleanupPhase.completed => '系统组件清理成功',
      SystemCleanupPhase.failed => '系统组件处理未完成',
    };

    return Material(
      key: const ValueKey('system-cleanup-panel'),
      color: CosmicColors.panel.withValues(alpha: .92),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: CosmicColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.layers_clear_outlined,
                  size: 19,
                  color: CosmicColors.cyan,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    '系统组件',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  task.phase == SystemCleanupPhase.ready ? '已分析' : 'Windows',
                  style: const TextStyle(
                    color: CosmicColors.muted,
                    fontSize: 10,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              child: Row(
                key: ValueKey(status),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    task.phase == SystemCleanupPhase.completed
                        ? Icons.check_circle_rounded
                        : Icons.storage_rounded,
                    size: 19,
                    color: CosmicColors.cyan,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      status,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (active) ...[
              const SizedBox(height: 14),
              LinearProgressIndicator(
                value: task.progress,
                color: CosmicColors.cyan,
                backgroundColor: CosmicColors.line,
              ),
              const SizedBox(height: 7),
              Text(
                task.phase == SystemCleanupPhase.cleaning
                    ? '系统维护会在后台继续，执行期间不能强行取消。'
                    : '只分析组件存储，不删除文件。',
                style: const TextStyle(color: CosmicColors.muted, fontSize: 11),
              ),
            ],
            if (task.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  task.error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            if (task.restartRequired)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'Windows 提示需要重启，请方便时手动重启；软件不会自动重启。',
                  style: TextStyle(color: CosmicColors.muted, fontSize: 12),
                ),
              ),
            if (_confirm && task.canClean) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: CosmicColors.cyan.withValues(alpha: .07),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '将移除已被替代的旧组件，可能减少部分更新的回退选项。此操作不进入回收站。',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => setState(() => _confirm = false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: ordinaryBusy || task.restartRequired
                              ? null
                              : () {
                                  setState(() => _confirm = false);
                                  task.clean();
                                },
                          child: const Text('确认清理'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (task.phase == SystemCleanupPhase.analyzing)
                    TextButton.icon(
                      onPressed: task.cancelAnalysis,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('取消分析'),
                    )
                  else
                    FilledButton.tonalIcon(
                      onPressed: active || ordinaryBusy ? null : task.analyze,
                      icon: const Icon(Icons.manage_search_rounded),
                      label: Text(
                        task.phase == SystemCleanupPhase.idle ? '分析组件' : '重新分析',
                      ),
                    ),
                  if (task.phase == SystemCleanupPhase.ready)
                    FilledButton(
                      onPressed:
                          task.canClean &&
                              !ordinaryBusy &&
                              !task.restartRequired
                          ? () => setState(() => _confirm = true)
                          : null,
                      child: const Text('清理组件'),
                    ),
                ],
              ),
            ],
            if (task.output.isNotEmpty)
              Theme(
                data: Theme.of(context).copyWith(
                  dividerColor: Colors.transparent,
                  expansionTileTheme: const ExpansionTileThemeData(
                    textColor: CosmicColors.cyan,
                    collapsedTextColor: CosmicColors.muted,
                    iconColor: CosmicColors.cyan,
                    collapsedIconColor: CosmicColors.muted,
                  ),
                ),
                child: ExpansionTile(
                  key: const PageStorageKey(
                    'system-cleanup-diagnostic-expansion',
                  ),
                  tilePadding: EdgeInsets.zero,
                  title: const Text('诊断详情', style: TextStyle(fontSize: 12)),
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        tooltip: '复制诊断',
                        onPressed: () =>
                            Clipboard.setData(ClipboardData(text: task.output)),
                        icon: const Icon(Icons.copy_all_rounded, size: 18),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          task.output,
                          key: const PageStorageKey(
                            'system-cleanup-diagnostic-text',
                          ),
                          style: const TextStyle(
                            color: CosmicColors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
