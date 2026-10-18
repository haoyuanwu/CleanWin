import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/installed_app.dart';
import '../services/path_utils.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/page_shell.dart';
import '../widgets/uninstall_loading_dialog.dart';
import '../widgets/module_insights.dart';

class UninstallPage extends StatefulWidget {
  const UninstallPage({super.key, this.active = true});

  final bool active;

  @override
  State<UninstallPage> createState() => _UninstallPageState();
}

class _UninstallPageState extends State<UninstallPage> {
  final _searchCtrl = TextEditingController();
  String? _loadError;
  bool _sortBySize = false;
  bool? _knownSize;

  @override
  void initState() {
    super.initState();
    if (widget.active) _loadOnEnter();
  }

  @override
  void didUpdateWidget(covariant UninstallPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _loadOnEnter();
  }

  void _loadOnEnter() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active) unawaited(_loadApps());
    });
  }

  Future<void> _loadApps({bool force = false}) async {
    final state = context.read<AppState>();
    if (state.loadingApps) return;
    setState(() => _loadError = null);
    try {
      await state.loadInstalledApps(force: force);
    } catch (_) {
      if (mounted) setState(() => _loadError = '读取失败，请点击刷新列表重试');
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final matchingApps = state.installedApps;
    final knownCount = matchingApps
        .where((app) => app.estimatedSizeBytes > 0)
        .length;
    final knownBytes = matchingApps.fold<int>(
      0,
      (sum, app) => sum + app.estimatedSizeBytes,
    );
    final apps =
        matchingApps
            .where(
              (app) =>
                  _knownSize == null ||
                  (app.estimatedSizeBytes > 0) == _knownSize,
            )
            .toList()
          ..sort(
            (a, b) => _sortBySize
                ? b.estimatedSizeBytes.compareTo(a.estimatedSizeBytes)
                : a.displayName.toLowerCase().compareTo(
                    b.displayName.toLowerCase(),
                  ),
          );

    return Padding(
      padding: kPagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ModuleHeader(
            title: '软件卸载',
            subtitle:
                '共 ${apps.length} 个匹配软件 · ${state.loadingApps && state.hasInstalledAppsSnapshot ? '正在更新，当前显示上次结果' : '使用软件自带的卸载程序'}',
            toolbar: Toolbar(
              children: [
                ModuleSearchField(
                  controller: _searchCtrl,
                  hint: '搜索软件名称或发布者…',
                  onChanged: (value) =>
                      context.read<AppState>().appFilter = value,
                ),
                IconButton.outlined(
                  tooltip: '刷新列表',
                  onPressed: state.loadingApps
                      ? null
                      : () => _loadApps(force: true),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                ),
                ModuleSelect<bool>(
                  label: '软件排序',
                  value: _sortBySize,
                  items: const [
                    ModuleSelectItem(value: false, child: Text('按名称排序')),
                    ModuleSelectItem(value: true, child: Text('按大小排序')),
                  ],
                  onChanged: (value) =>
                      setState(() => _sortBySize = value ?? false),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (state.hasInstalledAppsSnapshot) ...[
            ModuleInsights(
              label: '软件占用',
              value: formatBytes(knownBytes),
              hint: '不含未报告大小的软件 · 圆环按数量分布',
              icon: Icons.apps_rounded,
              segments: [
                InsightSegment(
                  label: '已知大小',
                  amount: knownCount.toDouble(),
                  value: '$knownCount',
                  color: AppColors.primary,
                  selected: _knownSize == true,
                  onTap: () => setState(
                    () => _knownSize = _knownSize == true ? null : true,
                  ),
                ),
                InsightSegment(
                  label: '未知大小',
                  amount: (matchingApps.length - knownCount).toDouble(),
                  value: '${matchingApps.length - knownCount}',
                  color: AppColors.textTertiary,
                  selected: _knownSize == false,
                  onTap: () => setState(
                    () => _knownSize = _knownSize == false ? null : false,
                  ),
                ),
                InsightSegment(
                  label: '按占用排列',
                  amount: 0,
                  value: '↓',
                  color: AppColors.accent,
                  selected: _sortBySize,
                  onTap: () => setState(() {
                    _sortBySize = true;
                    _knownSize = null;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (state.loadingApps && state.hasInstalledAppsSnapshot) ...[
            const LinearProgressIndicator(
              key: ValueKey('apps-refresh-progress'),
            ),
            const SizedBox(height: 12),
          ],
          if (_loadError != null && state.hasInstalledAppsSnapshot) ...[
            GlassBanner(
              icon: Icons.error_outline_rounded,
              text: '$_loadError，当前保留上次列表。',
              color: AppColors.warning,
            ),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: state.loadingApps && !state.hasInstalledAppsSnapshot
                ? const Center(child: CircularProgressIndicator())
                : apps.isEmpty
                ? EmptyState(
                    icon: Icons.apps_rounded,
                    title: _loadError != null
                        ? '加载软件列表失败'
                        : state.appFilter.trim().isNotEmpty
                        ? '没有匹配的软件'
                        : '未发现可卸载软件',
                    subtitle:
                        _loadError ??
                        (state.appFilter.trim().isNotEmpty
                            ? '试试其它关键词'
                            : '可以刷新列表重新扫描'),
                    actionLabel: '重新扫描',
                    action: _loadApps,
                  )
                : Card(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: AppColors.border),
                            ),
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) => Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    '软件',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                if (constraints.maxWidth >= 688)
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      '发布者',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                SizedBox(
                                  width: 100,
                                  child: Text(
                                    '大小',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 100,
                                  child: Text(
                                    '操作',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            key: const PageStorageKey('installed-app-list'),
                            itemCount: apps.length,
                            itemBuilder: (context, index) {
                              final app = apps[index];
                              return _AppRow(
                                app: app,
                                fraction: knownBytes <= 0
                                    ? 0
                                    : app.estimatedSizeBytes / knownBytes,
                                onUninstall:
                                    state.loadingApps || !app.canUninstall
                                    ? null
                                    : () => _confirmUninstall(app),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmUninstall(InstalledApp app) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('卸载软件'),
        content: Text(
          '确定要卸载「${app.displayName}」吗？\n\n'
          '将启动该软件的卸载程序，可能需要您在弹出的窗口中确认。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('开始卸载'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    // loading 弹窗内执行卸载
    await showUninstallLoading(context, app);
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.app,
    required this.onUninstall,
    required this.fraction,
  });

  final InstalledApp app;
  final VoidCallback? onUninstall;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    _AppIcon(app: app),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (app.displayVersion != null)
                            Text(
                              app.displayVersion!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          if (compact && app.publisher != null)
                            Text(
                              app.publisher!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (!compact)
                Expanded(
                  flex: 2,
                  child: Text(
                    app.publisher ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              SizedBox(
                width: 100,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.estimatedSizeKb != null
                          ? formatBytes(app.estimatedSizeBytes)
                          : '—',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    if (fraction > 0) ...[
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: ShareBar(fraction: fraction),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(
                width: 100,
                child: TextButton(
                  onPressed: onUninstall,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('卸载'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 软件图标：有 logo 显示 logo，否则首字母占位
class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.app});

  final InstalledApp app;

  @override
  Widget build(BuildContext context) {
    final path = app.iconPath;

    Widget fallback() {
      final letter = app.displayName.isNotEmpty
          ? app.displayName.characters.first.toUpperCase()
          : '?';
      return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          letter,
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    if (path == null || path.isEmpty || !File(path).existsSync()) {
      return fallback();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.file(
        File(path),
        width: 36,
        height: 36,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => fallback(),
      ),
    );
  }
}
