import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/path_utils.dart';
import '../models/clean_models.dart';
import '../models/workspace_structure.dart';
import 'cosmic_scene.dart';
import '../state/app_state.dart';

Duration cleanMotion(BuildContext context, int milliseconds) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

class CleanAnimatedSize extends StatelessWidget {
  const CleanAnimatedSize({
    super.key,
    required this.child,
    required this.duration,
    this.alignment = Alignment.center,
  });
  final Widget child;
  final Duration duration;
  final AlignmentGeometry alignment;
  @override
  Widget build(BuildContext context) => MediaQuery.disableAnimationsOf(context)
      ? child
      : AnimatedSize(duration: duration, alignment: alignment, child: child);
}

class AnimatedByteCount extends StatelessWidget {
  const AnimatedByteCount({
    super.key,
    required this.bytes,
    required this.style,
  });
  final int bytes;
  final TextStyle style;
  @override
  Widget build(BuildContext context) => Semantics(
    label: formatBytes(bytes),
    child: ExcludeSemantics(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: bytes.toDouble()),
        duration: cleanMotion(context, 450),
        curve: Curves.easeOutCubic,
        builder: (_, value, _) =>
            Text(formatBytes(value.round()), maxLines: 1, style: style),
      ),
    ),
  );
}

class CleanOverview extends StatefulWidget {
  const CleanOverview({
    super.key,
    required this.state,
    required this.hasResults,
    required this.onScan,
    required this.cleanedAt,
    required this.onCategory,
    required this.onSmartClean,
    required this.onViewResults,
  });
  final AppState state;
  final bool hasResults;
  final VoidCallback onScan;
  final VoidCallback onViewResults;
  final VoidCallback? onSmartClean;
  final ValueChanged<CleanCategory> onCategory;
  final DateTime? cleanedAt;
  @override
  State<CleanOverview> createState() => _CleanOverviewState();
}

class _CleanOverviewState extends State<CleanOverview> {
  ({int total, int free})? _space;
  bool _loadingDisk = true;
  bool _celebrating = false;
  final _drive = (Platform.environment['SystemDrive'] ?? 'C:').replaceAll(
    ':',
    '',
  );
  @override
  void initState() {
    super.initState();
    unawaited(_loadDisk());
  }

  @override
  void didUpdateWidget(covariant CleanOverview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cleanedAt != widget.cleanedAt && widget.cleanedAt != null) {
      _celebrating = true;
      unawaited(_loadDisk());
    }
    if (widget.state.scanning) _celebrating = false;
  }

  Future<void> _loadDisk() async {
    try {
      final disk = await context.read<AppState>().diskSpace(_drive);
      if (mounted) {
        setState(() {
          _space = disk;
          _loadingDisk = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _space = null;
          _loadingDisk = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final busy = state.scanning || state.cleaning;
    final incomplete =
        state.scanError != null ||
        (widget.hasResults &&
            state.categories.any((category) => category.error != null));
    final disk = _space;
    final introduction = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: incomplete ? const Color(0xFFF5C985) : CosmicColors.cyan,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                state.scanning
                    ? '正在探测磁盘星域'
                    : _celebrating
                    ? state.lastFreedBytes > 0
                          ? '清理完成 · 空间已释放'
                          : '清理完成 · 文件已处理'
                    : incomplete
                    ? '部分内容未完成 · 请核对提示'
                    : widget.hasResults
                    ? '探测完成 · 等待清理'
                    : '系统在线 · 等待探索',
                style: const TextStyle(fontSize: 12, color: CosmicColors.cyan),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        AnimatedSwitcher(
          duration: cleanMotion(context, 350),
          child: Align(
            key: ValueKey(_celebrating),
            alignment: Alignment.centerLeft,
            child: Text(
              _celebrating
                  ? state.lastFreedBytes > 0
                        ? '为电脑释放了\n${formatBytes(state.lastFreedBytes)} 空间'
                        : '本次清理已完成\n文件已安全处理'
                  : '为你的电脑\n释放一片星空',
              style: TextStyle(
                fontSize: widget.hasResults ? 26 : 31,
                height: 1.35,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -.6,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          state.scanError ??
              (widget.hasResults
                  ? '已默认选择可清理项目，显卡缓存除外。'
                  : '发现散落的缓存，让空间重新轻盈。'),
          style: const TextStyle(
            fontSize: 13,
            height: 1.7,
            color: CosmicColors.muted,
          ),
        ),
        const SizedBox(height: 25),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: busy ? null : widget.onScan,
              style: ElevatedButton.styleFrom(
                backgroundColor: CosmicColors.cyan,
                foregroundColor: CosmicColors.background,
                padding: const EdgeInsets.symmetric(
                  horizontal: 21,
                  vertical: 19,
                ),
              ),
              icon: Icon(
                widget.hasResults || incomplete
                    ? Icons.refresh_rounded
                    : Icons.radar_rounded,
                size: 19,
              ),
              label: Text(
                state.scanning
                    ? '正在扫描…'
                    : widget.hasResults || incomplete
                    ? '重新扫描'
                    : '开始扫描',
              ),
            ),
            if (state.scanning)
              OutlinedButton.icon(
                onPressed: state.cancelScan,
                icon: const Icon(Icons.stop_rounded, size: 18),
                label: const Text('取消扫描'),
              ),
            if (widget.hasResults)
              TextButton.icon(
                onPressed: widget.onViewResults,
                icon: const Icon(Icons.south_rounded, size: 16),
                label: const Text('查看结果'),
              ),
          ],
        ),
        if (!widget.hasResults && !state.scanning)
          const Padding(
            padding: EdgeInsets.only(top: 18),
            child: Text(
              '白名单保护已开启 · 扫描不会删除文件',
              style: TextStyle(fontSize: 11, color: CosmicColors.muted),
            ),
          ),
      ],
    );
    final orbit = CosmicOrbit(
      scanning: state.scanning,
      cleaning: state.cleaning,
      celebrating: _celebrating,
      progress: state.progress.ratio,
      hasResults: widget.hasResults,
      results: state.results,
      onCategory: widget.onCategory,
      center: Semantics(
        button: true,
        label: widget.hasResults
            ? '已选总量 ${formatBytes(_overviewSelectedBytes(state))}，点击清理已选项目'
            : '扫描磁盘',
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: busy
              ? null
              : widget.hasResults
              ? widget.onSmartClean
              : widget.onScan,
          child: SizedBox(
            width: 180,
            height: 180,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  state.scanning
                      ? Icons.radar_rounded
                      : _celebrating
                      ? Icons.check_rounded
                      : Icons.auto_awesome_rounded,
                  color: CosmicColors.cyan,
                  size: 23,
                ),
                const SizedBox(height: 12),
                if (state.scanning)
                  Text(
                    '${(state.progress.ratio * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 34,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else if (widget.hasResults)
                  AnimatedByteCount(
                    key: const ValueKey('orbit-selected-total'),
                    bytes: _overviewSelectedBytes(state),
                    style: const TextStyle(
                      fontSize: 27,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else
                  const Text(
                    '准备就绪',
                    style: TextStyle(
                      fontSize: 23,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const SizedBox(height: 7),
                Text(
                  state.scanning
                      ? '扫描进行中'
                      : widget.hasResults
                      ? '已选总量'
                      : '开启空间探索',
                  style: const TextStyle(
                    fontSize: 11,
                    color: CosmicColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 720
              ? Row(
                  children: [
                    Expanded(flex: 5, child: introduction),
                    const SizedBox(width: 12),
                    Expanded(flex: 6, child: orbit),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [introduction, const SizedBox(height: 10), orbit],
                ),
        ),
        if (state.scanning)
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: CosmicColors.panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: CosmicColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: state.progress.ratio > 0 ? state.progress.ratio : null,
                  minHeight: 3,
                  color: CosmicColors.cyan,
                  backgroundColor: CosmicColors.line,
                ),
                const SizedBox(height: 10),
                Text(
                  '${state.progress.message} · ${state.progress.completedCategories}/${state.progress.totalCategories}',
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Tooltip(
                  message: state.progress.currentPath,
                  child: Text(
                    state.progress.currentPath.isEmpty
                        ? '正在定位扫描位置…'
                        : state.progress.currentPath,
                    key: const ValueKey('scan-current-path'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontSize: 11,
                      color: CosmicColors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final panels = [
              _MetricPanel(
                key: const ValueKey('clean-disk-overview'),
                icon: Icons.storage_rounded,
                label: '系统盘 $_drive:',
                value: _loadingDisk
                    ? '读取空间中…'
                    : disk == null || disk.total <= 0
                    ? '暂时无法读取'
                    : '${formatBytes(disk.free)} 可用',
                detail: disk == null || disk.total <= 0
                    ? '磁盘空间'
                    : '共 ${formatBytes(disk.total)}',
                onRefresh: _loadingDisk
                    ? null
                    : () {
                        setState(() => _loadingDisk = true);
                        unawaited(_loadDisk());
                      },
              ),
              _MetricPanel(
                icon: Icons.blur_circular_rounded,
                label: widget.hasResults ? '已探测内容' : '探索范围',
                value: widget.hasResults
                    ? formatBytes(_overviewFoundBytes(state))
                    : '缓存 · 日志 · 回收站',
                detail: widget.hasResults
                    ? '${state.categories.where((entry) => cleanupOwner(entry.category) == 0).length} 类清理内容已检查'
                    : '扫描后默认选择，显卡缓存除外',
              ),
              const _MetricPanel(
                icon: Icons.shield_outlined,
                label: '保护机制',
                value: '默认选择安全候选',
                detail: '显卡缓存仍需手动选择',
              ),
            ];
            if (constraints.maxWidth < 600) {
              return Column(
                children: [
                  for (final panel in panels)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: panel,
                    ),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < panels.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(child: panels[i]),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _MetricPanel extends StatelessWidget {
  const _MetricPanel({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    this.onRefresh,
  });
  final IconData icon;
  final String label, value, detail;
  final VoidCallback? onRefresh;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: CosmicColors.panel,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: CosmicColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: CosmicColors.cyan),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 11, color: CosmicColors.muted),
              ),
            ),
            if (onRefresh != null)
              SizedBox(
                width: 20,
                height: 18,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: '刷新磁盘空间',
                  onPressed: onRefresh,
                  icon: const Icon(
                    Icons.refresh_rounded,
                    size: 15,
                    color: CosmicColors.muted,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          detail,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10, color: CosmicColors.muted),
        ),
      ],
    ),
  );
}

int _overviewSelectedBytes(AppState state) => state.categories
    .where((entry) => cleanupOwner(entry.category) == 0)
    .expand((entry) => entry.items)
    .where((item) => item.selected)
    .fold<int>(0, (sum, item) => sum + item.sizeBytes);
int _overviewFoundBytes(AppState state) => state.categories
    .where((entry) => cleanupOwner(entry.category) == 0)
    .fold<int>(0, (sum, entry) => sum + entry.totalSizeBytes);
