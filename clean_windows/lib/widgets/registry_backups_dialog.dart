import 'package:flutter/material.dart';

import '../services/registry_backups.dart';
import '../services/registry_scan_service.dart';

Future<void> showRegistryBackups(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const RegistryBackupsDialog(),
);

class RegistryBackupsDialog extends StatefulWidget {
  const RegistryBackupsDialog({super.key, this.backups});
  final RegistryBackups? backups;
  @override
  State<RegistryBackupsDialog> createState() => _RegistryBackupsDialogState();
}

class _RegistryBackupsDialogState extends State<RegistryBackupsDialog> {
  late final _backupStore = widget.backups ?? RegistryBackups();
  late final Future<List<RegistryBackup>> _backups = _backupStore.list();
  bool _restoring = false;
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
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('注册表备份'),
    content: SizedBox(
      width: 640,
      height: MediaQuery.sizeOf(context).height * .5,
      child: FutureBuilder<List<RegistryBackup>>(
        future: _backups,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('备份读取失败，请检查本地备份目录'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final records = snapshot.data!;
          if (records.isEmpty) return const Center(child: Text('暂无注册表备份'));
          return ListView(
            children: [
              if (_backupStore.warnings.isNotEmpty)
                Text('${_backupStore.warnings.length} 个备份格式无效，已跳过'),
              for (final record in records)
                ListTile(
                  title: Text(
                    record.issue.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${record.time.toLocal().toString().substring(0, 16)}\n${record.issue.fullKey}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: TextButton(
                    onPressed: _restoring ? null : () => _restore(record),
                    child: const Text('预览恢复'),
                  ),
                ),
            ],
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: _restoring ? null : () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );
}
