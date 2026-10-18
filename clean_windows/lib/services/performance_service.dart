import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'process_utils.dart';
import 'windows_runtime_metrics.dart';
import 'windows_process_sampler.dart';

class RuntimeSnapshot {
  const RuntimeSnapshot({
    required this.cpuPercent,
    required this.memoryUsedPercent,
    required this.cpuTempC,
    required this.topProcesses,
    required this.collectedAt,
    this.totalMemoryMb = 0,
    this.usedMemoryMb = 0,
  });
  final double cpuPercent;
  final double memoryUsedPercent;
  final double? cpuTempC;
  final List<ProcUsage> topProcesses;
  final DateTime collectedAt;
  final double totalMemoryMb;
  final double usedMemoryMb;
  bool get cpuHigh => cpuPercent >= 85;
  bool get memHigh => memoryUsedPercent >= 90;
  bool get tempHigh => cpuTempC != null && cpuTempC! >= 85;
  bool get tempWarn => cpuTempC != null && cpuTempC! >= 75;
  String get tempStatus => cpuTempC == null
      ? '传感器暂不可用'
      : tempHigh
      ? '温度偏高'
      : tempWarn
      ? '建议关注散热'
      : 'ACPI 温度参考值';
}

class ProcUsage {
  const ProcUsage({
    required this.name,
    required this.pid,
    required this.cpu,
    required this.memoryMb,
  });
  final String name;
  final int pid;

  /// Cumulative CPU seconds, not an instantaneous utilization percentage.
  final double cpu;
  final double memoryMb;
  static const protectedNames = {
    'system',
    'registry',
    'smss',
    'csrss',
    'wininit',
    'winlogon',
    'lsass',
    'services',
    'svchost',
    'dwm',
    'sihost',
    'fontdrvhost',
    'secure system',
    'memory compression',
  };
  bool get canTerminate =>
      pid > 4 &&
      pid != io.pid &&
      !protectedNames.contains(
        name.toLowerCase().replaceFirst(RegExp(r'\.exe$'), ''),
      );
}

class PerformanceService {
  PerformanceService({
    PowerShellRunner? powerShellRunner,
    DateTime Function()? clock,
    this.metricsReader,
  }) : _run = powerShellRunner ?? runPowerShell,
       _clock = clock ?? DateTime.now,

       _useWorker = powerShellRunner == null;
  final PowerShellRunner _run;
  final bool _useWorker;
  WindowsProcessSampler? _worker;
  final RuntimeMetrics Function()? metricsReader;
  late final _nativeMetrics = WindowsRuntimeMetrics();
  RuntimeMetrics _metrics() => metricsReader?.call() ?? _nativeMetrics.read();
  final DateTime Function() _clock;
  Future<RuntimeSnapshot>? _pending;
  bool _readingTemperature = false;
  DateTime? _temperatureAttempt;
  double? _temperature;

  // One process per snapshot; no deliberate one-second counter waits.
  // WorkingSet64 is physical working-set memory, including shared pages.
  static const snapshotScript = r'''
$ErrorActionPreference = 'Stop'

$processes = @(Get-Process -ErrorAction Stop | ForEach-Object {
  $process = $_
  try {
    $memory = $process.WorkingSet64
    [PSCustomObject]@{ Name=$process.ProcessName; Id=$process.Id;
      MemMB=([double]$memory / 1MB) }
  } catch { } # Processes can exit while their properties are being read.
} | Sort-Object MemMB -Descending)
[PSCustomObject]@{
  Processes = @($processes)
} | ConvertTo-Json -Compress -Depth 4
''';

  static const temperatureScript = r'''
$ErrorActionPreference = 'Stop'
$t = Get-CimInstance -Namespace root/WMI -ClassName MSAcpi_ThermalZoneTemperature -OperationTimeoutSec 3
if ($t) { [math]::Round(($t | Select-Object -First 1).CurrentTemperature / 10.0 - 273.15, 1) }
''';

  /// Concurrent callers share one query instead of spawning overlapping samples.
  Future<RuntimeSnapshot> sample() =>
      _pending ??= _collect().whenComplete(() => _pending = null);

  Future<RuntimeSnapshot> _collect() async {
    _metrics(); // Seed CPU time deltas before awaiting the process snapshot.
    _scheduleTemperature();
    final result = await _readProcesses();
    if (!result.success && _useWorker) await pause();
    if (!result.success) throw StateError('读取运行状态失败，请稍后重试');
    final raw = jsonDecode(result.stdout);
    if (raw is! Map<String, dynamic>) throw const FormatException('运行状态结果无效');
    final metrics = _metrics();
    final total = metrics.totalMemoryMb;
    if (total <= 0) throw const FormatException('内存总量无效');
    final processes = <ProcUsage>[];
    final rows = raw['Processes'];
    if (rows is! List) throw const FormatException('进程列表无效');
    final seen = <int>{};
    for (final row in rows.whereType<Map>()) {
      final pid = row['Id'];
      final memory = row['MemMB'];
      if (pid is! num || memory is! num || !memory.isFinite || memory < 0) {
        continue;
      }
      if (!seen.add(pid.toInt())) continue;
      processes.add(
        ProcUsage(
          name: row['Name']?.toString() ?? '未知进程',
          pid: pid.toInt(),
          memoryMb: memory.toDouble(),
          cpu: 0,
        ),
      );
    }
    processes.sort((a, b) {
      final memoryOrder = b.memoryMb.compareTo(a.memoryMb);
      return memoryOrder != 0 ? memoryOrder : a.pid.compareTo(b.pid);
    });
    return RuntimeSnapshot(
      cpuPercent: metrics.cpuPercent ?? 0,
      memoryUsedPercent: metrics.memoryPercent.clamp(0, 100),
      totalMemoryMb: total,
      usedMemoryMb: metrics.usedMemoryMb.clamp(0, total),
      cpuTempC: _temperature,
      topProcesses: List.unmodifiable(processes),
      collectedAt: _clock(),
    );
  }

  void _scheduleTemperature() {
    final now = _clock();
    if (_readingTemperature ||
        (_temperatureAttempt != null &&
            now.difference(_temperatureAttempt!) <
                const Duration(seconds: 30))) {
      return;
    }
    _temperatureAttempt = now;
    _readingTemperature = true;
    unawaited(_readTemperature());
  }

  Future<void> _readTemperature() async {
    try {
      final result = await _run(temperatureScript, const Duration(seconds: 5));
      final value = result.success
          ? double.tryParse(result.stdout.trim().replaceAll(',', '.'))
          : null;
      _temperature =
          value != null && value.isFinite && value >= -20 && value <= 150
          ? value
          : null;
    } on Exception {
      _temperature = null;
    } finally {
      _readingTemperature = false;
    }
  }

  Future<bool> killProcess(int pid) async {
    if (pid <= 4 || pid == io.pid) return false;
    final result = await _run(
      '\$ErrorActionPreference = \'Stop\'; \$p=Get-Process -Id $pid -ErrorAction Stop; '
      "if (\$p.ProcessName.ToLowerInvariant() -in @(${ProcUsage.protectedNames.map((name) => "'$name'").join(',')})) { throw '系统进程受保护' }; \$p | Stop-Process -Force",
      const Duration(seconds: 5),
    );
    return result.success;
  }

  Future<void> pause() async {
    final worker = _worker;
    _worker = null;
    await worker?.close();
  }

  Future<void> dispose() => pause();

  Future<PsResult> _readProcesses() async {
    if (!_useWorker) return _run(snapshotScript, const Duration(seconds: 6));
    try {
      return await (_worker ??= WindowsProcessSampler(snapshotScript)).sample();
    } catch (_) {
      await pause();
      rethrow;
    }
  }

  /// Trim only this application's working set; never terminate other programs.
  Future<bool> trimMemory() async {
    final result = await _run('''
\$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class CleanWinMemory {
  [DllImport("psapi.dll", SetLastError=true)]
  public static extern bool EmptyWorkingSet(IntPtr process);
}
"@
\$target = Get-Process -Id ${io.pid}
if (-not [CleanWinMemory]::EmptyWorkingSet(\$target.Handle)) { throw '无法整理本程序内存' }
''', const Duration(seconds: 6));
    return result.success;
  }
}
