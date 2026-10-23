import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/health_check_service.dart';
import '../widgets/monitor_surface.dart';

class HardwareDashboardPage extends StatefulWidget {
  const HardwareDashboardPage({super.key, required this.controller});
  final HealthCheckController controller;
  @override
  State<HardwareDashboardPage> createState() => _HardwareDashboardPageState();
}

class _HardwareDashboardPageState extends State<HardwareDashboardPage> {
  static const icons = {
    'cpu': Icons.developer_board_rounded,
    'ram': Icons.memory_rounded,
    'gpu': Icons.videogame_asset_outlined,
    'disk': Icons.storage_rounded,
    'board': Icons.dashboard_outlined,
    'nic': Icons.router_outlined,
    'audio': Icons.speaker_outlined,
    'display': Icons.monitor_rounded,
    'os': Icons.window_rounded,
  };
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final entries = c.sections
          .where((v) => v.id == 'hardware')
          .expand((v) => v.entries)
          .toList();
      final ready = entries
          .where((v) => v.status != HealthStatus.unavailable)
          .length;
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: MonitorSurface(
          key: const ValueKey('hardware-monitor-surface'),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900
                  ? 3
                  : (constraints.maxWidth >= 500 ? 2 : 1);
              final width =
                  (constraints.maxWidth - 40 - (columns - 1) * 14) / columns;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 16,
                      runSpacing: 12,
                      children: [
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.developer_board_outlined),
                            SizedBox(width: 10),
                            Text(
                              '硬件信息',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: '复制硬件信息',
                              onPressed: entries.isEmpty
                                  ? null
                                  : () async {
                                      await Clipboard.setData(
                                        ClipboardData(
                                          text: entries
                                              .map(
                                                (v) => '${v.label}：${v.value}',
                                              )
                                              .join('\n'),
                                        ),
                                      );
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              const SnackBar(
                                                content: Text('硬件信息已复制'),
                                              ),
                                            );
                                      }
                                    },
                              icon: const Icon(Icons.copy_all_rounded),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.tonalIcon(
                              onPressed: c.scanning || c.probing
                                  ? null
                                  : () => c.scan(phaseIds: {'hardware'}),
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text(c.scanning ? '读取中' : '刷新'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      key: const PageStorageKey('hardware-dashboard'),
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      children: [
                        MonitorTile(
                          child: LayoutBuilder(
                            builder: (context, size) {
                              final summary = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '设备拓扑',
                                    style: TextStyle(
                                      color: monitorMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    entries.isEmpty
                                        ? '等待设备信息'
                                        : '$ready / ${entries.length} 项已读取',
                                    style: const TextStyle(
                                      fontSize: 25,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    c.scanning
                                        ? '正在读取本机硬件'
                                        : '本机配置快照 · 点击设备查看详情',
                                    style: const TextStyle(
                                      color: monitorMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              );
                              final map = SizedBox(
                                height: 146,
                                child: CustomPaint(
                                  painter: _BoardMap(),
                                  child: Center(
                                    child: Container(
                                      width: 78,
                                      height: 78,
                                      decoration: BoxDecoration(
                                        color: monitorInk,
                                        border: Border.all(
                                          color: monitorCyan,
                                          width: 2,
                                        ),
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      child: const Icon(
                                        Icons.developer_board_rounded,
                                        size: 42,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                              if (size.maxWidth < 540) {
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [summary, map],
                                );
                              }
                              return Row(
                                children: [
                                  Expanded(child: summary),
                                  Expanded(child: map),
                                ],
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (entries.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(32),
                            child: Center(
                              child: c.scanning
                                  ? const CircularProgressIndicator()
                                  : const Text(
                                      '暂未读取到硬件，点击刷新重试',
                                      style: TextStyle(color: monitorMuted),
                                    ),
                            ),
                          )
                        else
                          Wrap(
                            spacing: 14,
                            runSpacing: 14,
                            children: [
                              for (final entry in entries)
                                SizedBox(
                                  width: width,
                                  height: 172,
                                  child: MonitorTile(
                                    key: ValueKey('hardware-tile-${entry.id}'),
                                    onTap: () => showDialog<void>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: Text(entry.label),
                                        content: SingleChildScrollView(
                                          child: SelectableText(entry.value),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Clipboard.setData(
                                              ClipboardData(text: entry.value),
                                            ),
                                            child: const Text('复制'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text('关闭'),
                                          ),
                                        ],
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              icons[entry.id] ??
                                                  Icons.devices_rounded,
                                              size: 24,
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                entry.label,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            Icon(
                                              entry.status ==
                                                      HealthStatus.unavailable
                                                  ? Icons.help_outline_rounded
                                                  : Icons
                                                        .check_circle_outline_rounded,
                                              size: 16,
                                              color:
                                                  entry.status ==
                                                      HealthStatus.unavailable
                                                  ? const Color(0xFFECC08E)
                                                  : monitorCyan,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        SizedBox(
                                          height: 68,
                                          child: Align(
                                            alignment: Alignment.topLeft,
                                            child: Text(
                                              entry.value,
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: entry.id == 'ram'
                                                    ? 24
                                                    : 14,
                                                fontWeight: FontWeight.w600,
                                                height: 1.6,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Container(
                                              width: 5,
                                              height: 5,
                                              decoration: const BoxDecoration(
                                                color: monitorCyan,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                entry.status ==
                                                        HealthStatus.unavailable
                                                    ? '系统接口未返回数据'
                                                    : '本机硬件配置',
                                                style: const TextStyle(
                                                  color: monitorMuted,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                            Icon(
                                              Icons.open_in_full_rounded,
                                              size: 18,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}

class _BoardMap extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = monitorCyan.withValues(alpha: .4)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final offset in [
      Offset(24, 28),
      Offset(size.width - 24, 28),
      Offset(24, size.height - 28),
      Offset(size.width - 24, size.height - 28),
    ]) {
      final path = Path()
        ..moveTo(size.width / 2, size.height / 2)
        ..lineTo(offset.dx, size.height / 2)
        ..lineTo(offset.dx, offset.dy);
      canvas.drawPath(path, p);
      canvas.drawCircle(offset, 6, p);
    }
  }

  @override
  bool shouldRepaint(covariant _BoardMap oldDelegate) => false;
}
