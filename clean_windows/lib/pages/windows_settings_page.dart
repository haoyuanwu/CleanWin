import 'package:flutter/material.dart';

import '../services/health_check_service.dart';
import '../widgets/page_shell.dart';

/// Direct useful actions, with no vendor recommendations or simulated findings.
class WindowsSettingsPage extends StatelessWidget {
  const WindowsSettingsPage({super.key});
  static const tools = [
    (HealthSettings.defaults, Icons.apps_rounded, '默认应用'),
    (HealthSettings.notifications, Icons.notifications_none_rounded, '通知'),
    (HealthSettings.taskbar, Icons.dock_rounded, '任务栏'),
    (HealthSettings.lockScreen, Icons.lock_outline_rounded, '锁屏'),
    (HealthSettings.startup, Icons.rocket_launch_outlined, '启动应用'),
    (HealthSettings.storage, Icons.storage_rounded, '存储设置'),
    (HealthSettings.updates, Icons.system_update_alt_rounded, 'Windows 更新'),
    (HealthSettings.recovery, Icons.settings_backup_restore_rounded, '恢复选项'),
  ];
  @override
  Widget build(BuildContext context) => ModulePageShell(
    title: 'Windows 设置',
    child: LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 800
            ? 4
            : constraints.maxWidth >= 420
            ? 3
            : 2;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return SingleChildScrollView(
          child: Wrap(
            key: const ValueKey('windows-top-tools'),
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final tool in tools)
                SizedBox(
                  width: width,
                  height: 112,
                  child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () async {
                        try {
                          await tool.$1.open();
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('无法打开 Windows 设置，请从开始菜单进入'),
                              ),
                            );
                          }
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  tool.$2,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 26,
                                ),
                                const Spacer(),
                                const Icon(Icons.north_east_rounded, size: 16),
                              ],
                            ),
                            const Spacer(),
                            Text(
                              tool.$3,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}
