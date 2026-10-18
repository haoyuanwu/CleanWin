import 'dart:convert';
import 'dart:io';

typedef PowerShellRunner = Future<PsResult> Function(
  String script,
  Duration timeout,
);

Future<PsResult> runPowerShell(String script, Duration timeout) =>
    ProcessUtils.runPowerShell(script, timeout: timeout);

/// PowerShell / 进程工具
class ProcessUtils {
  /// 测试环境置 true，不启动真实子进程
  static bool debugSkip = false;

  /// 执行 PowerShell 脚本，返回 stdout（UTF-8）
  static Future<PsResult> runPowerShell(
    String script, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (debugSkip) {
      return PsResult(exitCode: 0, stdout: '', stderr: '');
    }
    try {
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          script,
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(timeout);
      return PsResult(
        exitCode: result.exitCode,
        stdout: result.stdout?.toString() ?? '',
        stderr: result.stderr?.toString() ?? '',
      );
    } on Exception catch (e) {
      return PsResult(exitCode: -1, stdout: '', stderr: e.toString());
    }
  }

  /// 解析 PowerShell ConvertTo-Json 输出（可能是单对象或数组）
  static List<Map<String, dynamic>> parseJsonList(String stdout) {
    final text = stdout.trim();
    if (text.isEmpty) return [];
    try {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList();
      }
      if (decoded is Map) {
        return [decoded.map((k, v) => MapEntry(k.toString(), v))];
      }
    } on FormatException catch (_) {
      // PowerShell 有时会输出多行 JSON 对象，逐段尝试
      final parts = text.split(RegExp(r'\}\s*\{'));
      for (final part in parts) {
        var s = part.trim();
        if (!s.startsWith('{')) s = '{$s';
        if (!s.endsWith('}')) s = '$s}';
        try {
          final decoded = jsonDecode(s);
          if (decoded is Map) {
            return [decoded.map((k, v) => MapEntry(k.toString(), v))];
          }
        } on FormatException catch (_) {
          continue;
        }
      }
    }
    return [];
  }

  /// 是否以管理员运行
  static Future<bool> isElevated() async {
    final r = await runPowerShell(
      r'([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)',
      timeout: const Duration(seconds: 10),
    );
    return r.stdout.trim().toLowerCase() == 'true';
  }
}

class PsResult {
  PsResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get success => exitCode == 0;
}
