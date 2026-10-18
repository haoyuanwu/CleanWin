import 'dart:async';

import 'package:clean_windows/pages/performance_page.dart';
import 'package:clean_windows/services/performance_service.dart';
import 'package:clean_windows/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

RuntimeSnapshot snapshot() => RuntimeSnapshot(
  cpuPercent: 20,
  memoryUsedPercent: 50,
  cpuTempC: null,
  collectedAt: DateTime(2026, 10, 17, 10, 20, 30),
  totalMemoryMb: 16000,
  usedMemoryMb: 8000,
  topProcesses: const [
    ProcUsage(name: 'Big process', pid: 2001, cpu: 0, memoryMb: 2048),
    ProcUsage(name: 'Medium process', pid: 2002, cpu: 0, memoryMb: 512),
    ProcUsage(name: 'Small process', pid: 2003, cpu: 0, memoryMb: 64),
  ],
);

class _Service extends PerformanceService {
  int calls = 0;
  int? killedPid;
  bool fail = false;
  Completer<RuntimeSnapshot>? pending;
  @override
  Future<RuntimeSnapshot> sample() async {
    calls++;
    if (fail) throw StateError('failed');
    if (pending != null) return pending!.future;
    return snapshot();
  }

  @override
  Future<bool> killProcess(int pid) async {
    killedPid = pid;
    return true;
  }
}

void main() {
  Widget app(_Service service, {bool active = true}) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: PerformancePage(service: service, active: active),
    ),
  );

  testWidgets('manual pause stops polling and resumes with fresh data', (
    tester,
  ) async {
    final service = _Service();
    await tester.pumpWidget(app(service));
    await tester.pump();
    await tester.tap(find.text('暂停刷新'));
    await tester.pump();
    final before = service.calls;
    await tester.pump(const Duration(seconds: 3));
    expect(service.calls, before);
    expect(find.text('Big process'), findsOneWidget);
    await tester.tap(find.text('继续刷新'));
    await tester.pump();
    expect(service.calls, before + 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('memory rows are readable, searchable, and update every second', (
    tester,
  ) async {
    final service = _Service();
    await tester.pumpWidget(app(service));
    await tester.pump();
    expect(
      tester.getTopLeft(find.text('Big process')).dy,
      lessThan(tester.getTopLeft(find.text('Medium process')).dy),
    );
    expect(find.text('2.00 GB'), findsOneWidget);
    expect(find.textContaining('累计'), findsNothing);
    final before = service.calls;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(service.calls, before + 1);
    await tester.ensureVisible(find.byTooltip('搜索'));
    await tester.tap(find.byTooltip('搜索'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(
      find.byKey(const ValueKey('process-search')),
      '2002',
    );
    await tester.pump();
    expect(find.text('Medium process'), findsOneWidget);
    expect(find.text('Big process'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('hidden module does not poll and resuming fetches immediately', (
    tester,
  ) async {
    final service = _Service();
    await tester.pumpWidget(app(service, active: false));
    await tester.pump(const Duration(seconds: 3));
    expect(service.calls, 0);
    await tester.pumpWidget(app(service));
    await tester.pump();
    expect(service.calls, 1);
    await tester.pumpWidget(app(service, active: false));
    await tester.pump(const Duration(seconds: 3));
    expect(service.calls, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'slow requests never overlap and failed refresh keeps last data',
    (tester) async {
      final service = _Service()..pending = Completer<RuntimeSnapshot>();
      await tester.pumpWidget(app(service));
      await tester.pump(const Duration(seconds: 3));
      expect(service.calls, 1);
      service.pending!.complete(snapshot());
      await tester.pump();
      service.pending = null;
      service.fail = true;
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('Big process'), findsOneWidget);
      expect(find.textContaining('上次成功读取的数据'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('ending a row keeps the confirmed PID while polling is paused', (
    tester,
  ) async {
    final service = _Service();
    await tester.pumpWidget(app(service));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('process-2001')),
        matching: find.text('结束'),
      ),
    );
    await tester.pumpAndSettle();
    final before = service.calls;
    await tester.pump(const Duration(seconds: 2));
    expect(service.calls, before);
    expect(find.textContaining('(PID 2001)'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, '结束进程'));
    await tester.pumpAndSettle();
    expect(service.killedPid, 2001);
    await tester.pumpWidget(const SizedBox());
  });
}
