import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/clean_models.dart';
import '../services/path_utils.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/clean_progress_dialog.dart';
import '../widgets/common.dart';
import '../widgets/page_shell.dart';
import '../widgets/module_insights.dart';
import '../widgets/file_actions_button.dart';
import '../widgets/file_age_filter.dart';

/// 下载文件夹管理（安全：默认不勾选）
class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});
  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  String _query = '';
  String? _kind;
  FileAge _age = FileAge.all;

  Future<void> _scan() async {
    try {
      await context.read<AppState>().scan(
        categories: {CleanCategory.downloads},
      );
    } catch (_) {
      // AppState retains the reason and partial results for the visible banner.
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final category = state.results[CleanCategory.downloads];
    final allItems = category?.items ?? const <CleanItem>[];
    final query = _query.trim().toLowerCase();
    final items =
        allItems
            .where(
              (item) =>
                  '${item.name} ${item.path}'.toLowerCase().contains(query) &&
                  _age.includes(item.reviewedModified),
            )
            .toList()
          ..removeWhere((item) => _kind != null && fileKind(item.name) != _kind)
          ..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    final totalBytes = allItems.fold<int>(
      0,
      (sum, item) => sum + item.sizeBytes,
    );
    final selectedIds = state.selectedDownloadIds;
    final selectedBytes = allItems
        .where((i) => selectedIds.contains(i.id))
        .fold<int>(0, (s, i) => s + i.sizeBytes);

    return ModulePageShell(
      title: '下载管理',
      subtitle: category == null
          ? '扫描下载目录中的大文件（≥10MB），默认不勾选'
          : '${items.length} / ${allItems.length} 个文件 · 已选 ${selectedIds.length} 项，${formatBytes(selectedBytes)} · 按大小排序',
      toolbar: Toolbar(
        children: [
          if (selectedIds.isNotEmpty)
            StatusChip(
              label: '已选 ${selectedIds.length} 项',
              color: AppColors.primary,
              icon: Icons.check_circle_rounded,
            ),
          FileAgeFilter(
            value: _age,
            onChanged: (age) => setState(() => _age = age),
          ),
          ModuleSearchField(
            hint: '搜索下载文件名称或路径…',
            onChanged: (value) => setState(() => _query = value),
          ),
          OutlinedButton.icon(
            onPressed: state.scanning || state.cleaning ? null : _scan,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('扫描下载'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: selectedIds.isEmpty || state.cleaning || state.scanning
                ? null
                : () => _confirmDelete(context),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: Text('删除 ${formatBytes(selectedBytes)}'),
          ),
        ],
      ),
      banner: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.scanError != null) ...[
            GlassBanner(
              icon: Icons.info_outline_rounded,
              text: state.scanError!,
              color: AppColors.warning,
            ),
            const SizedBox(height: 10),
          ],
          if (category != null) ...[
            ModuleInsights(
              label: '已扫描下载 · ${allItems.length} 项',
              value: formatBytes(totalBytes),
              hint: '圆环按容量分布 · 点击类型筛选',
              icon: Icons.download_rounded,
              segments: [
                for (var i = 0; i < fileKinds.length; i++)
                  InsightSegment(
                    label: fileKinds[i],
                    amount: allItems
                        .where((item) => fileKind(item.name) == fileKinds[i])
                        .fold<double>(0, (sum, item) => sum + item.sizeBytes),
                    value:
                        '${allItems.where((item) => fileKind(item.name) == fileKinds[i]).length}',
                    color: insightColors[i],
                    selected: _kind == fileKinds[i],
                    onTap: () => setState(
                      () => _kind = _kind == fileKinds[i] ? null : fileKinds[i],
                    ),
                  ),
                if (_kind != null)
                  InsightSegment(
                    label: '显示全部',
                    amount: 0,
                    value: '重置',
                    color: AppColors.textSecondary,
                    onTap: () => setState(() => _kind = null),
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          const GlassBanner(
            icon: Icons.info_outline_rounded,
            text: '手动选择 · 移入回收站，可恢复',
            color: AppColors.warning,
          ),

          if (state.scanning) ...[
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: LinearProgressIndicator(),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                state.progress.currentPath,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
      child: items.isEmpty
          ? EmptyState(
              icon: Icons.download_rounded,
              title: query.isNotEmpty || _kind != null
                  ? '没有匹配的下载文件'
                  : state.scanning
                  ? '正在扫描下载目录…'
                  : '没有大文件',
              subtitle: '扫描后会列出下载目录中 ≥10MB 的文件与文件夹',
            )
          : Card(
              clipBehavior: Clip.antiAlias,
              child: ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: AppColors.border),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final selected = selectedIds.contains(item.id);
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: Checkbox(
                      value: selected,
                      onChanged: state.cleaning || state.scanning
                          ? null
                          : (_) => context
                                .read<AppState>()
                                .toggleDownloadSelection(item.id),
                    ),
                    title: Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    selected: selected,
                    selectedTileColor: AppColors.primary.withValues(alpha: .04),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          item.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                        const SizedBox(height: 8),
                        ShareBar(
                          fraction: totalBytes <= 0
                              ? 0
                              : item.sizeBytes / totalBytes,
                          color:
                              insightColors[fileKinds.indexOf(
                                fileKind(item.name),
                              )],
                        ),
                      ],
                    ),
                    trailing: SizedBox(
                      width: 130,
                      child: Row(
                        children: [
                          Expanded(
                            child: SizeText(
                              item.sizeBytes,
                              highlight: selected,
                            ),
                          ),
                          FileActionsButton(
                            path: item.path,
                            onMoved: () => state.forgetMovedDownload(item.id),
                          ),
                        ],
                      ),
                    ),
                    onTap: state.cleaning || state.scanning
                        ? null
                        : () => context
                              .read<AppState>()
                              .toggleDownloadSelection(item.id),
                  );
                },
              ),
            ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final state = context.read<AppState>();
    final selectedBytes =
        state.results[CleanCategory.downloads]?.items
            .where((item) => item.selected)
            .fold<int>(0, (sum, item) => sum + item.sizeBytes) ??
        0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除下载文件'),
        content: Text(
          '将移到回收站 ${state.selectedDownloadIds.length} 个项目，'
          '共 ${formatBytes(selectedBytes)}。\n\n'
          '可在 Windows 回收站恢复。清空回收站后才会释放磁盘空间。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('移到回收站'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await showCleanProgress(context, categories: {CleanCategory.downloads});
  }
}
