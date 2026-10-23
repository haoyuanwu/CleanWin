import 'package:flutter/material.dart';

import '../services/performance_service.dart';
import 'monitor_surface.dart';
import 'resource_dial.dart';
import 'trend_graph.dart';

String formatNetworkRate(double? bytes) {
  if (bytes == null) return '—';
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB/s';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB/s';
  return '${bytes.toStringAsFixed(0)} B/s';
}

class RuntimeDashboard extends StatelessWidget {
  const RuntimeDashboard({
    super.key,
    required this.snapshot,
    required this.history,
  });
  final RuntimeSnapshot snapshot;
  final List<RuntimeSnapshot> history;

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    return MonitorSurface(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 700;
          final columns = constraints.maxWidth >= 500
              ? 3
              : (constraints.maxWidth >= 420 ? 2 : 1);
          final width =
              (constraints.maxWidth - 32 - (columns - 1) * 12) / columns;
          return ListView(
            key: const PageStorageKey('runtime-dashboard'),
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  const Icon(Icons.radar_rounded, size: 18),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '资源仪表',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    '${history.length} / 60 次采样',
                    style: const TextStyle(fontSize: 12, color: monitorMuted),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: width,
                    child: _metric(
                      context,
                      'CPU 占用',
                      Icons.speed_rounded,
                      '${s.cpuPercent.toStringAsFixed(1)}%',
                      s.cpuPercent / 100,
                      monitorBlue,
                      history.map((v) => v.cpuPercent).toList(),
                      '系统整体负载',
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _metric(
                      context,
                      '内存占用',
                      Icons.memory_rounded,
                      '${s.memoryUsedPercent.toStringAsFixed(1)}%',
                      s.memoryUsedPercent / 100,
                      monitorCyan,
                      history.map((v) => v.memoryUsedPercent).toList(),
                      '${(s.usedMemoryMb / 1024).toStringAsFixed(1)} / ${(s.totalMemoryMb / 1024).toStringAsFixed(1)} GB',
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _metric(
                      context,
                      'CPU 温度',
                      Icons.thermostat_rounded,
                      s.cpuTempC == null
                          ? '—'
                          : '${s.cpuTempC!.toStringAsFixed(0)}°C',
                      s.cpuTempC == null
                          ? null
                          : (s.cpuTempC! / 110).clamp(0, 1),
                      const Color(0xFFECC08E),
                      history.map((v) => v.cpuTempC).toList(),
                      s.cpuTempC == null ? 'CPU 传感器暂不可用' : s.tempStatus,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              MonitorTile(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.memory_rounded, size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            '物理内存',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          '${s.memoryUsedPercent.toStringAsFixed(1)}%',
                          style: const TextStyle(
                            color: monitorCyan,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        minHeight: 14,
                        value: (s.memoryUsedPercent / 100).clamp(0, 1),
                        color: monitorCyan,
                        backgroundColor: const Color(0xFF365464),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 24,
                      runSpacing: 8,
                      children: [
                        Text(
                          '已用 ${(s.usedMemoryMb / 1024).toStringAsFixed(2)} GB',
                          style: const TextStyle(color: monitorCyan),
                        ),
                        Text(
                          '可用 ${((s.totalMemoryMb - s.usedMemoryMb).clamp(0, s.totalMemoryMb) / 1024).toStringAsFixed(2)} GB',
                          style: const TextStyle(color: monitorMuted),
                        ),
                        Text(
                          '总量 ${(s.totalMemoryMb / 1024).toStringAsFixed(2)} GB',
                          style: const TextStyle(color: monitorMuted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              MonitorTile(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.swap_vert_rounded, size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            '网络吞吐',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Tooltip(
                          message: '活动网卡的接口吞吐合计，可能包含虚拟网卡及局域网流量；不是外网测速。',
                          child: Text(
                            '${s.networkAdapters} 个活动接口',
                            style: const TextStyle(
                              color: monitorMuted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (narrow) ...[
                      _network(
                        '下行',
                        Icons.south_rounded,
                        s.downloadBytesPerSecond,
                        history.map((v) => v.downloadBytesPerSecond).toList(),
                        monitorCyan,
                      ),
                      const SizedBox(height: 18),
                      _network(
                        '上行',
                        Icons.north_rounded,
                        s.uploadBytesPerSecond,
                        history.map((v) => v.uploadBytesPerSecond).toList(),
                        monitorBlue,
                      ),
                    ] else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _network(
                              '下行',
                              Icons.south_rounded,
                              s.downloadBytesPerSecond,
                              history
                                  .map((v) => v.downloadBytesPerSecond)
                                  .toList(),
                              monitorCyan,
                            ),
                          ),
                          const SizedBox(width: 28),
                          Expanded(
                            child: _network(
                              '上行',
                              Icons.north_rounded,
                              s.uploadBytesPerSecond,
                              history
                                  .map((v) => v.uploadBytesPerSecond)
                                  .toList(),
                              monitorBlue,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 10),
                    Text(
                      s.downloadBytesPerSecond == null
                          ? (s.networkAdapters == 0
                                ? '当前没有可采样的活动接口，或系统接口暂不可用'
                                : '等待下一次采样计算速率')
                          : '活动接口吞吐 · 曲线独立缩放',
                      style: const TextStyle(color: monitorMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _network(
    String label,
    IconData icon,
    double? rate,
    List<double?> values,
    Color color,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(label),
          const Spacer(),
          Text(
            formatNetworkRate(rate),
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      TrendGraph(values: values, color: color, height: 72),
    ],
  );

  Widget _metric(
    BuildContext context,
    String label,
    IconData icon,
    String value,
    double? fraction,
    Color color,
    List<double?> values,
    String hint,
  ) => MonitorTile(
    onTap: () => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$label趋势'),
        content: SizedBox(
          width: 540,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(hint),
              const SizedBox(height: 20),
              TrendGraph(values: values, color: color, height: 140),
              const SizedBox(height: 16),
              if (values.whereType<double>().isNotEmpty)
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    Text(
                      '最低 ${values.whereType<double>().reduce((a, b) => a < b ? a : b).toStringAsFixed(1)}${label.contains('温度') ? '°C' : '%'}',
                    ),
                    Text(
                      '平均 ${(values.whereType<double>().reduce((a, b) => a + b) / values.whereType<double>().length).toStringAsFixed(1)}${label.contains('温度') ? '°C' : '%'}',
                    ),
                    Text(
                      '最高 ${values.whereType<double>().reduce((a, b) => a > b ? a : b).toStringAsFixed(1)}${label.contains('温度') ? '°C' : '%'}',
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              Text(
                '最近 ${values.length} 次成功采样；缺失值不绘制',
                style: const TextStyle(color: monitorMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(label)),
          ],
        ),
        const SizedBox(height: 20),
        Center(
          child: ResourceDial(
            fraction: fraction,
            icon: icon,
            color: color,
            size: 96,
            child: Center(
              child: Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 21,
                  color: color,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TrendGraph(values: values, color: color, height: 32),
        const SizedBox(height: 12),
        Text(
          hint,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: monitorMuted),
        ),
      ],
    ),
  );
}
