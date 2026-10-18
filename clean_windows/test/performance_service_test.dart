import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clean_windows/services/performance_service.dart';
import 'package:clean_windows/services/process_utils.dart';
import 'package:clean_windows/services/windows_runtime_metrics.dart';
import 'package:clean_windows/services/windows_process_sampler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const metrics = RuntimeMetrics(
    cpuPercent: 25,
    totalMemoryMb: 16000,
    usedMemoryMb: 8000,
  );
  PsResult response(List<Map<String, dynamic>> processes) => PsResult(
    exitCode: 0,
    stdout: jsonEncode({'Processes': processes}),
    stderr: '',
  );

  test('processes sort by memory with stable PID ties, including null CPU and more than eight rows', () async {
    final rows = List.generate(
      20,
      (i) => {
        'Name': 'process$i',
        'Id': 100 + i,
        'CPU': null,
        'MemMB': i * 100.0,
      },
    );
    rows.add({'Name': 'tie', 'Id': 5, 'MemMB': 1900});
    final service = PerformanceService(
      metricsReader: () => metrics,
      powerShellRunner: (script, _) async =>
          script == PerformanceService.snapshotScript
          ? response(rows)
          : PsResult(exitCode: 1, stdout: '', stderr: 'unsupported'),
    );
    final result = await service.sample();
    expect(result.topProcesses, hasLength(21));
    expect(result.topProcesses.first.pid, 5);
    expect(result.topProcesses[1].pid, 119);
    expect(result.topProcesses.last.memoryMb, 0);
    expect(result.cpuPercent, 25);
    expect(result.memoryUsedPercent, 50);
  });

  test('concurrent sampling shares one request and slow temperature never blocks the snapshot', () async {
    final processes = Completer<PsResult>();
    final temperature = Completer<PsResult>();
    var snapshotCalls = 0;
    var tempCalls = 0;
    final service = PerformanceService(
      metricsReader: () => metrics,
      powerShellRunner: (script, _) {
        if (script == PerformanceService.temperatureScript) {
          tempCalls++;
          return temperature.future;
        }
        snapshotCalls++;
        return processes.future;
      },
    );
    final first = service.sample();
    final second = service.sample();
    expect(identical(first, second), isTrue);
    expect(snapshotCalls, 1);
    processes.complete(response([]));
    expect((await first.timeout(const Duration(seconds: 1))).cpuTempC, isNull);
    temperature.complete(PsResult(exitCode: 0, stdout: '45.5', stderr: ''));
    await Future<void>.delayed(Duration.zero);
    expect((await service.sample()).cpuTempC, 45.5);
    expect(tempCalls, 1);
  });

  test('failed queries can retry and temperatures refresh only every thirty seconds', () async {
    var now = DateTime(2026, 10, 17);
    var failed = true;
    var tempCalls = 0;
    final service = PerformanceService(
      metricsReader: () => metrics,
      clock: () => now,
      powerShellRunner: (script, _) async {
        if (script == PerformanceService.temperatureScript) {
          tempCalls++;
          return PsResult(exitCode: 1, stdout: '', stderr: 'unsupported');
        }
        return failed
            ? PsResult(exitCode: 1, stdout: '', stderr: 'denied')
            : response([]);
      },
    );
    await expectLater(service.sample(), throwsStateError);
    failed = false;
    expect((await service.sample()).topProcesses, isEmpty);
    expect(tempCalls, 1);
    now = now.add(const Duration(seconds: 31));
    await service.sample();
    expect(tempCalls, 2);
  });

  test(
    'system and own-process termination is rejected without sending commands',
    () async {
      var calls = 0;
      final service = PerformanceService(
        metricsReader: () => metrics,
        powerShellRunner: (_, _) async {
          calls++;
          return PsResult(exitCode: 0, stdout: '', stderr: '');
        },
      );
      for (final id in [0, 4, pid]) {
        expect(await service.killProcess(id), isFalse);
      }
      expect(calls, 0);
    },
  );

  test(
    'native Windows CPU and memory sampling returns valid metrics',
    () async {
      final reader = WindowsRuntimeMetrics();
      final first = reader.read();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final second = reader.read();
      expect(first.totalMemoryMb, greaterThan(0));
      expect(second.usedMemoryMb, inInclusiveRange(0, second.totalMemoryMb));
      expect(second.cpuPercent, inInclusiveRange(0, 100));
      for (var i = 0; i < 50; i++) {
        reader.read();
      }
    },
    skip: !Platform.isWindows,
  );
  test(
    'owned sampling worker delivers consecutive snapshots and stops cleanly',
    () async {
      final worker = WindowsProcessSampler(r''''{"Processes":[]}' ''');
      try {
        expect((await worker.sample()).success, isTrue);
        expect((await worker.sample()).success, isTrue);
        final pending = worker.sample();
        await Future<void>.delayed(Duration.zero);
        await worker.close();
        expect((await pending).success, isFalse);
        await expectLater(worker.sample(), throwsStateError);
      } finally {
        await worker.close();
      }
    },
    skip: !Platform.isWindows,
  );
}
