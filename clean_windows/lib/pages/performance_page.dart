import 'dart:async';

import 'package:flutter/material.dart';

import '../services/performance_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/page_shell.dart';
import '../widgets/trend_graph.dart';

class PerformancePage extends StatefulWidget {
  const PerformancePage({super.key, this.active = true, this.service});
  final bool active;
  final PerformanceService? service;
  @override
  State<PerformancePage> createState() => _PerformancePageState();
}

class _PerformancePageState extends State<PerformancePage>
    with WidgetsBindingObserver {
  late final PerformanceService _service;
  RuntimeSnapshot? _snap;
  final List<RuntimeSnapshot> _history = [];
  bool _loading = false;
  bool _acting = false;
  bool _foreground = true;
  bool _paused = false;
  String? _error;
  String _query = '';
  Timer? _timer;
  bool get _active => widget.active && _foreground && !_paused;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PerformanceService();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground =
        lifecycle != AppLifecycleState.hidden &&
        lifecycle != AppLifecycleState.paused &&
        lifecycle != AppLifecycleState.detached;
    _syncPolling();
  }

  @override
  void didUpdateWidget(covariant PerformancePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) _syncPolling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground =
        state != AppLifecycleState.hidden &&
        state != AppLifecycleState.paused &&
        state != AppLifecycleState.detached;
    _syncPolling();
  }

  void _syncPolling() {
    _timer?.cancel();
    _timer = null;
    if (!_active) {
      unawaited(_service.pause());
      return;
    }
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_service.dispose());
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading || _acting || !_active) return;
    setState(() => _loading = true);
    try {
      final snapshot = await _service.sample();
      if (!mounted) return;
      setState(() {
        _snap = snapshot;
        _history.add(snapshot);
        if (_history.length > 60) _history.removeAt(0);
        _error = null;
      });
    } on Exception {
      if (mounted) setState(() => _error = '暂时无法更新，稍后将自动重试');
    } on StateError {
      if (mounted) setState(() => _error = '暂时无法更新，稍后将自动重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _memory(double mb) => mb >= 1024
      ? '${(mb / 1024).toStringAsFixed(2)} GB'
      : '${mb.toStringAsFixed(1)} MB';
  String _time(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final s = _snap;
    final query = _query.trim().toLowerCase();
    final processes =
        s?.topProcesses
            .where(
              (process) =>
                  query.isEmpty ||
                  process.name.toLowerCase().contains(query) ||
                  process.pid.toString().contains(query),
            )
            .toList() ??
        <ProcUsage>[];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '运行监控',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _paused
                          ? '已暂停自动刷新 · 当前保留最近数据'
                          : s == null
                          ? '每秒自动刷新 · 按内存占用排序'
                          : '每秒自动刷新 · 更新于 ${_time(s.collectedAt)}',
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
              const SizedBox(width: 8),
              SizedBox(
                height: 42,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: _acting
                      ? null
                      : () {
                          setState(() => _paused = !_paused);
                          _syncPolling();
                        },
                  icon: Icon(
                    _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    size: 18,
                  ),
                  label: Text(_paused ? '继续刷新' : '暂停刷新'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox.square(
                dimension: 42,
                child: IconButton.outlined(
                  tooltip: '刷新',
                  onPressed: _loading || _acting || _paused ? null : _refresh,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: '整理本程序内存，不关闭其他软件',
                child: SizedBox.square(
                  dimension: 42,
                  child: IconButton(
                    onPressed: _acting ? null : _trimMemory,
                    icon: const Icon(Icons.cleaning_services_rounded, size: 18),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (s == null)
            Expanded(
              child: Center(
                child: _error == null
                    ? (_active
                          ? const CircularProgressIndicator()
                          : const Text('打开页面后更新运行状态'))
                    : Text(
                        _error!,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
              ),
            )
          else ...[
            if (_error != null)
              GlassBanner(
                icon: Icons.sync_problem_rounded,
                text: '$_error，当前显示上次成功读取的数据。',
                color: AppColors.warning,
              )
            else
              _AlertBar(snapshot: s),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    label: '内存占用',
                    value: '${s.memoryUsedPercent.toStringAsFixed(1)}%',
                    icon: Icons.memory_rounded,
                    color: s.memHigh ? AppColors.warning : AppColors.primary,
                    bar: s.memoryUsedPercent / 100,
                    history: _history
                        .map((sample) => sample.memoryUsedPercent)
                        .toList(),
                    hint: s.totalMemoryMb > 0
                        ? '${_memory(s.usedMemoryMb)} / ${_memory(s.totalMemoryMb)}'
                        : '系统物理内存',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricCard(
                    label: 'CPU 占用',
                    value: '${s.cpuPercent.toStringAsFixed(1)}%',
                    icon: Icons.speed_rounded,
                    color: s.cpuHigh ? AppColors.warning : AppColors.primary,
                    bar: s.cpuPercent / 100,
                    history: _history
                        .map((sample) => sample.cpuPercent)
                        .toList(),
                    hint: s.cpuHigh ? '占用偏高' : '系统整体占用',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricCard(
                    label: '温度参考',
                    value: s.cpuTempC == null
                        ? '—'
                        : '${s.cpuTempC!.toStringAsFixed(0)}°C',
                    icon: Icons.thermostat_rounded,
                    color: s.tempWarn ? AppColors.warning : AppColors.success,
                    bar: s.cpuTempC == null
                        ? 0
                        : (s.cpuTempC! / 110).clamp(0, 1),
                    hint: s.tempStatus,
                    history: _history.map((sample) => sample.cpuTempC).toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        query.isEmpty
                            ? '进程 · ${processes.length} 项'
                            : '进程 · ${processes.length} / ${s.topProcesses.length} 项',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Text(
                        '按内存占用从高到低排列',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                ModuleSearchField(
                  fieldKey: const ValueKey('process-search'),
                  hint: '搜索进程名称或 PID',
                  onChanged: (value) => setState(() => _query = value),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 7,
                      ),
                      color: Colors.white.withValues(alpha: 0.4),
                      child: const Row(
                        children: [
                          Expanded(
                            child: Text(
                              '进程名称',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          Tooltip(
                            message: '按当前物理内存工作集从高到低排列，包含共享内存',
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '内存占用',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Icon(
                                  Icons.arrow_downward_rounded,
                                  size: 13,
                                  color: AppColors.primary,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: 84),
                        ],
                      ),
                    ),
                    Expanded(
                      child: processes.isEmpty
                          ? Center(
                              child: Text(
                                query.isEmpty ? '暂未读取到进程' : '没有匹配的进程',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            )
                          : ListView.builder(
                              key: const PageStorageKey(
                                'performance-process-list',
                              ),
                              itemExtent: 50,
                              itemCount: processes.length,
                              itemBuilder: (context, index) {
                                final process = processes[index];
                                final highest = s.topProcesses.isEmpty
                                    ? 0.0
                                    : s.topProcesses.first.memoryMb;
                                return _ProcessRow(
                                  key: ValueKey('process-${process.pid}'),
                                  process: process,
                                  memory: _memory(process.memoryMb),
                                  rank: index + 1,
                                  fraction: highest <= 0
                                      ? 0
                                      : (process.memoryMb / highest).clamp(
                                          0,
                                          1,
                                        ),
                                  onEnd: _acting || !process.canTerminate
                                      ? null
                                      : () => _confirmKill(process),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _trimMemory() async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      final success = await _service.trimMemory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success ? '已整理本程序的内存工作集' : '内存整理未完成，请稍后重试')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _acting = false);
        unawaited(_refresh());
      }
    }
  }

  Future<void> _confirmKill(ProcUsage process) async {
    if (_acting || !process.canTerminate) return;
    setState(() => _acting = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('结束进程'),
          content: Text(
            '确定结束「${process.name}」(PID ${process.pid})？未保存的数据可能丢失。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('结束进程'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final success = await _service.killProcess(process.pid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? '已结束 ${process.name}'
                  : '未能结束 ${process.name}，可能已退出或需要权限',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _acting = false);
        unawaited(_refresh());
      }
    }
  }
}

class _ProcessRow extends StatelessWidget {
  const _ProcessRow({
    super.key,
    required this.process,
    required this.memory,
    required this.rank,
    required this.fraction,
    this.onEnd,
  });
  final ProcUsage process;
  final String memory;
  final int rank;
  final double fraction;
  final VoidCallback? onEnd;
  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        SizedBox(
          width: 24,
          child: Text(
            '$rank',
            style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
          ),
        ),
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primarySoft.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            process.name.isEmpty
                ? '?'
                : process.name.characters.first.toUpperCase(),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Tooltip(
                message: process.name,
                child: Text(
                  process.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                'PID ${process.pid}',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 116,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                memory,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 3,
                  color: AppColors.primary.withValues(alpha: 0.65),
                  backgroundColor: AppColors.primarySoft.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        TextButton(
          onPressed: onEnd,
          child: const Text('结束', style: TextStyle(fontSize: 12)),
        ),
      ],
    ),
  );
}

class _AlertBar extends StatelessWidget {
  const _AlertBar({required this.snapshot});
  final RuntimeSnapshot snapshot;
  @override
  Widget build(BuildContext context) {
    final warning = snapshot.cpuHigh || snapshot.memHigh || snapshot.tempWarn;
    final message = snapshot.memHigh
        ? '内存占用较高，可查看下方占用最多的进程。'
        : snapshot.cpuHigh
        ? 'CPU 占用较高，请留意后台运行的软件。'
        : snapshot.tempWarn
        ? '系统温度偏高，建议检查散热情况。'
        : snapshot.cpuTempC == null
        ? 'CPU 与内存暂未发现高占用，温度传感器暂不可用。'
        : 'CPU 与内存暂未发现高占用。';
    final color = warning ? AppColors.warning : AppColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            warning
                ? Icons.info_outline_rounded
                : Icons.check_circle_outline_rounded,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(message, style: TextStyle(fontSize: 11, color: color)),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.bar,
    required this.hint,
    required this.history,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final double bar;
  final String hint;
  final List<double?> history;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 15),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: color,
                    height: 1.1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TrendGraph(values: history, color: color, height: 24),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: bar.clamp(0, 1),
                minHeight: 3,
                backgroundColor: color.withValues(alpha: 0.12),
                color: color,
              ),
            ),
            const SizedBox(height: 5),
            Tooltip(
              message: hint,
              child: Text(
                hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
