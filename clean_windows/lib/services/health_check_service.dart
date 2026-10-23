import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'health_check_scripts.dart';
import 'process_utils.dart';

enum HealthStatus { normal, attention, info, unavailable }

class HealthEntry {
  const HealthEntry(this.id, this.label, this.value, this.status);
  final String id, label, value;
  final HealthStatus status;
}

class HealthSection {
  const HealthSection(this.id, this.title, this.entries);
  final String id, title;
  final List<HealthEntry> entries;
  int get attentionCount =>
      entries.where((e) => e.status == HealthStatus.attention).length;
  int get unavailableCount =>
      entries.where((e) => e.status == HealthStatus.unavailable).length;
}

/// A run owns its subprocess, so cancel/timeout cannot leave a WMI scan behind.
class HealthCheckService {
  // ignore: prefer_initializing_formals
  HealthCheckService({PowerShellRunner? runner}) : _runner = runner;
  final PowerShellRunner? _runner;
  Process? _process;
  bool _cancelled = false;
  bool _running = false;
  static final phases = [
    ('hardware', '硬件概况', hardwareHealthScript),
    ('network', '网络诊断', networkHealthScript),
    ('storage', '空间与痕迹', storageHealthScript),
    ('applications', '应用与启动', applicationsHealthScript),
    ('preferences', '设置建议', preferencesHealthScript),
  ];

  void cancel() {
    _cancelled = true;
    _process?.kill();
  }

  Stream<HealthSection> scan() => _scan(null);

  /// A feature page executes only its own read-only inspections.
  Stream<HealthSection> scanPhases(Set<String> ids) => _scan(ids);

  Stream<HealthSection> _scan(Set<String>? ids) async* {
    if (_running) throw StateError('体检正在进行');
    _running = true;
    _cancelled = false;
    try {
      for (final phase in phases) {
        if (ids != null && !ids.contains(phase.$1)) continue;
        if (_cancelled) break;
        try {
          final result = await _execute(
            '$healthScriptPreamble\n${phase.$3}\n$healthScriptEnd',
          );
          if (_cancelled) break;
          if (!result.success) throw const FormatException('检查未完成');
          yield HealthSection(phase.$1, phase.$2, parseEntries(result.stdout));
        } catch (_) {
          if (_cancelled) break;
          yield HealthSection(phase.$1, phase.$2, const [
            HealthEntry(
              'unavailable',
              '检查未完成',
              '接口不可用、权限不足或检查超时，可重新体检。',
              HealthStatus.unavailable,
            ),
          ]);
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<PsResult> _execute(String script) async {
    const timeout = Duration(seconds: 35);
    if (_runner != null) return _runner(script, timeout);
    if (!Platform.isWindows || ProcessUtils.debugSkip) {
      return PsResult(exitCode: -1, stdout: '', stderr: 'Unavailable');
    }
    final process = await Process.start('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-EncodedCommand',
      base64Encode(_utf16(script)),
    ]);
    _process = process;
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.transform(utf8.decoder).join();
    if (_cancelled) process.kill();
    try {
      final code = await process.exitCode.timeout(timeout);
      return PsResult(
        exitCode: code,
        stdout: await output,
        stderr: await errors,
      );
    } on TimeoutException {
      process.kill();
      await Future.wait([output, errors]);
      rethrow;
    } finally {
      if (identical(_process, process)) _process = null;
    }
  }

  static List<int> _utf16(String value) => [
    for (final unit in value.codeUnits) ...[unit & 255, unit >> 8],
  ];

  static List<HealthEntry> parseEntries(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! List || decoded.isEmpty) {
      throw const FormatException('没有检查结果');
    }
    final entries = <HealthEntry>[];
    final seen = <String>{};
    for (final row in decoded) {
      if (row is! Map ||
          row['id'] is! String ||
          row['label'] is! String ||
          row['value'] is! String) {
        throw const FormatException('检查结果格式错误');
      }
      final id = row['id'] as String;
      if (id.isEmpty || !seen.add(id)) throw const FormatException('检查标识无效');
      final status = HealthStatus.values
          .where((s) => s.name == row['status'])
          .firstOrNull;
      if (status == null) throw const FormatException('检查状态无效');
      entries.add(HealthEntry(id, row['label'], redact(row['value']), status));
    }
    return List.unmodifiable(entries);
  }

  // Proxy URLs can contain credentials. Neither the UI nor copied reports expose them.
  static String redact(String value) => value
      .replaceAll(RegExp(r'(?<=://)[^\s/@]+@'), '***@')
      .replaceAll(RegExp(r'[^/\s:@]+:[^/\s@]+@'), '***@')
      .replaceAll(RegExp(r'\?[^\s]*'), '?***');

  Future<HealthSection> probeConnectivity() async {
    _cancelled = false;
    final result = await _execute(
      '$healthScriptPreamble\n$connectivityHealthScript\n$healthScriptEnd',
    );
    if (!result.success) throw StateError('连通性检测未完成');
    return HealthSection('connectivity', '外网探测', parseEntries(result.stdout));
  }

  Future<bool> flushDns() async {
    if (ProcessUtils.debugSkip || !Platform.isWindows) return false;
    try {
      final result = await Process.run('ipconfig.exe', [
        '/flushdns',
      ]).timeout(const Duration(seconds: 8));
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}

/// Lives with the page in IndexedStack; leaving the page doesn't restart a scan.
class HealthCheckController extends ChangeNotifier {
  HealthCheckController({HealthCheckService? service})
    : service = service ?? HealthCheckService();
  final HealthCheckService service;
  final Map<String, HealthSection> _sections = {};
  final Set<String> _fresh = {};
  bool scanning = false;
  bool cancelled = false;
  bool probing = false;
  bool _disposed = false;
  Future<void>? _startupRead;
  bool startupReading = false;
  DateTime? completedAt;
  String current = '';
  List<HealthSection> get sections => List.unmodifiable(_sections.values);
  bool isFresh(String id) => _fresh.contains(id);
  int get completedPhases => _fresh
      .where((id) => HealthCheckService.phases.any((p) => p.$1 == id))
      .length;
  int get attentionCount => sections.fold(0, (n, s) => n + s.attentionCount);
  int get unavailableCount =>
      sections.fold(0, (n, s) => n + s.unavailableCount);

  /// One silent local snapshot per application session, independent of file scans.
  Future<void> readOnStartup() => _startupRead ??= _readOnStartup();

  Future<void> _readOnStartup() async {
    startupReading = true;
    try {
      await scan(phaseIds: const {'hardware', 'network'});
    } finally {
      startupReading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> scan({Set<String>? phaseIds}) async {
    if (scanning || probing || _disposed) return;
    final requested = HealthCheckService.phases
        .where((phase) => phaseIds == null || phaseIds.contains(phase.$1))
        .toList();
    if (requested.isEmpty) return;
    scanning = true;
    cancelled = false;
    _fresh.removeAll(requested.map((phase) => phase.$1));
    current = requested.first.$2;
    var completed = 0;
    notifyListeners();
    try {
      final stream = phaseIds == null
          ? service.scan()
          : service.scanPhases(phaseIds);
      await for (final section in stream) {
        if (_disposed || cancelled) break;
        _sections[section.id] = section;
        _fresh.add(section.id);
        final next = ++completed;
        current = next < requested.length ? requested[next].$2 : '';
        notifyListeners();
      }
      if (!cancelled && !_disposed) completedAt = DateTime.now();
    } finally {
      scanning = false;
      current = '';
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> probeConnectivity() async {
    if (scanning || probing || _disposed) return;
    probing = true;
    notifyListeners();
    try {
      final result = await service.probeConnectivity();
      if (!_disposed) {
        _sections[result.id] = result;
        _fresh.add(result.id);
      }
    } finally {
      probing = false;
      if (!_disposed) notifyListeners();
    }
  }

  void cancel() {
    if (!scanning) return;
    cancelled = true;
    service.cancel();
    notifyListeners();
  }

  String report() => [
    'CleanWin 本机体检报告',
    if (completedAt != null) '检查更新时间：$completedAt',
    if (scanning) '正在体检，包含已保留结果',
    if (cancelled) '本次体检已取消，包含已保留结果',
    for (final section in sections) ...[
      '\n${section.title}${!isFresh(section.id) ? '（上次结果）' : ''}',
      for (final entry in section.entries) '${entry.label}：${entry.value}',
    ],
    '\n系统连通状态来自 Windows；只有外网探测项包含实际测试，未执行任何修复。',
  ].join('\n');

  @override
  void dispose() {
    _disposed = true;
    service.cancel();
    super.dispose();
  }
}

enum HealthSettings {
  network('ms-settings:network-status'),
  proxy('ms-settings:network-proxy'),
  defaults('ms-settings:defaultapps'),
  taskbar('ms-settings:taskbar'),
  lockScreen('ms-settings:lockscreen'),
  notifications('ms-settings:notifications'),
  startup('ms-settings:startupapps'),
  troubleshoot('ms-settings:troubleshoot'),
  storage('ms-settings:storagesense'),
  updates('ms-settings:windowsupdate'),
  recovery('ms-settings:recovery');

  const HealthSettings(this.uri);
  final String uri;
  Future<void> open() async {
    if (ProcessUtils.debugSkip || !Platform.isWindows) return;
    // Only compile-time settings URIs, never a command obtained from a scan.
    // Explorer hands the URI to the existing Windows shell. Its exit code
    // does not describe whether Settings opened; only report launch failures.
    await Process.start('explorer.exe', [uri], mode: ProcessStartMode.detached);
  }
}
