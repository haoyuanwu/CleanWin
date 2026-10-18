import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/activity_service.dart';
import '../services/file_actions.dart';
import '../services/path_utils.dart';
import '../services/registry_backups.dart';
import '../services/registry_scan_service.dart';
import '../state/app_state.dart';
import 'common.dart';

Future<void> showActivityCenter(BuildContext context, {int tab = 0}) =>
    showDialog<void>(
      context: context,
      builder: (_) =>
          ActivityCenter(journal: context.read<AppState>().journal, tab: tab),
    );

class ActivityCenter extends StatefulWidget {
  const ActivityCenter({
    super.key,
    required this.journal,
    this.tab = 0,
    this.backups,
  });
  final RegistryBackups? backups;
  final ActivityJournal journal;
  final int tab;
  @override
  State<ActivityCenter> createState() => _ActivityCenterState();
}

class _ActivityCenterState extends State<ActivityCenter> {
  late final _backupStore = widget.backups ?? RegistryBackups();
  late Future<List<RegistryBackup>> _backups = _backupStore.list();
  bool _restoring = false;
  String _time(Object? raw) =>
      DateTime.tryParse('$raw')?.toLocal().toString().substring(0, 16) ??
      '时间未知';
  Future<void> _restore(RegistryBackup backup) async {
    final issue = backup.issue;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复注册表值'),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: SelectableText(
              '${issue.fullKey}\n${issue.view}\n值：${issue.valueName}\n内容：${issue.data}\n\n仅恢复此备份值，已有值不会被覆盖。',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _restoring = true);
    bool success;
    try {
      success = await RegistryScanService().restoreValue(issue);
    } catch (_) {
      success = false;
    }
    if (!mounted) return;
    setState(() => _restoring = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(success ? '已恢复备份值' : '未能恢复：可能权限不足或值已存在，未覆盖已有内容')),
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    initialIndex: widget.tab,
    child: AlertDialog(
      title: const Text('任务与记录'),
      content: SizedBox(
        width: 720,
        height: math.min(520, MediaQuery.sizeOf(context).height * .65),
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: '进行中'),
                Tab(text: '清理记录'),
                Tab(text: '注册表备份'),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(
                children: [
                  ListenableBuilder(
                    listenable: TaskBoard.instance,
                    builder: (context, _) {
                      final tasks = TaskBoard.instance.tasks.entries.toList();
                      if (tasks.isEmpty) {
                        return const EmptyState(
                          icon: Icons.task_alt_rounded,
                          title: '当前没有运行中的任务',
                        );
                      }
                      return ListView(
                        children: [
                          for (final entry in tasks)
                            ListTile(
                              leading: const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              title: Text(entry.value.title),
                              subtitle: Text(
                                entry.value.detail,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: TextButton(
                                onPressed: entry.value.cancel == null
                                    ? null
                                    : () =>
                                          TaskBoard.instance.cancel(entry.key),
                                child: const Text('取消'),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  Builder(
                    builder: (context) {
                      final records = widget.journal.records;
                      if (records.isEmpty) {
                        return EmptyState(
                          icon: Icons.history_rounded,
                          title: widget.journal.error ?? '清理后将在这里保留记录',
                        );
                      }
                      return ListView(
                        children: [
                          if (widget.journal.error != null)
                            Text(widget.journal.error!),
                          for (final record in records)
                            ListTile(
                              leading: Icon(
                                record['cancelled'] == true
                                    ? Icons.stop_circle_outlined
                                    : Icons.history_rounded,
                              ),
                              title: Text(
                                '${record['title']} · ${record['cancelled'] == true ? '已取消' : '已结束'}',
                              ),
                              subtitle: Text(
                                '${_time(record['time'])}\n释放 ${formatBytes((record['freed'] as num?)?.toInt() ?? 0)} · 回收站 ${formatBytes((record['recycled'] as num?)?.toInt() ?? 0)}',
                              ),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () => showDialog<void>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text('${record['title']}'),
                                  content: SizedBox(
                                    width: 500,
                                    child: SingleChildScrollView(
                                      child: SelectableText(
                                        '完成 ${record['completed']} · 跳过 ${record['skipped']} · 失败 ${record['failed']}\n\n${(record['names'] as List? ?? []).join('\n')}\n\n${(record['failures'] as List? ?? []).join('\n')}',
                                      ),
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('关闭'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  FutureBuilder<List<RegistryBackup>>(
                    future: _backups,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return EmptyState(
                          icon: Icons.error_outline,
                          title: '备份未能完整读取',
                          subtitle: '${snapshot.error}',
                          actionLabel: '重试',
                          action: () =>
                              setState(() => _backups = _backupStore.list()),
                        );
                      }
                      final records = snapshot.data ?? [];
                      if (records.isEmpty) {
                        return EmptyState(
                          icon: Icons.restore_rounded,
                          title: _backupStore.warnings.isEmpty
                              ? '清理注册表后生成备份'
                              : '没有可读取的备份',
                          subtitle: _backupStore.warnings.isEmpty
                              ? null
                              : '${_backupStore.warnings.length} 个备份损坏或格式不支持，已跳过',
                        );
                      }
                      return ListView(
                        children: [
                          if (_backupStore.warnings.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                '${_backupStore.warnings.length} 个备份损坏或格式不支持，已跳过',
                              ),
                            ),
                          for (final record in records)
                            ListTile(
                              title: Text(
                                record.issue.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${_time(record.time.toIso8601String())}\n${record.issue.fullKey}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: TextButton(
                                onPressed: _restoring
                                    ? null
                                    : () => _restore(record),
                                child: const Text('预览恢复'),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: FileActions.recycleBin,
          icon: const Icon(Icons.restore_from_trash_rounded),
          label: const Text('打开回收站'),
        ),
        TextButton(
          onPressed: _restoring ? null : () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}
