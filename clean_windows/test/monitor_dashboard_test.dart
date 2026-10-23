import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:clean_windows/pages/performance_page.dart';
import 'package:clean_windows/pages/hardware_dashboard_page.dart';
import 'package:clean_windows/services/performance_service.dart';
import 'package:clean_windows/services/health_check_service.dart';
import 'package:clean_windows/services/process_utils.dart';
import 'package:clean_windows/theme/app_theme.dart';
import 'package:clean_windows/widgets/runtime_dashboard.dart';
import 'package:clean_windows/widgets/trend_graph.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class Samples extends PerformanceService {
  int calls = 0;
  @override
  Future<RuntimeSnapshot> sample() async {
    calls++;
    return RuntimeSnapshot(
      cpuPercent: 20 + calls % 12,
      memoryUsedPercent: 62.5,
      cpuTempC: null,
      totalMemoryMb: 32768,
      usedMemoryMb: 20480,
      topProcesses: const [
        ProcUsage(name: 'Example', pid: 2001, cpu: 0, memoryMb: 2048),
      ],
      collectedAt: DateTime(2026, 10, 22, 23, 20, calls),
      downloadBytesPerSecond: calls == 1 ? null : 1024 * 1024 * 2.35,
      uploadBytesPerSecond: calls == 1 ? null : 1024 * 168.4,
      networkAdapters: 1,
    );
  }
}

void main() {
  const render = bool.fromEnvironment('UI_PREVIEWS');
  setUpAll(() async {
    if (!render) return;
    await (FontLoader('Segoe UI')..addFont(
          Future.value(
            ByteData.sublistView(
              File(r'C:\Windows\Fonts\msyh.ttc').readAsBytesSync(),
            ),
          ),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  test('network rate units preserve missing and measured zero', () {
    expect(formatNetworkRate(null), '—');
    expect(formatNetworkRate(0), '0 B/s');
    expect(formatNetworkRate(2048), '2.0 KB/s');
    expect(formatNetworkRate(2097152), '2.00 MB/s');
  });
  for (final width in [1000.0, 560.0]) {
    testWidgets('runtime dashboard and isolated processes fit $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final samples = Samples();
      final boundary = GlobalKey();
      Widget page(bool processes, bool active) => MaterialApp(
        theme: AppTheme.light(),
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: RepaintBoundary(
            key: boundary,
            child: PerformancePage(
              key: ValueKey(processes),
              service: samples,
              processesOnly: processes,
              active: active,
            ),
          ),
        ),
      );
      await tester.pumpWidget(page(false, true));
      await tester.pump();
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester.getTopLeft(
          find.byKey(const ValueKey('runtime-monitor-surface')),
        ),
        const Offset(20, 14),
      );
      expect(find.text('CPU 占用'), findsOneWidget);
      expect(find.text('内存占用'), findsOneWidget);
      expect(find.byKey(const ValueKey('process-2001')), findsNothing);
      Future<void> capture(String name) async {
        expect(tester.takeException(), isNull);
        if (!render) return;
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '.dart_tool/monitor-previews/$name-${width.toInt()}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('runtime');
      await tester.scrollUntilVisible(
        find.text('网络吞吐'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(RuntimeDashboard),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('2.35 MB/s'), findsOneWidget);
      expect(find.text('168.4 KB/s'), findsOneWidget);
      expect(find.byType(TrendGraph), findsWidgets);
      await capture('runtime-network');
      await tester.pumpWidget(page(false, false));
      await tester.pump();
      final before = samples.calls;
      await tester.pump(const Duration(seconds: 3));
      expect(samples.calls, before);
      await tester.pumpWidget(page(true, true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('process-2001')), findsOneWidget);
      expect(find.text('网络吞吐'), findsNothing);
      await capture('processes');
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets(
      'hardware configuration dashboard uses snapshots and opens details $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var calls = 0;
        Completer<PsResult>? gate;
        final rows = [
          {
            'id': 'cpu',
            'label': '处理器',
            'value': 'AMD Ryzen 9 7950X / 16 核 32 线程',
            'status': 'info',
          },
          {'id': 'ram', 'label': '物理内存', 'value': '32.0 GB', 'status': 'info'},
          {
            'id': 'gpu',
            'label': '显卡',
            'value': 'NVIDIA GeForce RTX 4070 / 驱动 32.0.15.6094',
            'status': 'info',
          },
          {
            'id': 'disk',
            'label': '物理磁盘',
            'value': 'Samsung SSD 990 PRO / 1,863 GB',
            'status': 'info',
          },
          {
            'id': 'board',
            'label': '主板',
            'value': 'ASUSTeK COMPUTER INC. ROG STRIX X670E',
            'status': 'info',
          },
          {
            'id': 'nic',
            'label': '网卡',
            'value': 'Intel Ethernet Controller / Wi-Fi 6E',
            'status': 'info',
          },
          {
            'id': 'audio',
            'label': '音频设备',
            'value': 'Realtek High Definition Audio',
            'status': 'info',
          },
          {
            'id': 'display',
            'label': '显示器',
            'value': '无法读取',
            'status': 'unavailable',
          },
          {
            'id': 'os',
            'label': '操作系统',
            'value': 'Microsoft Windows 11 Pro / 10.0.26200 / 64 位',
            'status': 'info',
          },
        ];
        final controller = HealthCheckController(
          service: HealthCheckService(
            runner: (script, _) async {
              calls++;
              return gate == null
                  ? PsResult(exitCode: 0, stdout: jsonEncode(rows), stderr: '')
                  : gate.future;
            },
          ),
        );
        addTearDown(controller.dispose);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            home: Scaffold(
              body: RepaintBoundary(
                key: boundary,
                child: HardwareDashboardPage(controller: controller),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(calls, 0);
        await controller.scan(phaseIds: {'hardware'});
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(
            find.byKey(const ValueKey('hardware-monitor-surface')),
          ),
          const Offset(20, 14),
        );
        final tileSizes = [
          for (final row in rows)
            tester.getSize(find.byKey(ValueKey('hardware-tile-${row['id']}'))),
        ];
        expect(tileSizes.map((size) => size.height).toSet(), {172.0});
        expect(tileSizes.map((size) => size.width).toSet().length, 1);
        expect(find.text('8 / 9 项已读取'), findsOneWidget);
        if (render) {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              '.dart_tool/monitor-previews/hardware-${width.toInt()}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(find.byKey(const ValueKey('hardware-tile-cpu')));
        await tester.pumpAndSettle();
        expect(find.byType(SelectableText), findsOneWidget);
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
        gate = Completer<PsResult>();
        await tester.tap(find.text('刷新'));
        await tester.pump();
        expect(find.text('读取中'), findsOneWidget);
        expect(find.text('8 / 9 项已读取'), findsOneWidget);
        gate.complete(PsResult(exitCode: 1, stdout: '', stderr: 'unavailable'));
        await tester.pumpAndSettle();
        expect(find.text('0 / 1 项已读取'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
