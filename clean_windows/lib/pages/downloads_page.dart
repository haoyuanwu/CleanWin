import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:provider/provider.dart';

import '../services/download_list_index.dart';

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
  final _collapsedFolders = <String>{};
  ScanCategory? _indexedCategory;
  int _indexedCount = -1;
  bool? _indexedCleaning;
  String? _indexedQuery;
  String? _indexedKind;
  FileAge? _indexedAge;
  Future<DownloadListIndex>? _indexFuture;

  Future<DownloadListIndex> _indexFor(ScanCategory? category, bool cleaning) {
    final items = category?.items ?? const <CleanItem>[];
    if (!identical(_indexedCategory, category) ||
        _indexedCount != items.length ||
        _indexedCleaning != cleaning ||
        _indexedQuery != _query ||
        _indexedKind != _kind ||
        _indexedAge != _age ||
        _indexFuture == null) {
      _indexedCategory = category;
      _indexedCount = items.length;
      _indexedCleaning = cleaning;
      _indexedQuery = _query;
      _indexedKind = _kind;
      _indexedAge = _age;
      final request = DownloadListRequest(
        [
          for (var i = 0; i < items.length; i++)
            (
              index: i,
              id: items[i].id,
              name: items[i].name,
              path: items[i].path,
              root: downloadFolder(items[i].path, items[i].id),
              bytes: items[i].sizeBytes,
              modified: items[i].reviewedModified,
            ),
        ],
        query: _query,
        kind: _kind,
        minimumDays: switch (_age) {
          FileAge.all => null,
          FileAge.recent => 0,
          FileAge.old => 30,
          FileAge.older => 180,
        },
        maximumDays: _age == FileAge.recent ? 30 : null,
      );
      _indexFuture = items.length > 400
          ? compute(buildDownloadListIndex, request)
          : SynchronousFuture(buildDownloadListIndex(request));
    }
    return _indexFuture!;
  }

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
    return FutureBuilder<DownloadListIndex>(
      future: _indexFor(category, state.cleaning),
      builder: (context, snapshot) => _buildPage(
        context,
        state,
        category,
        snapshot.connectionState == ConnectionState.done ? snapshot.data : null,
      ),
    );
  }

  Widget _buildPage(
    BuildContext context,
    AppState state,
    ScanCategory? category,
    DownloadListIndex? index,
  ) {
    final allItems = category?.items ?? const <CleanItem>[];
    final query = _query.trim().toLowerCase();
    final totalBytes = index?.totalBytes ?? 0;
    final selectedIds = state.selectedDownloadIds;
    final selectedBytes = selectedIds.fold<int>(
      0,
      (sum, id) => sum + (index?.sizeById[id] ?? 0),
    );
    return ModulePageShell(
      title: '下载管理',
      subtitle: category == null
          ? '系统下载（≥10MB）与软件管家下载包，默认不勾选'
          : '${index?.visibleCount ?? 0} / ${allItems.length} 个文件 · 已选 ${selectedIds.length} 项，${formatBytes(selectedBytes)} · 按大小排序',
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
          if (category != null && index != null) ...[
            ModuleInsights(
              label: '已扫描下载 · ${allItems.length} 项',
              value: formatBytes(totalBytes),

              icon: Icons.download_rounded,
              segments: [
                for (var i = 0; i < fileKinds.length; i++)
                  InsightSegment(
                    label: fileKinds[i],
                    amount: (index.kindBytes[fileKinds[i]] ?? 0).toDouble(),
                    value: '${index.kindCounts[fileKinds[i]] ?? 0}',
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
      child: index == null
          ? const Center(child: CircularProgressIndicator())
          : index.visibleCount == 0
          ? EmptyState(
              icon: Icons.download_rounded,
              title: query.isNotEmpty || _kind != null || _age != FileAge.all
                  ? '没有匹配的下载文件'
                  : state.scanning
                  ? '正在扫描下载目录…'
                  : category == null
                  ? '扫描下载文件夹'
                  : '没有可管理的下载文件',
              subtitle: '扫描系统下载目录和已识别的软件管家下载目录',
            )
          : Card(
              clipBehavior: Clip.antiAlias,
              child: CustomScrollView(
                slivers: [
                  for (final group in index.groups) ...[
                    SliverToBoxAdapter(
                      child: FileActionsButton.contextMenu(
                        path: group.path,
                        allowMove: false,
                        child: ListTile(
                          key: ValueKey('download-folder-${group.path}'),
                          leading: const Icon(
                            Icons.folder_rounded,
                            color: AppColors.primary,
                          ),
                          title: Text(
                            group.path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            '${group.indices.length} 项 · ${formatBytes(group.bytes)}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: AnimatedRotation(
                            turns: _collapsedFolders.contains(group.path)
                                ? -.25
                                : 0,
                            duration: const Duration(milliseconds: 180),
                            child: const Icon(Icons.expand_more_rounded),
                          ),
                          onTap: () => setState(() {
                            if (!_collapsedFolders.add(group.path)) {
                              _collapsedFolders.remove(group.path);
                            }
                          }),
                        ),
                      ),
                    ),
                    if (!_collapsedFolders.contains(group.path))
                      SliverList.builder(
                        itemCount: group.indices.length,
                        itemBuilder: (context, row) => _downloadTile(
                          context,
                          state,
                          allItems[group.indices[row]],
                          totalBytes,
                          selectedIds,
                        ),
                      ),
                    const SliverToBoxAdapter(child: Divider(height: 1)),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _downloadTile(
    BuildContext context,
    AppState state,
    CleanItem item,
    int totalBytes,
    Set<String> selectedIds,
  ) {
    final selected = selectedIds.contains(item.id);
    return FileActionsButton.contextMenu(
      path: item.path,
      enabled: !state.scanning && !state.cleaning,
      allowMove:
          !item.id.startsWith('dl_dir_') && !item.id.startsWith('dl_software_'),
      onMoved: () => state.forgetMovedDownload(item.id),
      actions: [
        FileMenuAction(
          selected ? '取消勾选' : '勾选此项',
          icon: Icons.check_box_outlined,
          onSelected: () => state.toggleDownloadSelection(item.id),
        ),
        FileMenuAction(
          '删除所选',
          icon: Icons.delete_outline_rounded,
          destructive: true,
          onSelected: selectedIds.isEmpty
              ? null
              : () => _confirmDelete(context),
        ),
      ],
      child: ListTile(
        key: ValueKey(item.id),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Checkbox(
          value: selected,
          onChanged: state.cleaning || state.scanning
              ? null
              : (_) =>
                    context.read<AppState>().toggleDownloadSelection(item.id),
        ),
        title: Text(
          item.name,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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
              fraction: totalBytes <= 0 ? 0 : item.sizeBytes / totalBytes,
              color: insightColors[fileKinds.indexOf(fileKind(item.name))],
            ),
          ],
        ),
        trailing: SizedBox(
          width: 130,
          child: Row(
            children: [
              Expanded(child: SizeText(item.sizeBytes, highlight: selected)),
              FileActionsButton(
                path: item.path,
                allowMove:
                    !item.id.startsWith('dl_dir_') &&
                    !item.id.startsWith('dl_software_'),
                onMoved: () => state.forgetMovedDownload(item.id),
              ),
            ],
          ),
        ),
        onTap: state.cleaning || state.scanning
            ? null
            : () => context.read<AppState>().toggleDownloadSelection(item.id),
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
