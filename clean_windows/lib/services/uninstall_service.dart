import 'dart:convert';
import 'dart:io';

import '../models/installed_app.dart';
import 'module_cache.dart';
import 'path_utils.dart';
import 'process_utils.dart';

/// 软件卸载服务：读注册表列表 + 执行卸载
class UninstallService {
  UninstallService({PowerShellRunner? runner, ModuleCache? cache})
    : _runner = runner ?? runPowerShell,
      _cache = cache ?? AppCache.apps;
  final PowerShellRunner _runner;
  final ModuleCache _cache;
  static const _cacheKey = 'installed_v2';
  static const _sizeCacheKey = 'size_estimates_v1';
  static const _psList = r'''
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$paths = @(
  'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
  'HKCU:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$apps = foreach ($p in $paths) {
  Get-ItemProperty $p | Where-Object { $_.DisplayName } | ForEach-Object {
    [PSCustomObject]@{
      DisplayName        = $_.DisplayName
      DisplayVersion     = $_.DisplayVersion
      Publisher          = $_.Publisher
      InstallLocation    = $_.InstallLocation
      UninstallString    = $_.UninstallString
      QuietUninstallString = $_.QuietUninstallString
      EstimatedSize      = $_.EstimatedSize
      SystemComponent    = $_.SystemComponent
      DisplayIcon        = $_.DisplayIcon
      RegistryKey        = $_.PSPath
    }
  }
}
ConvertTo-Json -InputObject @($apps | Sort-Object DisplayName) -Depth 4 -Compress
''';

  /// 获取已安装软件列表（带临时缓存）
  Future<List<InstalledApp>> listInstalled({bool force = false}) async {
    if (!force) {
      final cached = _cache.getList(_cacheKey);
      if (cached != null) {
        return cached
            .whereType<Map>()
            .map(
              (m) => InstalledApp.fromJson(
                m.map((k, v) => MapEntry(k.toString(), v)),
              ),
            )
            .toList();
      }
    }

    final r = await _runner(_psList, const Duration(seconds: 90));
    if (!r.success) throw StateError('读取已安装软件失败，请重试');

    final apps = <InstalledApp>[];
    final seen = <String>{};

    final decoded = jsonDecode(
      r.stdout.trim().isEmpty && ProcessUtils.debugSkip ? '[]' : r.stdout,
    );
    if (decoded is! List && decoded is! Map) {
      throw const FormatException('安装列表格式不完整');
    }
    for (final map
        in (decoded is List ? decoded : [decoded]).whereType<Map>()) {
      final app = InstalledApp.fromJson(Map<String, dynamic>.from(map));
      if (app.isSystemComponent) continue;
      if (!app.canUninstall) continue;
      final key = app.identity;
      if (seen.contains(key)) continue;
      seen.add(key);
      apps.add(app);
    }

    apps.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );

    _restoreMeasuredSizes(apps);
    _cache.set(
      _cacheKey,
      apps
          .map(
            (a) => {
              'DisplayName': a.displayName,
              'DisplayVersion': a.displayVersion,
              'Publisher': a.publisher,
              'InstallLocation': a.installLocation,
              'UninstallString': a.uninstallString,
              'QuietUninstallString': a.quietUninstallString,
              'EstimatedSize': a.estimatedSizeKb,
              'RegistryKey': a.registryKey,
              'DisplayIcon': a.displayIcon,
              'SystemComponent': a.isSystemComponent ? '1' : '0',
            },
          )
          .toList(),
    );
    return apps;
  }

  void _restoreMeasuredSizes(List<InstalledApp> apps) {
    final cached = _cache.getMap(_sizeCacheKey);
    if (cached == null) return;
    for (final app in apps) {
      if (app.hasRegistrySize) continue;
      final bytes = cached[app.identity];
      if (bytes is num && bytes > 0) {
        app.measuredSizeBytes = bytes.toInt();
      }
    }
  }

  /// 为未报告 EstimatedSize 的软件测量安装目录大小。
  /// [onUpdated] 每完成一项回调一次，便于界面渐进刷新。
  Future<void> fillMissingSizes(
    List<InstalledApp> apps, {
    void Function(InstalledApp app)? onUpdated,
  }) async {
    final pending = <InstalledApp>[];
    final sizes = Map<String, dynamic>.from(_cache.getMap(_sizeCacheKey) ?? {});
    var dirty = false;
    for (final app in apps) {
      if (app.hasRegistrySize) continue;
      if ((app.measuredSizeBytes ?? 0) > 0) {
        sizes[app.identity] = app.measuredSizeBytes;
        dirty = true;
        continue;
      }
      final cached = sizes[app.identity];
      if (cached is num && cached > 0) {
        app.measuredSizeBytes = cached.toInt();
        onUpdated?.call(app);
        continue;
      }
      pending.add(app);
    }
    if (dirty) _cache.set(_sizeCacheKey, sizes);

    for (final app in pending) {
      final root = resolveInstallRoot(
        installLocation: app.installLocation,
        uninstallString: app.uninstallString,
        quietUninstallString: app.quietUninstallString,
        displayIcon: app.displayIcon,
      );
      if (root == null || !Directory(root).existsSync()) continue;
      try {
        final bytes = await measureDirectoryBytes(root);
        if (bytes > 0) {
          app.measuredSizeBytes = bytes;
          sizes[app.identity] = bytes;
          _cache.set(_sizeCacheKey, sizes);
          onUpdated?.call(app);
        }
      } on Exception catch (_) {
        // 测量失败保持未知大小，不阻断列表
      }
    }
  }

  /// Launch the normal wizard; success requires checking the exact install record.
  Future<UninstallResult> uninstall(InstalledApp app) async {
    final raw = app.uninstallString?.trim().isNotEmpty == true
        ? app.uninstallString!.trim()
        : app.quietUninstallString?.trim();
    if (raw == null || raw.isEmpty) {
      return UninstallResult(success: false, message: '没有卸载命令');
    }
    final match =
        RegExp(
          r'^"([^"]+\.exe)"\s*(.*)$',
          caseSensitive: false,
        ).firstMatch(raw) ??
        RegExp(
          r'^(.+?\.exe)(?:\s+(.*))?$',
          caseSensitive: false,
        ).firstMatch(raw);
    if (match == null) {
      return UninstallResult(
        success: false,
        message: '无法安全解析卸载命令，请在 Windows 设置中卸载',
      );
    }
    final executable = match[1]!;
    var arguments = match[2] ?? '';
    if (executable.toLowerCase().endsWith('msiexec.exe')) {
      arguments = arguments.replaceFirst(
        RegExp(r'/I(?=\s*\{)', caseSensitive: false),
        '/X',
      );
    }
    final encoded = base64Encode(
      utf8.encode(
        jsonEncode({
          'file': executable,
          'args': arguments,
          'key': app.registryKey,
        }),
      ),
    );
    final script =
        '''
\$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
\$payload=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encoded')) | ConvertFrom-Json
try {
  if ([string]::IsNullOrWhiteSpace(\$payload.args)) { \$child=Start-Process -FilePath \$payload.file -PassThru -Wait -ErrorAction Stop }
  else { \$child=Start-Process -FilePath \$payload.file -ArgumentList \$payload.args -PassThru -Wait -ErrorAction Stop }
  \$present=\$null
  if (\$payload.key) { \$present=Test-Path -LiteralPath \$payload.key -ErrorAction Stop }
  @{Code=\$child.ExitCode; Present=\$present} | ConvertTo-Json -Compress
} catch {
  if (\$_.Exception.NativeErrorCode -eq 1223) { @{Code=1602;Present=\$true} | ConvertTo-Json -Compress }
  else { throw }
}
''';
    try {
      final response = await _runner(script, const Duration(minutes: 5));
      if (!response.success) {
        return UninstallResult(
          success: false,
          status: UninstallStatus.unverified,
          message: '未能确认卸载结果，请刷新核对；卸载向导可能仍在运行',
        );
      }
      final result = jsonDecode(response.stdout);
      if (result is! Map || result['Code'] is! num) {
        throw const FormatException('缺少卸载结果');
      }
      final code = (result['Code'] as num).toInt();
      if (code == 1602 || code == 1223) {
        return UninstallResult(
          success: false,
          status: UninstallStatus.cancelled,
          message: '已取消卸载，软件仍保留',
        );
      }
      if (![0, 1641, 3010].contains(code)) {
        return UninstallResult(
          success: false,
          message: '卸载未完成（退出码 $code），软件仍保留',
        );
      }
      bool? present = result['Present'] is bool
          ? result['Present'] as bool
          : null;
      if (present == null) {
        final current = await listInstalled(force: true);
        present = current.any((item) => item.identity == app.identity);
      }
      if (present) {
        return UninstallResult(
          success: false,
          status: code == 0
              ? UninstallStatus.unverified
              : UninstallStatus.restartRequired,
          message: code == 0
              ? '卸载向导已退出，安装记录仍存在，请刷新或继续完成向导'
              : '卸载要求重新启动，请重启后刷新核对',
        );
      }
      _cache.invalidate(_cacheKey);
      return UninstallResult(
        success: true,
        status: code == 0
            ? UninstallStatus.completed
            : UninstallStatus.restartRequired,
        message: code == 0 ? '卸载已完成，安装记录已核对' : '卸载已完成，需要重新启动 Windows',
      );
    } catch (_) {
      return UninstallResult(
        success: false,
        status: UninstallStatus.unverified,
        message: '暂时无法确认卸载结果，请刷新列表核对',
      );
    }
  }
}

enum UninstallStatus {
  completed,
  cancelled,
  failed,
  restartRequired,
  unverified,
}

class UninstallResult {
  UninstallResult({
    required this.success,
    required this.message,
    this.status = UninstallStatus.failed,
  });
  final bool success;
  final String message;
  final UninstallStatus status;
}
