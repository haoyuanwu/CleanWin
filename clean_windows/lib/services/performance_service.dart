import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'process_utils.dart';
import 'windows_runtime_metrics.dart';
import 'windows_process_sampler.dart';
import 'network_rates.dart';

class RuntimeSnapshot {
  const RuntimeSnapshot({
    required this.cpuPercent,
    required this.memoryUsedPercent,
    required this.cpuTempC,
    required this.topProcesses,
    required this.collectedAt,
    this.totalMemoryMb = 0,
    this.usedMemoryMb = 0,
    this.cpuTempSource,
    this.downloadBytesPerSecond,
    this.uploadBytesPerSecond,
    this.networkAdapters = 0,
  });
  final double? downloadBytesPerSecond, uploadBytesPerSecond;
  final int networkAdapters;
  final double cpuPercent;
  final double memoryUsedPercent;
  final double? cpuTempC;
  final String? cpuTempSource;
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
      : cpuTempSource ?? 'CPU 传感器';
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
    this.includeProcesses = true,
  }) : _run = powerShellRunner ?? runPowerShell,
       _clock = clock ?? DateTime.now,

       _useWorker = powerShellRunner == null;
  final bool includeProcesses;
  final _network = NetworkRates();
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
  String? _temperatureSource;

  // One process per snapshot; no deliberate one-second counter waits.
  // WorkingSet64 is physical working-set memory, including shared pages.
  static const networkScript = r'''
$network=@()
$networkOk=$true
try {
  foreach($adapter in [Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
    if($adapter.OperationalStatus -ne 'Up' -or $adapter.NetworkInterfaceType -in @('Loopback','Tunnel')){continue}
    try {
      $stats=$adapter.GetIPStatistics()
      $network += [PSCustomObject]@{Id=$adapter.Id;Rx=$stats.BytesReceived;Tx=$stats.BytesSent}
    } catch { $networkOk=$false }
  }
} catch { $networkOk=$false }
if(!$networkOk){$network=$null}
''';
  static const resourceScript =
      networkScript +
      r'''
[PSCustomObject]@{Processes=@();Network=$network;NetworkTicks=[DateTime]::UtcNow.Ticks} | ConvertTo-Json -Compress -Depth 4
''';
  static const snapshotScript =
      networkScript +
      r'''
$ErrorActionPreference = 'Stop'
$processes = @(Get-Process -ErrorAction Stop | ForEach-Object {
  $process = $_
  try {
    $memory = $process.WorkingSet64
    [PSCustomObject]@{ Name=$process.ProcessName; Id=$process.Id;
      MemMB=([double]$memory / 1MB) }
  } catch { }
} | Sort-Object MemMB -Descending)
[PSCustomObject]@{
  Processes = @($processes)
  Network = $network
  NetworkTicks = [DateTime]::UtcNow.Ticks
} | ConvertTo-Json -Compress -Depth 4
''';

  // Read only already-running hardware sensor providers. ACPI thermal zones can
  // represent the motherboard and must never be presented as CPU temperature.
  static const temperatureScript = r'''
$ErrorActionPreference = 'Stop'
$readings = @()
foreach ($provider in @('LibreHardwareMonitor', 'OpenHardwareMonitor')) {
  try {
    $namespace = 'root/' + $provider
    $cpus = @(Get-CimInstance -Namespace $namespace -ClassName Hardware -Filter "HardwareType='Cpu'" -OperationTimeoutSec 2 -ErrorAction Stop)
    if ($cpus.Count -eq 0) { continue }
    $ids = @($cpus | ForEach-Object { $_.Identifier })
    $sensors = @(Get-CimInstance -Namespace $namespace -ClassName Sensor -Filter "SensorType='Temperature'" -OperationTimeoutSec 2 -ErrorAction Stop)
    foreach ($sensor in $sensors) {
      if ($ids -contains $sensor.Parent) {
        $readings += [PSCustomObject]@{ Provider=$provider; HardwareType='Cpu';
          Name=$sensor.Name; Value=$sensor.Value; Identifier=$sensor.Identifier }
      }
    }
    if ($readings.Count -gt 0) { break }
  } catch { } # Missing providers and denied namespaces are normal on many PCs.
}
ConvertTo-Json -InputObject @($readings) -Compress -Depth 3
''';

  /// Select a package reading when available, otherwise the hottest CPU sensor.
  /// Never accept a bare thermal-zone number or non-CPU hardware as CPU data.
  static ({double value, String source})? parseTemperature(String output) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(output);
    } on FormatException {
      return null;
    }
    if (decoded is! List) return null;
    final readings = <({double value, String source, bool package})>[];
    for (final row in decoded.whereType<Map>()) {
      final provider = row['Provider'];
      final value = row['Value'];
      if ((provider != 'LibreHardwareMonitor' &&
              provider != 'OpenHardwareMonitor') ||
          row['HardwareType'] != 'Cpu' ||
          value is! num ||
          !value.isFinite ||
          value <= 0 ||
          value > 130) {
        continue;
      }
      final name = row['Name']?.toString() ?? '';
      readings.add((
        value: value.toDouble(),
        source: '$provider · ${name.isEmpty ? "CPU" : name}',
        package: RegExp(
          r'package|tctl|tdie',
          caseSensitive: false,
        ).hasMatch(name),
      ));
    }
    if (readings.isEmpty) return null;
    final packages = readings.where((reading) => reading.package).toList();
    final selected = packages.isNotEmpty ? packages : readings;
    selected.sort((a, b) => b.value.compareTo(a.value));
    return (value: selected.first.value, source: selected.first.source);
  }

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
    final rates = _network.read(raw['Network'], raw['NetworkTicks']);
    return RuntimeSnapshot(
      downloadBytesPerSecond: rates.down,
      uploadBytesPerSecond: rates.up,
      networkAdapters: rates.adapters,
      cpuPercent: metrics.cpuPercent ?? 0,
      memoryUsedPercent: metrics.memoryPercent.clamp(0, 100),
      totalMemoryMb: total,
      usedMemoryMb: metrics.usedMemoryMb.clamp(0, total),
      cpuTempC: _temperatureSource == null ? null : _temperature,
      cpuTempSource: _temperatureSource,
      topProcesses: List.unmodifiable(processes),
      collectedAt: _clock(),
    );
  }

  void _scheduleTemperature() {
    final now = _clock();
    if (_readingTemperature ||
        (_temperatureAttempt != null &&
            now.difference(_temperatureAttempt!) <
                Duration(seconds: _temperature == null ? 30 : 5))) {
      return;
    }
    _temperatureAttempt = now;
    _readingTemperature = true;
    unawaited(_readTemperature());
  }

  Future<void> _readTemperature() async {
    try {
      final result = await _run(temperatureScript, const Duration(seconds: 10));
      final reading = result.success ? parseTemperature(result.stdout) : null;
      _temperature = reading?.value;
      _temperatureSource = reading?.source;
    } on Exception {
      _temperature = null;
      _temperatureSource = null;
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
    _network.reset();
    final worker = _worker;
    _worker = null;
    await worker?.close();
  }

  Future<void> dispose() => pause();

  Future<PsResult> _readProcesses() async {
    final script = includeProcesses ? snapshotScript : resourceScript;
    if (!_useWorker) return _run(script, const Duration(seconds: 6));
    try {
      return await (_worker ??= WindowsProcessSampler(script)).sample();
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
