import 'dart:async';
import 'dart:convert';

import 'package:clean_windows/pages/health_check_page.dart';
import 'package:clean_windows/services/health_check_service.dart';
import 'package:clean_windows/services/process_utils.dart';
import 'package:clean_windows/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PsResult data(int phase) => PsResult(
  exitCode: 0,
  stderr: '',
  stdout: jsonEncode([
    switch (phase % 5) {
      0 => {
        'id': 'cpu',
        'label': '处理器',
        'value': 'Demo CPU / 8 核 16 线程',
        'status': 'info',
      },
      1 => {
        'id': 'proxy',
        'label': '系统代理',
        'value': 'https://demo:secret@proxy.example:8080/?key=hidden',
        'status': 'info',
      },
      2 => {
        'id': 'drive_C',
        'label': 'C: 可用空间',
        'value': '8 / 100 GB',
        'status': 'attention',
      },
      3 => {
        'id': 'startup',
        'label': '可管理启动项',
        'value': '4 项开启 / 2 项关闭',
        'status': 'info',
      },
      _ => {
        'id': 'browser',
        'label': '默认浏览器',
        'value': 'User selected browser',
        'status': 'info',
      },
    },
  ]),
);

class _Service extends HealthCheckService {
  _Service() : super(runner: (script, timeout) async => data(0));
  int flushes = 0, probes = 0;
  @override
  Future<bool> flushDns() async {
    flushes++;
    return true;
  }

  @override
  Future<HealthSection> probeConnectivity() async {
    probes++;
    return const HealthSection('connectivity', '外网探测', [
      HealthEntry('probe_dns', '外网 DNS 解析', '目标已响应', HealthStatus.normal),
    ]);
  }
}

void main() {
  test('partial results stream; unavailable never becomes healthy; no automatic probes', () async {
    var calls = 0;
    final service = HealthCheckService(
      runner: (script, timeout) async {
        calls++;
        if (calls == 2) {
          return PsResult(exitCode: 1, stdout: '', stderr: 'Access denied');
        }
        if (calls == 3) {
          return PsResult(exitCode: 0, stdout: 'not json', stderr: '');
        }
        return data(calls - 1);
      },
    );
    final c = HealthCheckController(service: service);
    final observed = <int>[];
    c.addListener(() => observed.add(c.sections.length));
    await c.scan();
    expect(calls, 5);
    expect(observed, containsAllInOrder([0, 1, 2, 3, 4, 5]));
    expect(c.unavailableCount, 2);
    expect(c.completedPhases, 5);
    expect(c.completedAt, isNotNull);
    expect(c.scanning, isFalse);
    expect(c.sections.map((s) => s.id), [
      'hardware',
      'network',
      'storage',
      'applications',
      'preferences',
    ]);
    c.dispose();
  });

  test('rescan retains old results, cancel discards pending output, next scan works', () async {
    var calls = 0;
    Completer<PsResult>? pending;
    final service = HealthCheckService(
      runner: (script, timeout) async {
        final n = calls++;
        return pending == null ? data(n) : pending.future;
      },
    );
    final c = HealthCheckController(service: service);
    await c.scan();
    final completed = c.completedAt;
    pending = Completer();
    final rescan = c.scan();
    await Future<void>.delayed(Duration.zero);
    expect(c.sections.length, 5);
    expect(c.isFresh('hardware'), isFalse);
    expect(c.completedAt, completed);
    c.cancel();
    pending.complete(data(0));
    await rescan;
    expect(c.cancelled, isTrue);
    expect(c.completedPhases, 0);
    expect(c.sections.length, 5);
    expect(c.report(), contains('本次体检已取消'));
    expect(c.report(), contains('上次结果'));
    expect(calls, 6);
    pending = null;
    await c.scan();
    expect(c.cancelled, isFalse);
    expect(c.completedPhases, 5);
    expect(calls, 11);
    c.dispose();
  });

  test('reports mask proxy credentials and PAC query tokens; configuration is informational', () async {
    var i = 0;
    final c = HealthCheckController(
      service: HealthCheckService(runner: (script, timeout) async => data(i++)),
    );
    await c.scan();
    final report = c.report();
    expect(report, isNot(contains('secret')));
    expect(report, isNot(contains('hidden')));
    expect(report, contains('***@proxy.example'));
    expect(c.sections[1].entries.single.status, HealthStatus.info);
    expect(c.attentionCount, 1);
    c.dispose();
  });

  test('invalid and duplicate result identities fail closed', () {
    for (final text in [
      '{}',
      '[]',
      '[{"id":"a","label":"b","value":"c","status":"healthy"}]',
      '[{"id":"a","label":"b","value":"c","status":"info"},{"id":"a","label":"b","value":"c","status":"info"}]',
    ]) {
      expect(
        () => HealthCheckService.parseEntries(text),
        throwsFormatException,
      );
    }
  });

  testWidgets(
    'entering page does not scan; rescan data stays collapsed and narrow layout fits',
    (tester) async {
      tester.view.physicalSize = const Size(560, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var calls = 0;
      final c = HealthCheckController(
        service: HealthCheckService(
          runner: (script, timeout) async => data(calls++),
        ),
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: HealthCheckPage(
              controller: c,
              onNavigate: (_) {},
              onScanTraces: () async => true,
            ),
          ),
        ),
      );
      expect(calls, 0);
      expect(find.text('了解电脑的当前状态'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('health-scan')));
      await tester.pumpAndSettle();
      expect(calls, 5);
      expect(find.text('硬件概况'), findsOneWidget);
      expect(find.textContaining('Demo CPU'), findsNothing);
      await tester.tap(find.text('硬件概况'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Demo CPU'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'network mutations and outbound tests require explicit confirmation',
    (tester) async {
      final service = _Service();
      final c = HealthCheckController(service: service);
      await c.scan();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: HealthCheckPage(
              controller: c,
              onNavigate: (_) {},
              onScanTraces: () async => true,
            ),
          ),
        ),
      );
      await tester.tap(find.text('网络诊断'));
      await tester.pumpAndSettle();
      final dns = find.text('刷新 DNS');
      await tester.ensureVisible(dns);
      await tester.tap(dns);
      await tester.pumpAndSettle();
      expect(find.text('刷新 DNS 缓存？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(service.flushes, 0);
      await tester.ensureVisible(find.text('外网探测'));
      await tester.tap(find.text('外网探测'));
      await tester.pumpAndSettle();
      expect(service.probes, 0);
      await tester.tap(find.text('检测'));
      await tester.pumpAndSettle();
      expect(service.probes, 1);
      expect(c.sections.any((s) => s.id == 'connectivity'), isTrue);
      expect(c.completedPhases, 5);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'scan survives IndexedStack navigation and returns existing results',
    (tester) async {
      final pending = Completer<PsResult>();
      var calls = 0;
      final c = HealthCheckController(
        service: HealthCheckService(
          runner: (script, timeout) async {
            final i = calls++;
            return i == 0 ? pending.future : data(i);
          },
        ),
      );
      addTearDown(c.dispose);
      var index = 0;
      late StateSetter change;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                change = setState;
                return IndexedStack(
                  index: index,
                  children: [
                    HealthCheckPage(
                      controller: c,
                      onNavigate: (_) {},
                      onScanTraces: () async => true,
                    ),
                    const Text('Other page'),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('health-scan')));
      await tester.pump();
      change(() => index = 1);
      await tester.pump();
      pending.complete(data(0));
      await tester.pumpAndSettle();
      expect(calls, 5);
      change(() => index = 0);
      await tester.pumpAndSettle();
      expect(find.text('硬件概况'), findsOneWidget);
      expect(calls, 5);
      expect(tester.takeException(), isNull);
    },
  );
}
