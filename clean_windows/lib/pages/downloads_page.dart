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
  final _listController = ScrollController();
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

  @override
  void dispose() {
    _listController.dispose();
    super.dispose();
  }

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
    final showBanner =
        state.scanError != null ||
        state.scanning ||
        (category != null && index != null);
    return ModulePageShell(
      title: '下载管理',
      subtitle: category == null
          ? '系统下载（≥10MB）与软件管家下载包，默认不勾选'
          : '${index?.visibleCount ?? 0} / ${allItems.length} 个文件 · 已选 ${selectedIds.length} 项，${formatBytes(selectedBytes)} · 按大小排序',
      toolbar: Toolbar(
        children: [
          FileAgeFilter(
            value: _age,
            onChanged: (age) => setState(() => _age = age),
          ),
          ModuleSearchField(
            hint: '搜索下载文件名称或路径…',
            onChanged: (value) => setState(() => _query = value),
          ),
          ElevatedButton.icon(
            onPressed: state.scanning || state.cleaning ? null : _scan,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('扫描下载'),
          ),
        ],
      ),
      banner: !showBanner
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (state.scanError != null) ...[
                  GlassBanner(
                    icon: Icons.info_outline_rounded,
                    text: state.scanError!,
                    color: AppColors.warning,
                  ),
                  if (category != null || state.scanning)
                    const SizedBox(height: 8),
                ],
                if (category != null && index != null)
                  _DownloadSummaryBar(
                    fileCount: allItems.length,
                    totalBytes: totalBytes,
                    index: index,
                    selectedKind: _kind,
                    onKindChanged: (kind) => setState(() => _kind = kind),
                  ),
                if (state.scanning) ...[
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: index == null
                ? const Center(child: CircularProgressIndicator())
                : index.visibleCount == 0
                ? EmptyState(
                    icon: Icons.download_rounded,
                    title:
                        query.isNotEmpty || _kind != null || _age != FileAge.all
                        ? '没有匹配的下载文件'
                        : state.scanning
                        ? '正在扫描下载目录…'
                        : category == null
                        ? '扫描下载文件夹'
                        : '没有可管理的下载文件',
                    subtitle: '扫描系统下载目录和已识别的软件管家下载目录',
                  )
                : Card(
                    key: const ValueKey('download-list-panel'),
                    clipBehavior: Clip.antiAlias,
                    child: Scrollbar(
                      controller: _listController,
                      thumbVisibility: true,
                      interactive: true,
                      child: CustomScrollView(
                        controller: _listController,
                        slivers: [
                          for (final group in index.groups) ...[
                            SliverToBoxAdapter(
                              child: FileActionsButton.contextMenu(
                                path: group.path,
                                allowMove: false,
                                child: InteractiveSurface(
                                  baseColor: AppColors.surface,
                                  child: ListTile(
                                    key: ValueKey(
                                      'download-folder-${group.path}',
                                    ),
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
                                      turns:
                                          _collapsedFolders.contains(group.path)
                                          ? -.25
                                          : 0,
                                      duration:
                                          MediaQuery.disableAnimationsOf(
                                            context,
                                          )
                                          ? Duration.zero
                                          : const Duration(milliseconds: 180),
                                      child: const Icon(
                                        Icons.expand_more_rounded,
                                      ),
                                    ),
                                    onTap: () => setState(() {
                                      if (!_collapsedFolders.add(group.path)) {
                                        _collapsedFolders.remove(group.path);
                                      }
                                    }),
                                  ),
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
                  ),
          ),
          AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.bottomCenter,
            child: selectedIds.isEmpty
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Material(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle_rounded,
                              size: 20,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '已选 ${selectedIds.length} 项',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed:
                                  state.cleaning ||
                                      state.scanning ||
                                      category == null
                                  ? null
                                  : () => state.toggleCategory(category, false),
                              child: const Text('取消选择'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.danger,
                              ),
                              onPressed: state.cleaning || state.scanning
                                  ? null
                                  : () => _confirmDelete(context),
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                              ),
                              label: Text('删除 ${formatBytes(selectedBytes)}'),
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
      child: InteractiveSurface(
        selected: selected,
        enabled: !state.scanning && !state.cleaning,
        child: ListTile(
          key: ValueKey(item.id),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: selected,
                onChanged: state.cleaning || state.scanning
                    ? null
                    : (_) => context.read<AppState>().toggleDownloadSelection(
                        item.id,
                      ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 34,
                height: 38,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  switch (fileKind(item.name)) {
                    '压缩 / 镜像' => Icons.folder_zip_outlined,
                    '影音' => Icons.movie_outlined,
                    '安装包' => Icons.install_desktop_outlined,
                    _ => Icons.insert_drive_file_outlined,
                  },
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          title: Tooltip(
            message: item.path,
            child: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          selected: selected,
          selectedTileColor: Colors.transparent,
          subtitle: Text(
            item.reviewedModified == null
                ? fileKind(item.name)
                : '${fileKind(item.name)}  ·  ${item.reviewedModified!.toIso8601String().split('T').first.replaceAll('-', '/')}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          trailing: SizedBox(
            width: 144,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SizeText(item.sizeBytes, highlight: selected),
                      const SizedBox(height: 6),
                      ShareBar(
                        fraction: totalBytes <= 0
                            ? 0
                            : item.sizeBytes / totalBytes,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
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

class _DownloadSummaryBar extends StatelessWidget {
  const _DownloadSummaryBar({
    required this.fileCount,
    required this.totalBytes,
    required this.index,
    required this.selectedKind,
    required this.onKindChanged,
  });

  final int fileCount;
  final int totalBytes;
  final DownloadListIndex index;
  final String? selectedKind;
  final ValueChanged<String?> onKindChanged;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('download-summary-bar'),
    height: 58,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: Theme.of(context).colorScheme.outlineVariant,
        width: 1.2,
      ),
    ),
    child: Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.download_rounded,
            size: 19,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 145,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$fileCount 个下载文件 · ${formatBytes(totalBytes)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                '手动选择 · 移入回收站可恢复',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 1,
          height: 30,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < fileKinds.length; i++) ...[
                  _DownloadKindChip(
                    label: fileKinds[i],
                    count: index.kindCounts[fileKinds[i]] ?? 0,
                    color: insightColors[i],
                    selected: selectedKind == fileKinds[i],
                    onTap: () => onKindChanged(
                      selectedKind == fileKinds[i] ? null : fileKinds[i],
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (selectedKind != null)
                  _DownloadKindChip(
                    label: '显示全部',
                    count: 0,
                    showCount: false,
                    color: AppColors.textSecondary,
                    selected: false,
                    onTap: () => onKindChanged(null),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _DownloadKindChip extends StatelessWidget {
  const _DownloadKindChip({
    required this.label,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
    this.showCount = true,
  });

  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final bool showCount;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? color.withValues(alpha: .14) : AppColors.surface,
    borderRadius: BorderRadius.circular(9),
    child: InkWell(
      key: ValueKey('insight-$label'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? color.withValues(alpha: .45) : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              showCount ? '$label  $count' : label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? color : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
