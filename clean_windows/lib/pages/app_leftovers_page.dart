import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/clean_models.dart';
import '../state/app_state.dart';
import '../services/path_utils.dart';
import '../widgets/page_shell.dart';
import '../widgets/file_actions_button.dart';
import '../widgets/clean_progress_dialog.dart';

/// Explicit review of empty application folders, never the application's data tree.
class AppLeftoversPage extends StatelessWidget {
  const AppLeftoversPage({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final result = state.results[CleanCategory.appLeftovers];
    final items = result?.items ?? <CleanItem>[];
    final selected = items.where((item) => item.selected).toList();
    final busy = state.scanning || state.cleaning;
    return ModulePageShell(
      title: '应用残留',
      subtitle: '仅检查安装目录中的空文件夹，需逐项确认',
      toolbar: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (state.scanning)
            TextButton.icon(
              onPressed: state.cancelScan,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('取消'),
            ),
          FilledButton.icon(
            onPressed: busy
                ? null
                : () async {
                    try {
                      await state.scan(
                        categories: {CleanCategory.appLeftovers},
                      );
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('扫描未完成，已保留结果')),
                        );
                      }
                    }
                  },
            icon: const Icon(Icons.radar_rounded),
            label: const Text('扫描残留'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.scanning) ...[
            const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                state.progress.currentPath,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          if (result?.error != null) Text(result!.error!),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(result == null ? '扫描后审查空目录' : '未发现可操作的空目录'),
                  )
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return FileActionsButton.contextMenu(
                        path: item.path,
                        allowMove: false,
                        enabled: !busy,
                        actions: [
                          FileMenuAction(
                            '加入白名单',
                            icon: Icons.shield_outlined,
                            onSelected: busy
                                ? null
                                : () => state.addToWhitelist(item),
                          ),
                        ],
                        child: CheckboxListTile(
                          value: item.selected,
                          onChanged: busy
                              ? null
                              : (_) => state.toggleItem(item),
                          secondary: const Icon(Icons.folder_off_outlined),
                          title: Text(item.name),
                          subtitle: Text(item.path),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      );
                    },
                  ),
          ),
          if (items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '已选 ${selected.length} 项 · ${formatBytes(selected.fold<int>(0, (sum, item) => sum + item.sizeBytes))}',
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: busy || selected.isEmpty
                        ? null
                        : () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (_) => CleanConfirmationDialog(
                                title: '移除空目录',
                                count: selected.length,
                                bytes: selected.fold<int>(
                                  0,
                                  (sum, item) => sum + item.sizeBytes,
                                ),
                                recycledBytes: 0,
                                description: '仅移除已勾选且仍为空的目录，无法撤销。',
                              ),
                            );
                            if (ok != true || !context.mounted) return;
                            await showDialog<CleanReport>(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => const CleanProgressDialog(
                                categories: {CleanCategory.appLeftovers},
                              ),
                            );
                          },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('移除空目录'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
