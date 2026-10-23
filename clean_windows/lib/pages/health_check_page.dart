import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/health_check_service.dart';
import '../theme/app_theme.dart';
import '../widgets/page_shell.dart';
import '../widgets/cosmic_scene.dart';

class HealthCheckPage extends StatefulWidget {
  const HealthCheckPage({
    super.key,
    required this.onNavigate,
    required this.onScanTraces,
    this.controller,
    this.spaceCleanup,
    this.embedded = false,
    this.sectionIds,
    this.title,
  });
  final ValueChanged<int> onNavigate;
  final Future<bool> Function() onScanTraces;
  final HealthCheckController? controller;
  final Widget? spaceCleanup;
  final bool embedded;
  final Set<String>? sectionIds;
  final String? title;
  @override
  State<HealthCheckPage> createState() => _HealthCheckPageState();
}

class _HealthCheckPageState extends State<HealthCheckPage> {
  late final _controller = widget.controller ?? HealthCheckController();
  bool _flushing = false;
  bool _traces = false;
  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _settings(HealthSettings settings) async {
    try {
      await settings.open();
    } catch (_) {
      _message('无法打开 Windows 设置，请从系统设置进入');
    }
  }

  Future<void> _flushDns() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.dns_outlined),
        title: const Text('刷新 DNS 缓存？'),
        content: const SizedBox(
          width: 360,
          child: Text('清除本机域名解析缓存；下一次访问会重新解析。DNS 服务器、代理和静态 IP 设置保持不变。'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('刷新'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _flushing = true);
    final success = await _controller.service.flushDns();
    if (!mounted) return;
    setState(() => _flushing = false);
    _message(success ? 'DNS 缓存已刷新' : '刷新失败，可使用管理员终端执行 ipconfig /flushdns');
  }

  Future<void> _scanTraces() async {
    setState(() => _traces = true);
    try {
      final success = await widget.onScanTraces();
      _message(success ? '使用痕迹已扫描，可在概览中查看并手动选择' : '当前有清理或扫描任务，请完成后再试');
    } catch (_) {
      _message('使用痕迹扫描未完成，请重试');
    } finally {
      if (mounted) setState(() => _traces = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final c = _controller;
      if (widget.sectionIds != null) return _scoped(context, c);
      if (widget.embedded) return _embedded(context, c);
      return ModulePageShell(
        title: '全面体检',
        toolbar: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            IconButton.filledTonal(
              tooltip: '复制体检报告（含本机配置与 IP）',
              onPressed: c.sections.isEmpty
                  ? null
                  : () async {
                      await Clipboard.setData(ClipboardData(text: c.report()));
                      _message('体检报告已复制');
                    },
              icon: const Icon(Icons.copy_all_outlined),
            ),
            if (c.scanning)
              TextButton.icon(
                onPressed: c.cancelled ? null : c.cancel,
                icon: const Icon(Icons.stop_circle_outlined),
                label: Text(c.cancelled ? '正在取消' : '取消'),
              ),
            FilledButton.icon(
              key: const ValueKey('health-scan'),
              onPressed: c.scanning || c.probing
                  ? null
                  : () => unawaited(c.scan()),
              icon: Icon(
                c.sections.isEmpty
                    ? Icons.radar_rounded
                    : Icons.refresh_rounded,
              ),
              label: Text(
                c.scanning
                    ? '体检中'
                    : c.sections.isEmpty
                    ? '开始体检'
                    : '重新体检',
              ),
            ),
          ],
        ),
        child: ListView(
          key: const PageStorageKey('health-scroll'),
          children: [
            _summary(context, c),
            const SizedBox(height: 16),
            if (widget.spaceCleanup != null) ...[
              widget.spaceCleanup!,
              const SizedBox(height: 16),
            ],
            if (c.sections.isNotEmpty) ...[
              for (final section in c.sections)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _HealthSectionCard(
                    key: ValueKey('health-${section.id}'),
                    section: section,
                    stale: !c.isFresh(section.id),
                    actions: _actions(section.id),
                  ),
                ),
              const SizedBox(height: 6),
            ],
            Text('清理与管理', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth >= 660
                    ? (constraints.maxWidth - 20) / 3
                    : (constraints.maxWidth - 10) / 2;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final item in const [
                      (0, Icons.auto_awesome_outlined, '一键清理'),
                      (4, Icons.speed_rounded, '运行监控'),
                      (5, Icons.apps_rounded, '软件卸载'),
                      (6, Icons.rocket_launch_outlined, '启动项'),
                      (8, Icons.download_outlined, '下载管理'),
                      (2, Icons.donut_small_outlined, '磁盘分析'),
                    ])
                      SizedBox(
                        width: width,
                        child: _ModuleLink(
                          icon: item.$2,
                          label: item.$3,
                          onTap: () => widget.onNavigate(item.$1),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Tooltip(
                message: '扫描最近文件快捷方式与跳转列表；不会删除原文件，需在概览中手动勾选。',
                child: TextButton.icon(
                  onPressed: _traces ? null : _scanTraces,
                  icon: const Icon(Icons.history_rounded),
                  label: Text(_traces ? '扫描使用痕迹中…' : '扫描使用痕迹'),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
        ),
      );
    },
  );

  Widget _scoped(BuildContext context, HealthCheckController c) {
    final ids = widget.sectionIds!;
    final sections = c.sections
        .where(
          (section) =>
              ids.contains(section.id) ||
              (ids.contains('network') && section.id == 'connectivity'),
        )
        .toList();
    final attention = sections.fold<int>(
      0,
      (n, section) => n + section.attentionCount,
    );
    final unavailable = sections.fold<int>(
      0,
      (n, section) => n + section.unavailableCount,
    );
    return ModulePageShell(
      title: widget.title ?? '系统检查',
      toolbar: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          IconButton(
            tooltip: '复制当前检查结果（可能包含本机配置和 IP）',
            onPressed: sections.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(
                      ClipboardData(
                        text: sections
                            .map(
                              (section) =>
                                  '${section.title}\n${section.entries.map((entry) => '${entry.label}：${entry.value}').join('\n')}',
                            )
                            .join('\n\n'),
                      ),
                    );
                    _message('已复制当前检查结果');
                  },
            icon: const Icon(Icons.copy_all_outlined),
          ),
          if (c.scanning && !c.startupReading)
            TextButton.icon(
              onPressed: c.cancelled ? null : c.cancel,
              icon: const Icon(Icons.stop_circle_outlined),
              label: Text(c.cancelled ? '正在取消' : '取消检查'),
            ),
          FilledButton.icon(
            key: ValueKey('inspect-${ids.first}'),
            onPressed: c.scanning || c.probing
                ? null
                : () => c.scan(phaseIds: ids),
            icon: Icon(
              sections.isEmpty ? Icons.radar_rounded : Icons.refresh_rounded,
            ),
            label: Text(
              c.scanning
                  ? (c.startupReading ? '读取中' : '正在检查')
                  : sections.isEmpty
                  ? '读取信息'
                  : '刷新',
              style: c.scanning
                  ? const TextStyle(color: AppColors.textSecondary)
                  : null,
            ),
          ),
        ],
      ),
      banner: ids.contains('network')
          ? TextButtonTheme(
              data: TextButtonThemeData(
                style: TextButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary
                      .withValues(alpha: .07),
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              child: Wrap(
                key: const ValueKey('network-top-actions'),
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final action in _actions('network'))
                    SizedBox(height: 40, child: action),
                ],
              ),
            )
          : null,
      child: ListView(
        key: PageStorageKey('inspection-${ids.first}'),
        children: [
          if (c.scanning && !c.startupReading) ...[
            const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(c.cancelled ? '正在取消，保留已有结果' : '正在读取${c.current}'),
            ),
          ],
          if (sections.isEmpty && (!c.scanning || c.startupReading))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(
                    ids.contains('network')
                        ? Icons.hub_outlined
                        : ids.contains('hardware')
                        ? Icons.memory_rounded
                        : Icons.tune_rounded,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.title ?? '系统检查',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(c.startupReading ? '正在后台读取本机信息' : '暂未读取到信息，可点击刷新重试'),
                ],
              ),
            ),
          if (sections.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  Text(
                    '${sections.fold<int>(0, (n, section) => n + section.entries.length)} 项信息',
                  ),
                  Text('$attention 项需留意'),
                  if (unavailable > 0) Text('$unavailable 项未读取'),
                  if (c.cancelled) const Text('已取消 · 保留结果'),
                ],
              ),
            ),
            for (final section in sections)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _HealthSectionCard(
                  key: ValueKey('inspection-${section.id}'),
                  section: section,
                  stale: !c.isFresh(section.id),
                  initiallyExpanded: true,
                  actions: section.id == 'network'
                      ? const []
                      : _actions(section.id),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _embedded(BuildContext context, HealthCheckController c) {
    final status = c.scanning
        ? '正在检查${c.current}'
        : c.cancelled
        ? '已取消 · 保留完成项'
        : '${c.sections.length} 类 · ${c.attentionCount} 项留意${c.unavailableCount > 0 ? ' · ${c.unavailableCount} 项未读取' : ''}';
    return Material(
      color: CosmicColors.panel,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: const PageStorageKey('overview-health-results'),
        collapsedIconColor: CosmicColors.muted,
        iconColor: CosmicColors.cyan,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const Icon(
          Icons.fact_check_outlined,
          color: CosmicColors.cyan,
        ),
        title: const Text(
          '电脑体检',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          status,
          style: const TextStyle(color: CosmicColors.muted, fontSize: 12),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          if (c.scanning)
            LinearProgressIndicator(
              value: c.completedPhases / HealthCheckService.phases.length,
              color: CosmicColors.cyan,
            ),
          if (c.sections.isNotEmpty)
            Theme(
              data: AppTheme.light(),
              child: Builder(
                builder: (context) => Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F3F4),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          tooltip: '复制体检报告（含本机配置与 IP）',
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: c.report()),
                            );
                            _message('体检报告已复制');
                          },
                          icon: const Icon(Icons.copy_all_outlined),
                        ),
                      ),
                      for (final section in c.sections)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _HealthSectionCard(
                            key: ValueKey('health-${section.id}'),
                            section: section,
                            stale: !c.isFresh(section.id),
                            actions: _actions(section.id),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _summary(BuildContext context, HealthCheckController c) {
    final status = c.scanning
        ? (c.cancelled ? '正在取消' : '正在检查${c.current}')
        : c.cancelled
        ? '体检已取消'
        : c.sections.isEmpty
        ? '了解电脑的当前状态'
        : '${c.attentionCount} 项需要留意';
    final unavailable = c.unavailableCount;
    final subtitle = c.scanning
        ? '已完成 ${c.completedPhases} / ${HealthCheckService.phases.length} 类'
        : c.sections.isEmpty
        ? '硬件 · 网络 · 空间 · 应用 · 设置'
        : [
            if (c.completedAt != null) '上次完整体检 ${_time(c.completedAt!)}',
            if (unavailable > 0) '$unavailable 项未能读取',
            if (c.cancelled) '已保留完成项与上次结果',
          ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF193A43),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: c.scanning
                        ? c.completedPhases / HealthCheckService.phases.length
                        : 1,
                    strokeWidth: 3,
                    color: const Color(0xFF9CD9CB),
                    backgroundColor: Colors.white12,
                  ),
                ),
                Icon(
                  c.scanning ? Icons.radar_rounded : Icons.fact_check_outlined,
                  size: 29,
                  color: const Color(0xFFD8F0E9),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
                  child: Align(
                    key: ValueKey(status),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      status,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFFBCD4D7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _time(DateTime time) =>
      '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  List<Widget> _actions(String section) => switch (section) {
    'network' => [
      TextButton.icon(
        onPressed: _controller.scanning || _controller.probing || _flushing
            ? null
            : () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('检测外网连通性？'),
                    content: const Text(
                      '将解析 www.microsoft.com 并发送 3 次 ICMP 探测，显示延迟与未响应比例。不会更改网络设置。',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('检测'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true || !mounted) return;
                try {
                  await _controller.probeConnectivity();
                } catch (_) {
                  _message('外网探测未完成，请检查网络后重试');
                }
              },
        icon: const Icon(Icons.network_ping_rounded),
        label: Text(_controller.probing ? '探测中…' : '外网探测'),
      ),

      TextButton.icon(
        onPressed: () => _settings(HealthSettings.network),
        icon: const Icon(Icons.settings_ethernet_rounded),
        label: const Text('网络设置'),
      ),
      TextButton(
        onPressed: () => _settings(HealthSettings.proxy),
        child: const Text('代理设置'),
      ),
      TextButton(
        onPressed: () => _settings(HealthSettings.troubleshoot),
        child: const Text('疑难解答'),
      ),
      TextButton(
        onPressed: _flushing || _controller.scanning || _controller.probing
            ? null
            : _flushDns,
        child: Text(_flushing ? '正在刷新…' : '刷新 DNS'),
      ),
    ],
    'storage' => [
      TextButton.icon(
        onPressed: () => widget.onNavigate(0),
        icon: const Icon(Icons.cleaning_services_outlined),
        label: const Text('查看清理'),
      ),
    ],
    'applications' => [
      TextButton(
        onPressed: () => widget.onNavigate(6),
        child: const Text('管理启动项'),
      ),
      TextButton(
        onPressed: () => widget.onNavigate(5),
        child: const Text('查看软件'),
      ),
    ],
    'preferences' => [
      TextButton(
        onPressed: () => _settings(HealthSettings.defaults),
        child: const Text('默认应用'),
      ),
      TextButton(
        onPressed: () => _settings(HealthSettings.taskbar),
        child: const Text('任务栏'),
      ),
      TextButton(
        onPressed: () => _settings(HealthSettings.lockScreen),
        child: const Text('锁屏'),
      ),
      TextButton(
        onPressed: () => _settings(HealthSettings.notifications),
        child: const Text('通知与弹窗'),
      ),
      TextButton(
        onPressed: () => _settings(HealthSettings.startup),
        child: const Text('系统启动应用'),
      ),
    ],
    _ => [],
  };
}

class _HealthSectionCard extends StatelessWidget {
  const _HealthSectionCard({
    super.key,
    required this.section,
    this.initiallyExpanded = false,
    required this.stale,
    required this.actions,
  });
  final HealthSection section;
  final bool initiallyExpanded;
  final bool stale;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    final icon = switch (section.id) {
      'hardware' => Icons.developer_board_outlined,
      'network' || 'connectivity' => Icons.lan_outlined,
      'storage' => Icons.storage_rounded,
      'applications' => Icons.apps_rounded,
      _ => Icons.tune_rounded,
    };
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        key: PageStorageKey('expand-${section.id}'),
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(icon, color: const Color(0xFF246B70)),
        title: Text(
          section.title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          stale
              ? '上次结果'
              : '${section.entries.length} 项${section.attentionCount > 0 ? ' · ${section.attentionCount} 项留意' : ''}${section.unavailableCount > 0 ? ' · ${section.unavailableCount} 项未读取' : ''}',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
        children: [
          for (final entry in section.entries) _entry(context, entry),
          if (section.id == 'network')
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                '连通状态由 Windows 提供；未向外网发起 DNS、测速或连通性请求。',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(spacing: 6, runSpacing: 6, children: actions),
              ),
            ),
        ],
      ),
    );
  }

  Widget _entry(BuildContext context, HealthEntry entry) {
    final (color, icon, state) = switch (entry.status) {
      HealthStatus.normal => (
        const Color(0xFF247870),
        Icons.check_circle_outline_rounded,
        '正常',
      ),
      HealthStatus.attention => (
        const Color(0xFF98621C),
        Icons.info_outline_rounded,
        '需留意',
      ),
      HealthStatus.info => (
        const Color(0xFF516B83),
        Icons.circle_outlined,
        '配置信息',
      ),
      HealthStatus.unavailable => (
        AppColors.textTertiary,
        Icons.help_outline_rounded,
        '未读取',
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFEDF1F2))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tooltip(
            message: state,
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final label = Text(
                  entry.label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                );
                final value = SelectableText(
                  entry.value,
                  key: PageStorageKey('health-value-${section.id}-${entry.id}'),
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.55,
                    color: AppColors.textPrimary,
                  ),
                );
                if (constraints.maxWidth < 500) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [label, const SizedBox(height: 5), value],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 130, child: label),
                    const SizedBox(width: 16),
                    Expanded(child: value),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ModuleLink extends StatelessWidget {
  const _ModuleLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: .75),
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 20, color: const Color(0xFF246B70)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    ),
  );
}
