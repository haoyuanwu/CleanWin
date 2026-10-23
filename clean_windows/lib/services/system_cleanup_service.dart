import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'process_utils.dart';

enum SystemCleanupPhase { idle, analyzing, ready, cleaning, completed, failed }

enum MaintenanceJob { analyze, cleanup }

class MaintenanceResult {
  const MaintenanceResult(this.exitCode, this.output);
  final int exitCode;
  final String output;
  bool get success => exitCode == 0 || exitCode == 3010;
}

abstract class MaintenanceRunner {
  Future<MaintenanceResult> run(
    MaintenanceJob job,
    void Function(String) onOutput,
  );
  void cancelAnalysis();
}

/// Only documented servicing operations; never recursively delete WinSxS.
class WindowsMaintenanceRunner implements MaintenanceRunner {
  Process? _analysis;
  bool _cancelRequested = false;

  static List<String> arguments(MaintenanceJob job) => [
    '/English',
    '/Online',
    '/Cleanup-Image',
    job == MaintenanceJob.analyze
        ? '/AnalyzeComponentStore'
        : '/StartComponentCleanup',
    '/NoRestart',
  ];

  @override
  Future<MaintenanceResult> run(
    MaintenanceJob job,
    void Function(String) onOutput,
  ) async {
    if (!Platform.isWindows || ProcessUtils.debugSkip) {
      throw StateError('系统维护仅支持 Windows 管理员环境');
    }
    if (job == MaintenanceJob.analyze) _cancelRequested = false;
    final windows = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    // The Windows desktop bundle is x64. Use the trusted system executable.
    final process = await Process.start(
      '$windows\\System32\\Dism.exe',
      arguments(job),
      runInShell: false,
    );
    if (job == MaintenanceJob.analyze) {
      _analysis = process;
      if (_cancelRequested) process.kill();
    }
    var output = '';
    void receive(String chunk) {
      // /English output and percentage markers are ASCII. Preserve unknown
      // bytes for diagnostics without failing on the active Windows code page.
      output += chunk;
      if (output.length > 65536) {
        output = output.substring(output.length - 65536);
      }
      onOutput(output);
    }

    Future<void> consume(Stream<List<int>> stream) async {
      await for (final chunk in stream.transform(latin1.decoder)) {
        receive(chunk);
      }
    }

    final out = consume(process.stdout);
    final err = consume(process.stderr);
    Timer? deadline;
    if (job == MaintenanceJob.analyze) {
      deadline = Timer(const Duration(minutes: 10), process.kill);
    }
    try {
      final code = await process.exitCode;
      await Future.wait([out, err]);
      return MaintenanceResult(code, output);
    } finally {
      deadline?.cancel();
      if (identical(_analysis, process)) _analysis = null;
    }
  }

  @override
  void cancelAnalysis() {
    _cancelRequested = true;
    _analysis?.kill();
  }
}

class ComponentStoreReport {
  const ComponentStoreReport({
    required this.packages,
    required this.recommended,
  });
  final int packages;
  final bool recommended;

  static ComponentStoreReport? parse(String output) {
    final count = RegExp(
      r'Number of Reclaimable Packages\s*:\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(output);
    final advice = RegExp(
      r'Component Store Cleanup Recommended\s*:\s*(Yes|No)\b',
      caseSensitive: false,
    ).firstMatch(output);
    if (count == null || advice == null) return null;
    return ComponentStoreReport(
      packages: int.parse(count[1]!),
      recommended: advice[1]!.toLowerCase() == 'yes',
    );
  }
}

/// App-owned task: dismissing a dialog or navigating never starts or stops it.
class SystemCleanupController extends ChangeNotifier {
  SystemCleanupController({MaintenanceRunner? runner})
    : _runner = runner ?? WindowsMaintenanceRunner();
  final MaintenanceRunner _runner;
  SystemCleanupPhase phase = SystemCleanupPhase.idle;
  ComponentStoreReport? report;
  DateTime? analyzedAt;
  String output = '';
  String? error;
  double? progress;
  bool restartRequired = false;
  bool _cancelled = false;
  bool _disposed = false;
  bool get busy =>
      phase == SystemCleanupPhase.analyzing ||
      phase == SystemCleanupPhase.cleaning;
  bool get canClean =>
      phase == SystemCleanupPhase.ready &&
      report?.recommended == true &&
      report!.packages > 0 &&
      analyzedAt != null &&
      DateTime.now().difference(analyzedAt!) < const Duration(minutes: 30);

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _receive(String text) {
    output = text;
    final matches = RegExp(r'(\d{1,3}(?:\.\d+)?)\s*%').allMatches(text);
    if (matches.isNotEmpty) {
      final next = (double.parse(matches.last[1]!) / 100).clamp(0.0, 1.0);
      if (progress == null || next > progress!) progress = next;
    }
    _emit();
  }

  Future<void> analyze() async {
    if (busy) return;
    phase = SystemCleanupPhase.analyzing;
    error = null;
    progress = null;
    output = '';
    _cancelled = false;
    restartRequired = false;
    _emit();
    try {
      final result = await _runner.run(MaintenanceJob.analyze, _receive);
      output = result.output;
      if (_cancelled) {
        phase = SystemCleanupPhase.idle;
        return;
      }
      if (!result.success) {
        throw StateError('系统分析失败（代码 ${result.exitCode}），请查看诊断详情后重试');
      }
      final parsed = ComponentStoreReport.parse(output);
      if (parsed == null) throw StateError('未能识别系统分析结果，未开放清理；请查看诊断详情');
      report = parsed;
      analyzedAt = DateTime.now();
      restartRequired = result.exitCode == 3010;
      phase = SystemCleanupPhase.ready;
    } catch (e) {
      if (_cancelled) {
        phase = SystemCleanupPhase.idle;
      } else {
        phase = SystemCleanupPhase.failed;
        error = e.toString().replaceFirst('Bad state: ', '');
      }
    } finally {
      _emit();
    }
  }

  void cancelAnalysis() {
    if (phase != SystemCleanupPhase.analyzing) return;
    _cancelled = true;
    _runner.cancelAnalysis();
  }

  /// Caller must obtain explicit confirmation; no default selection or startup run.
  Future<void> clean() async {
    if (!canClean || restartRequired) return;
    phase = SystemCleanupPhase.cleaning;
    progress = null;
    output = '';
    error = null;
    _emit();
    try {
      final result = await _runner.run(MaintenanceJob.cleanup, _receive);
      output = result.output;
      if (!result.success) {
        throw StateError('系统清理未完成（代码 ${result.exitCode}），请查看诊断详情');
      }
      restartRequired = result.exitCode == 3010;
      phase = SystemCleanupPhase.completed;
      // Package counts are not bytes. Never claim a made-up freed-space value.
      report = null;
      analyzedAt = null;
      progress = 1;
    } catch (e) {
      phase = SystemCleanupPhase.failed;
      error = e.toString().replaceFirst('Bad state: ', '');
    } finally {
      _emit();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    // A read-only analysis can be stopped; never kill servicing midway.
    if (phase == SystemCleanupPhase.analyzing) _runner.cancelAnalysis();
    super.dispose();
  }
}
