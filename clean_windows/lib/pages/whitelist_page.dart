import 'package:flutter/material.dart';

import '../widgets/file_actions_button.dart';

import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/page_shell.dart';
import '../widgets/module_insights.dart';

/// 白名单管理页
class WhitelistPage extends StatefulWidget {
  const WhitelistPage({super.key});
  @override
  State<WhitelistPage> createState() => _WhitelistPageState();
}

class _WhitelistPageState extends State<WhitelistPage> {
  String _query = '';
  String? _drive;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final allEntries = state.whitelist.entries;
    final query = _query.trim().toLowerCase();
    String driveOf(String path) =>
        RegExp(r'^[a-zA-Z]:').stringMatch(path)?.toUpperCase() ?? '其他路径';
    final drives = <String, int>{};
    for (final entry in allEntries) {
      drives.update(
        driveOf(entry.path),
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final entries = allEntries
        .where(
          (entry) =>
              ('${entry.name} ${entry.path}').toLowerCase().contains(query),
        )
        .where((entry) => _drive == null || driveOf(entry.path) == _drive)
        .toList();
    return ModulePageShell(
      title: '白名单',
      subtitle: '已保护 ${allEntries.length} 个路径 · 当前显示 ${entries.length} 项',
      toolbar: Toolbar(
        children: [
          ModuleSearchField(
            hint: '搜索受保护的名称或路径…',
            onChanged: (value) => setState(() => _query = value),
          ),
          ElevatedButton.icon(
            onPressed: state.scanning || state.cleaning
                ? null
                : () => _showAddDialog(context),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('手动添加'),
          ),
          OutlinedButton.icon(
            onPressed: allEntries.isEmpty || state.scanning || state.cleaning
                ? null
                : () => _confirmClear(context),
            icon: const Icon(Icons.delete_sweep_rounded, size: 18),
            label: const Text('清空白名单'),
          ),
        ],
      ),
      banner: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.whitelistError != null) ...[
            GlassBanner(
              icon: Icons.error_outline_rounded,
              text: state.whitelistError!,
              color: AppColors.danger,
            ),
            const SizedBox(height: 10),
          ],
          ModuleInsights(
            label: '受保护路径',
            value: '${allEntries.length} 项',
            hint: '扫描与清理时跳过',
            icon: Icons.shield_outlined,
            segments: [
              for (var i = 0; i < drives.length; i++)
                InsightSegment(
                  label: drives.keys.elementAt(i),
                  amount: drives.values.elementAt(i).toDouble(),
                  value: '${drives.values.elementAt(i)}',
                  color: insightColors[i % insightColors.length],
                  selected: _drive == drives.keys.elementAt(i),
                  onTap: () => setState(() {
                    final drive = drives.keys.elementAt(i);
                    _drive = _drive == drive ? null : drive;
                  }),
                ),
              if (_drive != null)
                InsightSegment(
                  label: '全部路径',
                  amount: 0,
                  value: '重置',
                  color: AppColors.textSecondary,
                  onTap: () => setState(() => _drive = null),
                ),
            ],
          ),
          const SizedBox(height: 10),
          const GlassBanner(
            icon: Icons.verified_user_outlined,
            text: '受保护的路径将在扫描和清理时跳过，也可在一键清理结果中右键添加。',
            color: AppColors.success,
          ),
        ],
      ),
      child: entries.isEmpty
          ? EmptyState(
              icon: Icons.verified_user_outlined,
              title: allEntries.isEmpty ? '白名单是空的' : '没有匹配的保护路径',
              subtitle: '手动添加需要保留的文件或文件夹路径',
            )
          : Card(
              clipBehavior: Clip.antiAlias,
              child: ListView.separated(
                itemCount: entries.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return FileActionsButton.contextMenu(
                    path: entry.path,
                    allowMove: false,
                    actions: [
                      FileMenuAction(
                        '移除保护',
                        icon: Icons.remove_moderator_outlined,
                        destructive: true,
                        onSelected: state.scanning || state.cleaning
                            ? null
                            : () => _confirmRemove(context, entry.path),
                      ),
                    ],
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      leading: const Icon(
                        Icons.folder_special_outlined,
                        color: AppColors.success,
                      ),
                      title: Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Tooltip(
                        message: entry.path,
                        child: Text(
                          '${entry.path}\n添加于 ${_formatDate(entry.addedAt)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '复制路径',
                            icon: const Icon(Icons.copy_rounded, size: 17),
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: entry.path),
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('路径已复制')),
                              );
                            },
                          ),
                          TextButton(
                            onPressed: state.scanning || state.cleaning
                                ? null
                                : () => _confirmRemove(context, entry.path),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.danger,
                            ),
                            child: const Text('移除'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  Future<void> _confirmRemove(BuildContext context, String path) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('移除保护路径'),
        content: Text('移除后，下次扫描将重新包含此路径：\n\n$path'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<AppState>().removeFromWhitelist(path);
    }
  }

  String _formatDate(DateTime t) {
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  Future<void> _showAddDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('手动添加白名单'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '输入要排除的完整路径（文件或文件夹）',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: r'例如 C:\Users\Name\AppData\Local\Temp',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty && context.mounted) {
      await context.read<AppState>().addManualWhitelist(ctrl.text.trim());
    }
    ctrl.dispose();
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('清空白名单'),
        content: const Text('确定要移除全部白名单条目吗？下次扫描将重新包含这些路径。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<AppState>().clearWhitelist();
    }
  }
}
