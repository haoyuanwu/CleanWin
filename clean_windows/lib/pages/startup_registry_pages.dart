import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/startup_service.dart';
import '../services/registry_scan_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/page_shell.dart';
import '../widgets/module_insights.dart';
import '../services/activity_service.dart';
import '../models/clean_models.dart';
import '../widgets/activity_center.dart';

/// 开机启动项管理
class StartupPage extends StatefulWidget {
  const StartupPage({super.key, this.service, this.active = true});
  final StartupService? service;
  final bool active;

  @override
  State<StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends State<StartupPage> {
  late final StartupService _service;
  List<StartupItem> _items = [];
  bool _loading = true;
  bool _busy = false;
  String? _loadError;
  String _query = '';
  bool? _enabledFilter;
  bool _unknownOnly = false;
  String _sourceFilter = 'all';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? StartupService();
    if (widget.active) {
      _load();
    } else {
      _loading = false;
    }
  }

  @override
  void didUpdateWidget(covariant StartupPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && !_loaded) _load();
  }

  Future<void> _load() async {
    final taskId = 'startup-${identityHashCode(this)}';
    TaskBoard.instance.update(taskId, '启动项扫描', '正在读取启动位置');
    setState(() => _loading = true);
    try {
      final items = await _service.list(force: true);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loadError = null;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loadError = '无法读取启动项，请刷新重试');
    } finally {
      TaskBoard.instance.finish(taskId);
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final items = _items
        .where(
          (item) =>
              ('${item.name} ${item.command} ${item.locationLabel} ${item.publisher ?? ''}')
                  .toLowerCase()
                  .contains(query) &&
              (_sourceFilter == 'all' || item.group == _sourceFilter) &&
              (!_unknownOnly || !item.stateKnown) &&
              (_enabledFilter == null ||
                  (item.stateKnown && item.enabled == _enabledFilter)),
        )
        .toList();
    return Padding(
      padding: kPagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Toolbar(
                  children: [
                    ModuleSelect<String>(
                      label: '启动项来源',
                      value: _sourceFilter,
                      items: [
                        ModuleSelectItem(
                          value: 'all',
                          child: Text('全部来源（${_items.length}）'),
                        ),
                        for (final source in const [
                          (id: 'registry', label: '注册表'),
                          (id: 'folder', label: '启动文件夹'),
                          (id: 'task', label: '计划任务'),
                          (id: 'service', label: '自动服务'),
                          (id: 'package', label: '商店应用'),
                          (id: 'system', label: '系统登录'),
                        ])
                          ModuleSelectItem(
                            value: source.id,
                            child: Text(
                              '${source.label}（${_items.where((item) => item.group == source.id).length}）',
                            ),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _sourceFilter = value ?? 'all'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ModuleSearchField(
                hint: '搜索启动项名称或命令…',
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: '刷新',
                onPressed: _loading || _busy ? null : _load,
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ModuleInsights(
            label: '启动状态 · ${_items.length} 项',
            value:
                '${_items.where((item) => item.enabled && item.stateKnown).length} 已启用',
            hint: '点击状态筛选 · 修改下次登录生效',
            busy: _loading,
            icon: Icons.rocket_launch_rounded,
            segments: [
              for (final (label, value, color) in const [
                ('已启用', true, AppColors.primary),
                ('已禁用', false, AppColors.success),
              ])
                InsightSegment(
                  label: label,
                  amount: _items
                      .where((item) => item.stateKnown && item.enabled == value)
                      .length
                      .toDouble(),
                  value:
                      '${_items.where((item) => item.stateKnown && item.enabled == value).length}',
                  color: color,
                  selected: _enabledFilter == value,
                  onTap: () => setState(() {
                    _enabledFilter = _enabledFilter == value ? null : value;
                    _unknownOnly = false;
                  }),
                ),
              InsightSegment(
                label: '状态未知',
                amount: _items
                    .where((item) => !item.stateKnown)
                    .length
                    .toDouble(),
                value: '${_items.where((item) => !item.stateKnown).length}',
                color: AppColors.textTertiary,
                selected: _unknownOnly,
                onTap: () => setState(() {
                  _unknownOnly = !_unknownOnly;
                  _enabledFilter = null;
                }),
              ),
              if (_enabledFilter != null || _unknownOnly)
                InsightSegment(
                  label: '全部状态',
                  amount: 0,
                  value: '重置',
                  color: AppColors.textSecondary,
                  onTap: () => setState(() {
                    _enabledFilter = null;
                    _unknownOnly = false;
                  }),
                ),
            ],
          ),
          if (_loadError != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: GlassBanner(
                icon: Icons.error_outline_rounded,
                text: _loadError!,
                color: AppColors.warning,
              ),
            ),
          if (_service.warnings.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _showDetails(
                  '未完整读取的位置',
                  '部分位置可能需要管理员权限。\n\n${_service.warnings.join('\n')}',
                ),
                icon: const Icon(Icons.info_outline_rounded, size: 16),
                label: Text('${_service.warnings.length} 个位置未能完整读取'),
                style: TextButton.styleFrom(foregroundColor: AppColors.warning),
              ),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading && !_loaded
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                ? const EmptyState(
                    icon: Icons.rocket_launch_rounded,
                    title: '没有匹配的启动项',
                  )
                : Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListView.separated(
                      key: const PageStorageKey('startup-list'),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return ListTile(
                          key: ValueKey(item.id),
                          onTap: () => _showDetails(
                            item.name,
                            '来源：${item.groupLabel}\n${item.locationLabel}\n\n命令：${item.command}\n\n${item.publisher ?? ''}\n${item.canToggle ? '修改将在下次启动或登录时生效。' : '只读项目，请在 Windows 设置、任务计划程序或服务管理中调整。'}',
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          leading: Icon(
                            switch (item.group) {
                              'task' => Icons.task_outlined,
                              'service' => Icons.settings_suggest_outlined,
                              'folder' => Icons.folder_outlined,
                              'package' => Icons.apps_rounded,
                              'system' => Icons.shield_outlined,
                              _ => Icons.rocket_launch_outlined,
                            },
                            color: item.enabled
                                ? AppColors.primary
                                : AppColors.textTertiary,
                          ),
                          title: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Tooltip(
                            message: item.command,
                            child: Text(
                              '${item.groupLabel} · ${item.shortCommand}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!item.canToggle)
                                StatusChip(
                                  label: !item.stateKnown
                                      ? '状态由 Windows 管理'
                                      : '${item.enabled ? '已启用' : '已禁用'} · 只读',
                                  color: item.enabled && item.stateKnown
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                )
                              else
                                Tooltip(
                                  message: item.enabled ? '禁用启动项' : '启用启动项',
                                  child: Switch(
                                    value: item.enabled,
                                    onChanged: _busy || _loading
                                        ? null
                                        : (value) => _toggle(item, value),
                                  ),
                                ),
                              if (item.location.startsWith('StartupFolder'))
                                IconButton(
                                  tooltip: '删除启动项',
                                  onPressed: _busy || _loading
                                      ? null
                                      : () => _remove(item),
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: AppColors.danger,
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDetails(String title, String text) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(child: SelectableText(text)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('关闭'),
        ),
      ],
    ),
  );

  Future<void> _toggle(StartupItem item, bool enabled) async {
    if (_busy) return;
    setState(() => _busy = true);
    var ok = false;
    try {
      ok = await _service.setEnabled(item, enabled);
      if (ok && mounted) await _load();
    } on Exception {
      ok = false;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled ? '已启用「${item.name}」' : '已禁用「${item.name}」，下次开机不再自动运行',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('操作失败，可能需要管理员权限：${item.name}')));
    }
  }

  Future<void> _remove(StartupItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('删除启动项'),
        content: Text('从启动文件夹删除「${item.name}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (_busy) return;
    setState(() => _busy = true);
    var done = false;
    try {
      done = await _service.removeFile(item);
      if (done && mounted) await _load();
    } on Exception {
      done = false;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(done ? '已删除' : '删除失败')));
  }
}

/// 注册表瘦身（预览为主）
class RegistryCleanPage extends StatefulWidget {
  const RegistryCleanPage({super.key});

  @override
  State<RegistryCleanPage> createState() => _RegistryCleanPageState();
}

class _RegistryCleanPageState extends State<RegistryCleanPage> {
  final Set<String> _selected = {};
  String _query = '';
  String? _categoryFilter;
  bool _cleaning = false;
  bool _cancelRequested = false;
  String? _operationError;
  int _scanGeneration = 0;

  Future<void> _showCoverage() async {
    final state = context.read<AppState>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('注册表扫描范围'),
        content: SizedBox(
          width: 720,
          height: 420,
          child: ListView(
            children: [
              const Text(
                '按当前用户/全机、32/64 位视图逐项检查。位置不存在、无法读取和目标未验证会分别记录。',
                style: TextStyle(fontSize: 12),
              ),
              if (state.registryWarnings.isNotEmpty) ...[
                const SizedBox(height: 12),
                SelectableText(
                  '未完整读取：\n${state.registryWarnings.join('\n')}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.warning,
                  ),
                ),
              ],
              for (final source in state.registryCoverage)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        '${source.hive}\\${source.path}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${source.view == 'Registry32' ? '32 位' : '64 位'} · ${source.statusLabel} · ${source.keys} 个键 · ${source.checked} 次值检查 · ${source.unverified} 个目标未验证',
                        style: TextStyle(
                          fontSize: 11,
                          color: source.status == 'partial'
                              ? AppColors.warning
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _scan() async {
    setState(() {
      _selected.clear();
      _scanGeneration++;
      _operationError = null;
    });
    try {
      await context.read<AppState>().scanRegistry(force: true);
    } catch (_) {
      if (mounted) setState(() => _operationError = '注册表扫描失败，请重试；当前保留已读取的结果');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scanning = state.registryScanning;
    final enabled = !scanning && !_cleaning;
    final query = _query.trim().toLowerCase();
    final cleanable = state.registryIssues
        .where((issue) => issue.canDelete)
        .toList();
    final validIds = cleanable.map((issue) => issue.id).toSet();
    _selected.removeWhere((id) => !validIds.contains(id));
    final groups = <String, List<RegistryIssue>>{};
    for (final category in registryCategoryLabels.keys) {
      final matches = cleanable
          .where(
            (issue) =>
                issue.category == category &&
                (_categoryFilter == null ||
                    issue.category == _categoryFilter) &&
                ('${issue.title} ${issue.detail} ${issue.fullKey} ${issue.valueName ?? ''}')
                    .toLowerCase()
                    .contains(query),
          )
          .toList();
      if (matches.isNotEmpty) groups[category] = matches;
    }
    final entries = groups.entries.toList();
    return ModulePageShell(
      title: '注册表',
      subtitle: '${cleanable.length} 项可清理 · 已选 ${_selected.length} 项',
      toolbar: Toolbar(
        children: [
          ModuleSearchField(
            hint: '搜索名称或注册表路径…',
            onChanged: (value) => setState(() => _query = value),
          ),
          ElevatedButton.icon(
            onPressed: enabled ? _scan : null,
            icon: const Icon(Icons.radar_rounded, size: 18),
            label: Text(scanning ? '扫描中…' : '开始扫描'),
          ),
          OutlinedButton.icon(
            onPressed: enabled && _selected.isNotEmpty
                ? () => _confirmClean(context)
                : null,
            icon: const Icon(Icons.cleaning_services_rounded, size: 18),
            label: Text(_cleaning ? '清理中…' : '清理所选（${_selected.length}）'),
          ),
          if (_cleaning)
            TextButton(
              onPressed: _cancelRequested
                  ? null
                  : () => setState(() => _cancelRequested = true),
              child: const Text('取消清理'),
            ),
          IconButton(
            tooltip: '备份恢复',
            onPressed: _cleaning
                ? null
                : () => showActivityCenter(context, tab: 2),
            icon: const Icon(Icons.restore_rounded, size: 19),
          ),
          if (_selected.isNotEmpty)
            IconButton(
              tooltip: '取消选择',
              onPressed: enabled
                  ? () => setState(() => _selected.clear())
                  : null,
              icon: const Icon(Icons.deselect_rounded, size: 19),
            ),
          IconButton(
            tooltip: '查看扫描范围',
            onPressed: state.registryCoverage.isEmpty ? null : _showCoverage,
            icon: const Icon(Icons.info_outline_rounded, size: 19),
          ),
        ],
      ),
      banner: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ModuleInsights(
            label: '可清理记录',
            value: '${cleanable.length} 项',
            hint: '按类别查看 · 列表默认折叠 · 清理前备份',
            busy: scanning,
            icon: Icons.account_tree_outlined,
            segments: [
              for (var i = 0; i < registryCategoryLabels.length; i++)
                if (cleanable.any(
                  (issue) =>
                      issue.category ==
                      registryCategoryLabels.keys.elementAt(i),
                ))
                  InsightSegment(
                    label: registryCategoryLabels.values.elementAt(i),
                    amount: cleanable
                        .where(
                          (issue) =>
                              issue.category ==
                              registryCategoryLabels.keys.elementAt(i),
                        )
                        .length
                        .toDouble(),
                    value:
                        '${cleanable.where((issue) => issue.category == registryCategoryLabels.keys.elementAt(i)).length}',
                    color: insightColors[i % insightColors.length],
                    selected:
                        _categoryFilter ==
                        registryCategoryLabels.keys.elementAt(i),
                    onTap: () => setState(() {
                      final category = registryCategoryLabels.keys.elementAt(i);
                      _categoryFilter = _categoryFilter == category
                          ? null
                          : category;
                    }),
                  ),
              if (_categoryFilter != null)
                InsightSegment(
                  label: '全部类别',
                  amount: 0,
                  value: '重置',
                  color: AppColors.textSecondary,
                  onTap: () => setState(() => _categoryFilter = null),
                ),
            ],
          ),
          if (_operationError != null)
            GlassBanner(
              icon: Icons.error_outline_rounded,
              text: _operationError!,
              color: AppColors.danger,
            ),
          if (state.registryWarnings.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _showCoverage,
                icon: const Icon(Icons.info_outline_rounded, size: 16),
                label: Text('${state.registryWarnings.length} 个位置未完整读取'),
                style: TextButton.styleFrom(foregroundColor: AppColors.warning),
              ),
            ),
        ],
      ),
      child: scanning && cleanable.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : entries.isEmpty
          ? EmptyState(
              icon: Icons.health_and_safety_rounded,
              title: query.isEmpty ? '暂无可清理的注册表记录' : '没有匹配的记录',
            )
          : ListView.builder(
              key: const PageStorageKey('registry-groups'),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final ids = entry.value.map((issue) => issue.id).toSet();
                final selected = ids.where(_selected.contains).length;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    key: PageStorageKey(
                      'registry-group-$_scanGeneration-${entry.key}',
                    ),
                    initiallyExpanded: false,
                    shape: const Border(),
                    collapsedShape: const Border(),
                    leading: Checkbox(
                      tristate: true,
                      value: selected == 0
                          ? false
                          : selected == ids.length
                          ? true
                          : null,
                      onChanged: !enabled
                          ? null
                          : (_) => setState(() {
                              if (selected == ids.length) {
                                _selected.removeAll(ids);
                              } else {
                                _selected.addAll(ids);
                              }
                            }),
                    ),
                    title: Text(
                      registryCategoryLabels[entry.key]!,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      selected == 0
                          ? '${entry.value.length} 项'
                          : '${entry.value.length} 项 · 已选 $selected 项',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    children: [
                      for (final issue in entry.value)
                        _buildIssue(issue, enabled),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildIssue(RegistryIssue issue, bool enabled) => CheckboxListTile(
    key: ValueKey(issue.id),
    dense: true,
    value: _selected.contains(issue.id),
    onChanged: !enabled
        ? null
        : (value) => setState(() {
            if (value == true) {
              _selected.add(issue.id);
            } else {
              _selected.remove(issue.id);
            }
          }),
    title: Text(issue.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Tooltip(
      message:
          '${issue.detail}\n${issue.fullKey}\n值：${issue.valueName == '' ? '(默认)' : issue.valueName}',
      child: Text(
        '${issue.view == 'Registry32' ? '32 位' : '64 位'} · ${issue.fullKey}\n值：${issue.valueName == '' ? '(默认)' : issue.valueName}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11),
      ),
    ),
  );

  Future<void> _confirmClean(BuildContext context) async {
    final state = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理注册表'),
        content: const Text(
          '将重新核对所选值及其目标路径，保存备份后删除仍然失效的值。\n\n不会删除整键。备份保存在本地 CleanWin\\registry_backups 文件夹。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    setState(() {
      _cleaning = true;
      _cancelRequested = false;
    });
    final targets = List.of(state.registryIssues)
        .where((issue) => issue.canDelete && _selected.contains(issue.id))
        .toList();
    var done = 0;
    var handled = 0;
    final completed = <String>{};
    for (final e in targets) {
      if (_cancelRequested) break;
      TaskBoard.instance.update(
        'registry-cleanup',
        '注册表清理',
        '$handled / ${targets.length} · ${e.title}',
        cancel: () {
          if (mounted) setState(() => _cancelRequested = true);
        },
      );
      try {
        final okDel = await state.deleteRegistryIssue(e);
        if (okDel) {
          done++;
          completed.add(e.id);
        }
      } catch (_) {
        // Retain failed selections for review or retry.
      }
      handled++;
    }
    TaskBoard.instance.finish('registry-cleanup');
    state.journal.record(
      '注册表清理',
      CleanReport(
        freedBytes: 0,
        deletedCount: done,
        skippedCount: 0,
        failedCount: handled - done,
        cancelled: _cancelRequested && handled < targets.length,
      ),
      names: targets.map((issue) => issue.title).toList(),
    );
    if (!context.mounted) return;
    setState(() {
      _selected.removeWhere(completed.contains);
      _cleaning = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '已清理 $done / ${targets.length} 条${done < targets.length ? '，未完成项已保留' : ''}',
        ),
      ),
    );
  }
}
