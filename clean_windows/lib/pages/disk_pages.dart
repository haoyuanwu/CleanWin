import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/clean_models.dart';
import '../state/app_state.dart';
import '../services/activity_service.dart';
import '../widgets/file_actions_button.dart';
import '../widgets/file_age_filter.dart';
import '../widgets/path_picker.dart';
import '../widgets/duplicate_dialog.dart';

import '../services/disk_services.dart';
import '../services/path_utils.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/disk_treemap.dart';
import '../widgets/disk_controls.dart';
import '../widgets/page_shell.dart';
import '../widgets/module_insights.dart';

/// 磁盘分析：占用地图 + 缓存
class DiskAnalysisPage extends StatefulWidget {
  const DiskAnalysisPage({super.key, this.active = true, this.service});
  final bool active;
  final DiskAnalysisService? service;

  @override
  State<DiskAnalysisPage> createState() => _DiskAnalysisPageState();
}

class _DiskScan {
  final cancel = CancelToken();
  DirUsage? usage;
  String? error;
  bool loading = true;
  Map<String, int>? previousSizes;
}

class _DiskAnalysisPageState extends State<DiskAnalysisPage> {
  late final _service = widget.service ?? DiskAnalysisService();
  final Map<String, _DiskScan> _scans = {};
  final List<String> _stack = [];
  DirUsage? _current;
  bool _loading = false;
  String? _error;
  List<String> _drives = [];
  bool _mapMode = true;
  String _requestedPath = '';
  Map<String, int>? _previousSizes;
  String get _taskId => 'disk-${identityHashCode(this)}';
  String _scanKey(String path) => _normalizePath(path).toLowerCase();
  _DiskScan? get _activeScan => _scans[_scanKey(_requestedPath)];

  @override
  void initState() {
    super.initState();
    _drives = _service.availableDrives();
    if (widget.active) _openInitial();
  }

  void _openInitial() {
    if (_drives.isNotEmpty && _current == null && !_loading) {
      _open('${_drives.contains('C') ? 'C' : _drives.first}:\\');
    }
  }

  @override
  void didUpdateWidget(covariant DiskAnalysisPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _openInitial();
  }

  @override
  void dispose() {
    for (final entry in _scans.entries) {
      entry.value.cancel.cancel();
      TaskBoard.instance.finish('$_taskId:${entry.key}');
    }
    super.dispose();
  }

  Future<void> _open(String path, {bool force = false}) async {
    final key = _scanKey(path);
    final existing = _scans[key];
    // Navigation observes an existing task instead of cancelling or restarting it.
    if (existing != null && (existing.loading || !force)) {
      setState(() => _showScan(path, existing));
      return;
    }
    final scan = _DiskScan();
    scan.previousSizes =
        force && _scanKey(currentPath) == key && _current != null
        ? {for (final child in _current!.children) child.path: child.sizeBytes}
        : null;
    if (force) scan.usage = existing?.usage ?? _current;
    _scans[key] = scan;
    if (force) _service.invalidate(path);
    final cached = !force && _service.isCached(path);
    final taskId = '$_taskId:$key';
    TaskBoard.instance.update(taskId, '磁盘分析', path, cancel: scan.cancel.cancel);
    setState(() => _showScan(path, scan));
    try {
      final usage = await _service.analyzeDirectory(
        path,
        cancel: scan.cancel,
        onProgress: cached
            ? null
            : (partial) {
                scan.usage = partial;
                if (!mounted) return;
                TaskBoard.instance.update(
                  taskId,
                  '磁盘分析',
                  '${partial.path} · ${formatBytes(partial.sizeBytes)}',
                  cancel: scan.cancel.cancel,
                );
                if (_scanKey(_requestedPath) == key) {
                  setState(() => _showScan(path, scan));
                }
              },
      );
      scan.usage = usage;
    } catch (e) {
      scan.error = e.toString();
    } finally {
      scan.loading = false;
      TaskBoard.instance.finish(taskId);
      if (mounted && _scanKey(_requestedPath) == key) {
        setState(() => _showScan(path, scan));
      }
    }
  }

  void _showScan(String path, _DiskScan scan) {
    _requestedPath = path;
    _current = scan.usage;
    _loading = scan.loading;
    _error = scan.error;
    _previousSizes = scan.previousSizes;
  }

  void _push(DirUsage node) {
    final cur = _normalizePath(_requestedPath);
    if (cur.isNotEmpty) _stack.add(cur);
    _open(node.path);
  }

  void _pop() {
    if (_stack.isEmpty) return;
    final prev = _stack.removeLast();
    if (prev.isEmpty) return;
    _open(prev);
  }

  String _normalizePath(String p) {
    var s = p.replaceAll('/', '\\');
    if (s.length > 3 && s.endsWith('\\')) {
      s = s.substring(0, s.length - 1);
    }
    // 统一盘符为大写
    if (s.length >= 2 && s[1] == ':') {
      s = s[0].toUpperCase() + s.substring(1);
    }
    return s;
  }

  /// 从祖先路径跳转，并重建「上一级」栈
  void _goToPath(String targetRaw) {
    final target = _normalizePath(targetRaw);
    _stack.clear();
    if (target.isEmpty) return;
    final parts = target.split('\\').where((part) => part.isNotEmpty).toList();
    var parent = '';
    for (var i = 0; i < parts.length - 1; i++) {
      parent = i == 0 ? '${parts[i]}\\' : '$parent${parts[i]}\\';
      _stack.add(parent);
    }
    _open(target);
  }

  String get currentPath => _current?.path ?? '';

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final ranked = [...?current?.children]
      ..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    final leaders = ranked.take(3).toList();
    final otherBytes = ranked
        .skip(3)
        .fold<int>(0, (sum, node) => sum + node.sizeBytes);

    return Padding(
      padding: kPagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DiskActionBar(
            leading: [
              DiskDriveSelect(
                value: _requestedPath.isEmpty
                    ? null
                    : '${_requestedPath.substring(0, 1).toUpperCase()}:\\',
                roots: [for (final drive in _drives) '$drive:\\'],
                onChanged: (root) {
                  if (root == null ||
                      _requestedPath.toUpperCase() == root.toUpperCase()) {
                    return;
                  }
                  _stack.clear();
                  _open(root);
                },
              ),
            ],
            trailing: [
              IconButton.outlined(
                key: const ValueKey('disk-view-toggle'),
                tooltip: _mapMode ? '切换为列表' : '切换为地图',
                onPressed: () => setState(() => _mapMode = !_mapMode),
                icon: Icon(
                  _mapMode ? Icons.list_rounded : Icons.grid_view_rounded,
                  size: 20,
                ),
              ),
              IconButton.outlined(
                tooltip: _loading ? '停止分析' : '刷新分析',
                onPressed: _loading
                    ? () => _activeScan?.cancel.cancel()
                    : _drives.isEmpty
                    ? null
                    : () => _open(
                        _requestedPath.isEmpty
                            ? '${_drives.first}:\\'
                            : _requestedPath,
                        force: true,
                      ),
                icon: Icon(
                  _loading ? Icons.stop_rounded : Icons.refresh_rounded,
                  size: 20,
                ),
              ),
              IconButton.outlined(
                key: const ValueKey('disk-back'),
                tooltip: '返回上一级',
                onPressed: _stack.isEmpty ? null : _pop,
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ModuleInsights(
            label: _loading ? '已分析空间 · 持续更新' : '当前目录已读取空间',
            value: current == null ? '—' : formatBytes(current.sizeBytes),

            busy: _loading,
            icon: Icons.storage_rounded,
            segments: [
              for (var i = 0; i < leaders.length; i++)
                InsightSegment(
                  label: leaders[i].name,
                  amount: leaders[i].sizeBytes.toDouble(),
                  value: formatBytes(leaders[i].sizeBytes),
                  color: insightColors[i],
                  onTap: leaders[i].isDirectory
                      ? () => _push(leaders[i])
                      : null,
                ),
              if (otherBytes > 0)
                InsightSegment(
                  label: '其他',
                  amount: otherBytes.toDouble(),
                  value: formatBytes(otherBytes),
                  color: AppColors.textTertiary,
                ),
            ],
          ),
          const SizedBox(height: 8),
          // 路径 + 状态 一行
          Row(
            children: [
              Expanded(
                child: _PathBreadcrumb(
                  path: _requestedPath,
                  onNavigate: _goToPath,
                ),
              ),
              const SizedBox(width: 12),
              if (_loading)
                const Row(
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text(
                      '分析中…',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                )
              else if (current != null)
                Text(
                  '${_activeScan?.cancel.cancelled == true ? '已停止 · ' : ''}${formatBytes(current.sizeBytes)} · ${current.children.length} 项',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (current?.unreadablePaths.isNotEmpty == true)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.info_outline_rounded, size: 16),
                label: Text('${current!.unreadablePaths.length} 个位置未纳入统计'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('未纳入统计的位置'),
                    content: SizedBox(
                      width: 550,
                      child: SingleChildScrollView(
                        child: SelectableText(
                          '包含受保护、无法读取或主动跳过的位置，当前容量仅代表已读取数据。\n\n${current.unreadablePaths.take(100).join('\n')}',
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
            ),
          Expanded(
            child: _error != null
                ? EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: '分析失败',
                    subtitle: _error,
                    actionLabel: '重试',
                    action: () => _open(_requestedPath, force: true),
                  )
                : current == null
                ? EmptyState(
                    icon: _loading
                        ? Icons.radar_rounded
                        : Icons.donut_small_rounded,
                    title: _loading ? '正在分析目录…' : '选择磁盘开始分析',
                    subtitle: _loading ? _requestedPath : null,
                  )
                : _mapMode
                ? Card(
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: DiskTreemap(
                        usage: current,
                        onTap: (n) {
                          if (n.isDirectory) _push(n);
                        },
                      ),
                    ),
                  )
                : _buildList(current),
          ),
        ],
      ),
    );
  }

  Widget _buildList(DirUsage current) {
    return Card(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: const Row(
              children: [
                Expanded(
                  child: Text(
                    '名称',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: Text(
                    '文件数',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: Text(
                    '大小',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                SizedBox(width: 40),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: current.children.length,
              itemBuilder: (context, i) {
                final c = current.children[i];
                return FileActionsButton.contextMenu(
                  path: c.path,
                  allowMove: false,
                  actions: [
                    if (c.isDirectory)
                      FileMenuAction(
                        '进入目录',
                        icon: Icons.folder_open_rounded,
                        onSelected: () => _push(c),
                      ),
                  ],
                  child: ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 2,
                    ),
                    leading: Icon(
                      c.isDirectory
                          ? Icons.folder_rounded
                          : Icons.insert_drive_file_rounded,
                      color: c.isDirectory
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      size: 20,
                    ),
                    title: Text(c.name, style: const TextStyle(fontSize: 13)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8, right: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_previousSizes != null)
                            Text(
                              '较上次 ${c.sizeBytes >= (_previousSizes![c.path] ?? 0) ? '+' : '−'}${formatBytes((c.sizeBytes - (_previousSizes![c.path] ?? 0)).abs())}',
                              style: const TextStyle(fontSize: 10),
                            ),
                          ShareBar(
                            fraction: current.sizeBytes <= 0
                                ? 0
                                : c.sizeBytes / current.sizeBytes,
                          ),
                        ],
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 70,
                          child: Text(
                            c.isDirectory ? '${c.fileCount}' : '',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 80,
                          child: SizeText(
                            c.sizeBytes,
                            highlight: c.sizeBytes > 200 * 1024 * 1024,
                          ),
                        ),
                      ],
                    ),
                    onTap: c.isDirectory ? () => _push(c) : null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 可点击路径面包屑：点任一段可跳到该目录
class _PathBreadcrumb extends StatelessWidget {
  const _PathBreadcrumb({required this.path, required this.onNavigate});

  final String path;
  final void Function(String path) onNavigate;

  @override
  Widget build(BuildContext context) {
    if (path.isEmpty) {
      return const SizedBox(height: 28);
    }

    // C:\Users\Name\AppData -> [C:, Users, Name, AppData]
    final norm = path.replaceAll('/', '\\');
    final parts = norm.split('\\').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return const SizedBox.shrink();

    final segments = <({String label, String path})>[];
    var acc = '';
    for (var i = 0; i < parts.length; i++) {
      if (i == 0 && parts[i].endsWith(':')) {
        acc = '${parts[i]}\\';
        segments.add((label: parts[i], path: acc));
      } else {
        acc = acc.endsWith('\\') ? '$acc${parts[i]}' : '$acc\\${parts[i]}';
        if (i < parts.length - 1) acc = '$acc\\';
        segments.add((label: parts[i], path: acc));
      }
    }

    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: segments.length,
        separatorBuilder: (_, _) => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 2),
          child: Icon(
            Icons.chevron_right_rounded,
            size: 16,
            color: AppColors.textSecondary,
          ),
        ),
        itemBuilder: (context, i) {
          final seg = segments[i];
          final isLast = i == segments.length - 1;
          return InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => onNavigate(seg.path),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                seg.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isLast ? FontWeight.w600 : FontWeight.w600,
                  color: isLast ? AppColors.primary : Colors.black87,
                  fontFamily: 'Consolas',
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 大文件管理
class LargeFilesPage extends StatefulWidget {
  const LargeFilesPage({super.key, this.service});

  final LargeFileService? service;

  @override
  State<LargeFilesPage> createState() => _LargeFilesPageState();
}

class _LargeFilesPageState extends State<LargeFilesPage> {
  late final _service = widget.service ?? LargeFileService();
  final List<FileEntry> _files = [];
  final _cancel = CancelToken();
  Timer? _resultFlushTimer;
  bool _scanning = false;
  int _thresholdMb = 500;
  String _root = 'C:\\';
  int _found = 0;
  String _currentDir = '';
  String _query = '';
  String? _kind;
  FileAge _age = FileAge.all;
  String? _notice;
  bool _deleting = false;
  int _visibleLimit = 200;
  String get _largeTaskId => 'large-${identityHashCode(this)}';
  CleanCancellation? _deleteCancellation;
  List<String> _driveRoots = [];

  void _changeRange({String? root, int? threshold}) {
    setState(() {
      _root = root ?? _root;
      _visibleLimit = 200;
      _thresholdMb = threshold ?? _thresholdMb;
      _files.clear();
      _files.addAll(_service.loadCached(_root, _thresholdMb * 1024 * 1024));
      _notice = null;
      _found = 0;
      _currentDir = '';
    });
  }

  DateTime _lastUiFlush = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _driveRoots = DiskAnalysisService()
        .availableDrives()
        .map((drive) => '$drive:\\')
        .toList();
    if (_driveRoots.isNotEmpty && !_driveRoots.contains(_root)) {
      _root = _driveRoots.first;
    }
    // 临时缓存：回放大文件列表
    final cached = _service.loadCached(_root, _thresholdMb * 1024 * 1024);
    if (cached.isNotEmpty) {
      _files.addAll(cached);
    }
  }

  @override
  void dispose() {
    _cancel.cancel();
    _resultFlushTimer?.cancel();
    _deleteCancellation?.cancel();
    TaskBoard.instance.finish(_largeTaskId);
    super.dispose();
  }

  Future<void> _scan() async {
    if (_scanning || _deleting) return;
    _cancel.reset();
    _lastUiFlush = DateTime.fromMillisecondsSinceEpoch(0);
    TaskBoard.instance.update(_largeTaskId, '大文件扫描', _root, cancel: _stopScan);
    setState(() {
      _scanning = true;
      _notice = null;
      _files.clear();
      _visibleLimit = 200;
      _found = 0;
      _currentDir = '';
    });

    final batch = <FileEntry>[];
    void flush() {
      if (batch.isEmpty || !mounted) return;
      setState(() {
        _files.addAll(batch);
        _found = _files.length;
        batch.clear();
      });
    }

    _resultFlushTimer?.cancel();
    _resultFlushTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => flush(),
    );
    try {
      await for (final f in _service.scanLargeFiles(
        _root,
        minBytes: _thresholdMb * 1024 * 1024,
        cancel: _cancel,
        onProgress: (n, dir) {
          if (!mounted) return;
          final now = DateTime.now();
          if (now.difference(_lastUiFlush).inMilliseconds >= 250) {
            TaskBoard.instance.update(
              _largeTaskId,
              '大文件扫描',
              '$n 项 · $dir',
              cancel: _stopScan,
            );
            _lastUiFlush = now;
            setState(() {
              _found = n;
              _currentDir = dir;
            });
          }
        },
      )) {
        batch.add(f);
        // Show the first match immediately; publish subsequent matches on the timer.
        if (_files.isEmpty) flush();
      }
      flush();
      await _service.saveCached(_root, _thresholdMb * 1024 * 1024, _files);
      if (_service.unreadable > 0 && mounted) {
        setState(() => _notice = '${_service.unreadable} 个位置未能读取；当前只显示已读取的文件');
      }
    } on Exception catch (_) {
      _notice = '扫描未完整完成，当前保留已发现的文件';
      flush();
    } finally {
      _resultFlushTimer?.cancel();
      _resultFlushTimer = null;
      flush();
      TaskBoard.instance.finish(_largeTaskId);
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _stopScan() {
    _cancel.cancel();
    setState(() => _notice = '已请求停止，当前仅包含已发现的文件');
  }

  int get _selectedBytes =>
      _files.where((f) => f.selected).fold(0, (s, f) => s + f.sizeBytes);

  @override
  Widget build(BuildContext context) {
    final totalBytes = _files.fold<int>(0, (sum, file) => sum + file.sizeBytes);
    final sorted =
        _files
            .where(
              (file) =>
                  (_kind == null || fileKind(file.name) == _kind) &&
                  _age.includes(file.modified) &&
                  ('${file.name} ${file.path}').toLowerCase().contains(
                    _query.trim().toLowerCase(),
                  ),
            )
            .toList()
          ..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));

    return Padding(
      padding: kPagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DiskActionBar(
            leading: [
              DiskDriveSelect(
                value: _root,
                roots: _driveRoots.contains(_root)
                    ? _driveRoots
                    : [..._driveRoots, _root],
                onChanged: _scanning || _deleting
                    ? null
                    : (value) => _changeRange(root: value),
              ),
              ModuleSelect<int>(
                label: '文件大小阈值',
                value: _thresholdMb,
                items: [
                  for (final size in [100, 200, 500, 1000, 2000])
                    ModuleSelectItem(
                      value: size,
                      child: Text(
                        size >= 1000 ? '大于 ${size ~/ 1000} GB' : '大于 $size MB',
                      ),
                    ),
                ],
                onChanged: _scanning || _deleting
                    ? null
                    : (value) => _changeRange(threshold: value),
              ),
            ],
            trailing: [
              IconButton.outlined(
                tooltip: '指定扫描目录',
                onPressed: _scanning || _deleting
                    ? null
                    : () async {
                        final path = await pickScanDirectory(
                          context,
                          initial: _root,
                        );
                        if (path != null && mounted) _changeRange(root: path);
                      },
                icon: const Icon(Icons.folder_open_rounded, size: 20),
              ),
              IconButton.outlined(
                tooltip: '重复文件检查',
                onPressed: _scanning || _deleting
                    ? null
                    : () => showDuplicateFiles(context, root: _root),
                icon: const Icon(Icons.find_in_page_outlined, size: 20),
              ),
              ElevatedButton.icon(
                onPressed: _deleting || _driveRoots.isEmpty
                    ? null
                    : _scanning
                    ? _stopScan
                    : _scan,
                icon: Icon(
                  _scanning ? Icons.stop_rounded : Icons.radar_rounded,
                  size: 18,
                ),
                label: Text(_scanning ? '停止扫描' : '开始扫描'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ModuleInsights(
            label: '已发现大文件 · ${_files.length} 项',
            value: formatBytes(totalBytes),

            busy: _scanning,
            icon: Icons.data_usage_rounded,
            segments: [
              for (var i = 0; i < fileKinds.length; i++)
                InsightSegment(
                  label: fileKinds[i],
                  amount: _files
                      .where((file) => fileKind(file.name) == fileKinds[i])
                      .fold<double>(0, (sum, file) => sum + file.sizeBytes),
                  value:
                      '${_files.where((file) => fileKind(file.name) == fileKinds[i]).length}',
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
          const SizedBox(height: 6),
          DiskActionBar(
            leading: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  _scanning
                      ? '正在扫描 $_root · 已发现 $_found 个大文件…${_currentDir.isNotEmpty ? '\n$_currentDir' : ''}'
                      : sorted.isEmpty
                      ? (_query.trim().isNotEmpty || _kind != null
                            ? '没有匹配的文件 · 可清空搜索'
                            : '扫描后显示大文件，按容量分页展示')
                      : '${sorted.length} 个文件 · 按大小降序 · 默认不勾选',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
            trailing: [
              FileAgeFilter(
                value: _age,
                onChanged: (age) => setState(() {
                  _age = age;
                  _visibleLimit = 200;
                }),
              ),
              ModuleSearchField(
                hint: '搜索文件名称或路径…',
                onChanged: (value) => setState(() => _query = value),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_notice != null) ...[
            GlassBanner(
              icon: Icons.info_outline_rounded,
              text: _notice!,
              color: AppColors.warning,
            ),
            const SizedBox(height: 10),
          ],
          Expanded(
            child: sorted.isEmpty
                ? EmptyState(
                    icon: Icons.file_copy_rounded,
                    title: _scanning
                        ? '扫描中…'
                        : (_kind != null || _query.trim().isNotEmpty)
                        ? '没有匹配的文件'
                        : '暂无大文件',
                    actionLabel: _scanning ? null : '开始扫描',
                    action: _scanning ? null : _scan,
                  )
                : Card(
                    child: ListView.builder(
                      itemCount: sorted.length > _visibleLimit
                          ? _visibleLimit + 1
                          : sorted.length,
                      itemBuilder: (context, i) {
                        if (i == _visibleLimit) {
                          return Center(
                            child: TextButton(
                              onPressed: () =>
                                  setState(() => _visibleLimit += 200),
                              child: Text('继续显示 · 共 ${sorted.length} 项'),
                            ),
                          );
                        }
                        final f = sorted[i];
                        return FileActionsButton.contextMenu(
                          path: f.path,
                          enabled: !_deleting && !_scanning,
                          actions: [
                            FileMenuAction(
                              f.selected ? '取消勾选' : '勾选此项',
                              icon: Icons.check_box_outlined,
                              onSelected: () =>
                                  setState(() => f.selected = !f.selected),
                            ),
                          ],
                          onMoved: () {
                            if (mounted) setState(() => _files.remove(f));
                            _service.saveCached(
                              _root,
                              _thresholdMb * 1024 * 1024,
                              _files,
                            );
                          },
                          child: CheckboxListTile(
                            value: f.selected,
                            onChanged: _deleting || _scanning
                                ? null
                                : (_) =>
                                      setState(() => f.selected = !f.selected),
                            title: Text(
                              f.name,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizeText(f.sizeBytes, highlight: true),
                                Text(
                                  '修改于 ${f.modified.toLocal().toString().substring(0, 10)}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                const SizedBox(height: 8),
                                ShareBar(
                                  fraction: totalBytes <= 0
                                      ? 0
                                      : f.sizeBytes / totalBytes,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
          if (_files.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .85),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '已选 ${_files.where((file) => file.selected).length} 项 · ${formatBytes(_selectedBytes)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (_deleting)
                    TextButton(
                      onPressed: () => _deleteCancellation?.cancel(),
                      child: const Text('取消'),
                    ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.danger,
                    ),
                    onPressed: _deleting || _scanning || _selectedBytes == 0
                        ? null
                        : _confirmDelete,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: Text(_deleting ? '删除中…' : '删除所选'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDelete() async {
    if (_deleting || _scanning) return;
    final targets = _files.where((f) => f.selected).toList();
    final count = _files.where((f) => f.selected).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('删除大文件'),
        content: Text(
          '将 $count 个文件移到回收站，共 ${formatBytes(_selectedBytes)}。\n可在 Windows 回收站恢复；清空回收站后才释放空间。',
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
    if (ok != true || !mounted) return;

    setState(() => _deleting = true);
    _service.whitelist = context.read<AppState?>()?.whitelist;
    final cancellation = _deleteCancellation = CleanCancellation();
    final taskId = 'delete-$_largeTaskId';
    final journal = context.read<AppState?>()?.journal;
    TaskBoard.instance.update(
      taskId,
      '大文件移入回收站',
      '正在准备',
      cancel: cancellation.cancel,
    );
    CleanReport report;
    try {
      report = await _service.deleteReviewedFiles(
        targets,
        cancellation: cancellation,
        onProgress: (_, message, done, total) {
          TaskBoard.instance.update(
            taskId,
            '大文件移入回收站',
            '$done / $total · $message',
            cancel: cancellation.cancel,
          );
          if (mounted) setState(() => _notice = '处理 $done / $total · $message');
        },
      );
    } catch (_) {
      report = CleanReport(
        freedBytes: 0,
        deletedCount: 0,
        skippedCount: 0,
        failedCount: targets.length,
      );
    } finally {
      TaskBoard.instance.finish(taskId);
    }
    journal?.record(
      '大文件管理',
      report,
      names: targets.map((file) => file.name).toList(),
    );
    if (!mounted) return;
    setState(() {
      _files.removeWhere((file) => report.completedItemIds.contains(file.path));
      _deleting = false;
      _deleteCancellation = null;
      _notice =
          '${report.cancelled ? '已取消 · ' : ''}已移到回收站 ${report.deletedCount} 项，${formatBytes(report.recycledBytes)}；跳过 ${report.skippedCount} 项，失败 ${report.failedCount} 项。${report.failures.take(1).join()}';
    });
    _service.saveCached(_root, _thresholdMb * 1024 * 1024, _files);
  }
}
