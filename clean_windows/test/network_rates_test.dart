import 'dart:convert';

import 'package:clean_windows/services/network_rates.dart';
import 'package:clean_windows/services/performance_service.dart';
import 'package:clean_windows/services/process_utils.dart';
import 'package:clean_windows/services/windows_runtime_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> counter(String id, int rx, int tx) => {
    'Id': id,
    'Rx': rx,
    'Tx': tx,
  };
  test('network uses elapsed time, valid zero and per-adapter baselines', () {
    final rates = NetworkRates();
    expect(rates.read([counter('a', 100, 50)], 10000000).down, isNull);
    final second = rates.read([counter('a', 2148, 1074)], 30000000);
    expect(second.down, 1024);
    expect(second.up, 512);
    final zero = rates.read([counter('a', 2148, 1074)], 40000000);
    expect(zero.down, 0);
    expect(zero.up, 0);
    final joined = rates.read([
      counter('a', 2248, 1174),
      counter('b', 9999999, 9999999),
    ], 50000000);
    expect(joined.down, 100);
    expect(joined.adapters, 2);
    final removed = rates.read([counter('b', 10000099, 10000199)], 60000000);
    expect(removed.down, 100);
    expect(removed.up, 200);
  });
  test(
    'failures, gaps, disconnects, resets and backwards time do not spike',
    () {
      final rates = NetworkRates();
      expect(rates.read([counter('a', 1000, 2000)], 10000000).down, isNull);
      expect(rates.read([counter('a', 0, 0)], 20000000).down, isNull);
      expect(rates.read([counter('a', 100, 100)], 10000000).down, isNull);
      expect(rates.read(null, 20000000).down, isNull);
      expect(
        rates.read([counter('a', 10000000, 10000000)], 30000000).down,
        isNull,
      );
      expect(rates.read([], 40000000).adapters, 0);
      expect(
        rates.read([counter('a', 20000000, 20000000)], 50000000).down,
        isNull,
      );
      expect(
        rates.read([counter('a', 40000000, 40000000)], 200000000).down,
        isNull,
      );
      rates.reset();
      expect(
        rates.read([counter('a', 60000000, 60000000)], 210000000).down,
        isNull,
      );
    },
  );
  test('resource-only sampling skips process enumeration and carries network rates', () async {
    var count = 0;
    final scripts = <String>[];
    final service = PerformanceService(
      includeProcesses: false,
      metricsReader: () => const RuntimeMetrics(
        cpuPercent: 20,
        totalMemoryMb: 16000,
        usedMemoryMb: 8000,
      ),
      powerShellRunner: (script, _) async {
        if (script == PerformanceService.temperatureScript) {
          return PsResult(exitCode: 0, stdout: '[]', stderr: '');
        }
        scripts.add(script);
        count++;
        return PsResult(
          exitCode: 0,
          stdout: jsonEncode({
            'Processes': [],
            'Network': [counter('a', count * 1000, count * 500)],
            'NetworkTicks': count * 10000000,
          }),
          stderr: '',
        );
      },
    );
    addTearDown(service.dispose);
    expect((await service.sample()).downloadBytesPerSecond, isNull);
    final next = await service.sample();
    expect(next.downloadBytesPerSecond, 1000);
    expect(next.uploadBytesPerSecond, 500);
    expect(next.networkAdapters, 1);
    expect(scripts.every((v) => !v.contains('Get-Process')), isTrue);
    await service.pause();
    expect((await service.sample()).downloadBytesPerSecond, isNull);
  });
}
