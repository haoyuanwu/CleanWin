import 'dart:convert';

import 'module_cache.dart';
import 'process_utils.dart';
import 'registry_audit_script.dart';

const registryCategoryLabels = {
  'startup': '启动命令',
  'appPaths': '程序路径',
  'mui': 'MUI 缓存',
};

class RegistryIssue {
  RegistryIssue({
    required this.title,
    required this.detail,
    required this.hive,
    required this.keyPath,
    required this.valueName,
    required this.severity,
    this.view = 'Registry64',
    this.category = 'other',
    this.data,
    this.valueKind = '',
    this.target = '',
    this.deletable = false,
  });
  final String title,
      detail,
      hive,
      keyPath,
      severity,
      view,
      category,
      valueKind,
      target;
  final String? valueName;
  final Object? data;
  final bool deletable;
  String get fullKey => '$hive\\$keyPath';
  String get id => '$hive|$view|$keyPath|${valueName ?? '<key>'}'.toLowerCase();
  String get categoryLabel => registryCategoryLabels[category] ?? category;
  bool get canDelete => deletable && RegistryScanService.accepts(this);
  factory RegistryIssue.fromJson(Map<String, dynamic> row) => RegistryIssue(
    title: '${row['Title'] ?? ''}',
    detail: '${row['Detail'] ?? ''}',
    hive: '${row['Hive'] ?? ''}',
    keyPath: '${row['KeyPath'] ?? ''}',
    valueName: row['ValueName']?.toString(),
    severity: '${row['Severity'] ?? 'info'}',
    view: '${row['View'] ?? ''}',
    category: '${row['Category'] ?? 'other'}',
    data: row['Data'],
    valueKind: '${row['ValueKind'] ?? ''}',
    target: '${row['Target'] ?? ''}',
    deletable: row['CanDelete'] == true,
  );
  Map<String, dynamic> toJson() => {
    'Title': title,
    'Detail': detail,
    'Hive': hive,
    'KeyPath': keyPath,
    'ValueName': valueName,
    'Severity': severity,
    'View': view,
    'Category': category,
    'Data': data,
    'ValueKind': valueKind,
    'Target': target,
    'CanDelete': deletable,
  };
}

class RegistryCoverage {
  RegistryCoverage.fromJson(Map<String, dynamic> row)
    : hive = '${row['Hive'] ?? ''}',
      view = '${row['View'] ?? ''}',
      path = '${row['Path'] ?? ''}',
      category = '${row['Category'] ?? ''}',
      status = '${row['Status'] ?? 'partial'}',
      keys = (row['Keys'] as num?)?.toInt() ?? 0,
      checked = (row['Checked'] as num?)?.toInt() ?? 0,
      unverified = (row['Unverified'] as num?)?.toInt() ?? 0;
  final String hive, view, path, category, status;
  final int keys, checked, unverified;
  String get statusLabel => switch (status) {
    'ok' => '已检查',
    'missing' => '位置不存在',
    _ => '部分未读取',
  };
}

class RegistryScanService {
  RegistryScanService({PowerShellRunner? powerShellRunner, ModuleCache? cache})
    : _run = powerShellRunner ?? runPowerShell,
      _cache = cache ?? AppCache.registry;
  final PowerShellRunner _run;
  final ModuleCache _cache;
  List<RegistryCoverage> coverage = [];
  List<String> warnings = [];
  static const _cacheKey = 'registry_cleanable_v4';

  Future<bool> restoreValue(RegistryIssue issue) async {
    if (!issue.canDelete) return false;
    final encoded = base64Encode(utf8.encode(jsonEncode(issue.toJson())));
    final prefix =
        "\$snapshot=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encoded')) | ConvertFrom-Json\n";
    final response = await _run(
      prefix +
          r'''
$ErrorActionPreference='Stop'
$base=$null;$key=$null
try {
  $hive='CurrentUser'; if($snapshot.Hive -eq 'HKLM') {$hive='LocalMachine'}
  $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::$hive,[Microsoft.Win32.RegistryView]::$($snapshot.View))
  $key=$base.CreateSubKey([string]$snapshot.KeyPath,$true)
  if ($key.GetValueNames() -contains [string]$snapshot.ValueName) { throw '值已存在，禁止覆盖' }
  $kind=[Microsoft.Win32.RegistryValueKind]::$($snapshot.ValueKind)
  $key.SetValue([string]$snapshot.ValueName,[string]$snapshot.Data,$kind)
  $key.Flush()
} catch { Write-Error $_;exit 1 }
finally {if($key){$key.Dispose()};if($base){$base.Dispose()}}
''',
      const Duration(seconds: 20),
    );
    if (response.success) _cache.invalidate(_cacheKey);
    return response.success;
  }

  Future<List<RegistryIssue>> scan({bool force = false}) async {
    Map<String, dynamic>? result = force ? null : _cache.getMap(_cacheKey);
    if (result == null) {
      final response = await _run(
        registryAuditScript,
        const Duration(seconds: 120),
      );
      if (!response.success) throw Exception('注册表扫描失败：${response.stderr}');
      if (response.stdout.trim().isEmpty && ProcessUtils.debugSkip) return [];
      final parsed = jsonDecode(response.stdout);
      if (parsed is! Map ||
          parsed['Issues'] is! List ||
          parsed['Coverage'] is! List ||
          parsed['Warnings'] is! List) {
        throw const FormatException('注册表扫描结果不完整');
      }
      result = Map<String, dynamic>.from(parsed);
      _cache.set(_cacheKey, result);
    }
    final seen = <String>{};
    final issues = (result['Issues'] as List)
        .whereType<Map>()
        .map((row) => RegistryIssue.fromJson(Map<String, dynamic>.from(row)))
        .where(
          (issue) =>
              issue.title.isNotEmpty && issue.canDelete && seen.add(issue.id),
        )
        .toList();
    coverage = (result['Coverage'] as List)
        .whereType<Map>()
        .map((row) => RegistryCoverage.fromJson(Map<String, dynamic>.from(row)))
        .toList();
    warnings = (result['Warnings'] as List)
        .map((value) => value.toString())
        .toList();
    return issues;
  }

  static bool accepts(RegistryIssue issue) {
    if (!{'HKCU', 'HKLM'}.contains(issue.hive) ||
        !{'Registry64', 'Registry32'}.contains(issue.view) ||
        issue.valueName == null ||
        issue.data is! String ||
        !{'String', 'ExpandString'}.contains(issue.valueKind) ||
        !RegExp(
          r'^[A-Za-z]:\\.+\.(exe|com|bat|cmd|ps1|vbs|js)$',
          caseSensitive: false,
        ).hasMatch(issue.target)) {
      return false;
    }
    final path = issue.keyPath.toLowerCase();
    if (issue.category == 'startup') {
      return issue.valueName!.isNotEmpty &&
          {
            r'software\microsoft\windows\currentversion\run',
            r'software\microsoft\windows\currentversion\runonce',
          }.contains(path);
    }
    if (issue.category == 'mui') {
      final match = RegExp(
        r'^([A-Za-z]:\\.+?\.exe)(?:\.[^\\]+)?$',
        caseSensitive: false,
      ).firstMatch(issue.valueName!);
      return issue.hive == 'HKCU' &&
          match != null &&
          match[1]!.toLowerCase() == issue.target.toLowerCase() &&
          {
            r'software\classes\local settings\software\microsoft\windows\shell\muicache',
            r'software\microsoft\windows\shellnoroam\muicache',
          }.contains(path);
    }
    const root = r'software\microsoft\windows\currentversion\app paths\';
    return issue.category == 'appPaths' &&
        issue.valueName == '' &&
        path.startsWith(root) &&
        path.substring(root.length).isNotEmpty &&
        !path.substring(root.length).contains('\\') &&
        issue.target.toLowerCase().endsWith('.exe');
  }

  Future<bool> deleteValue(RegistryIssue issue) async {
    if (!issue.canDelete) return false;
    final encoded = base64Encode(utf8.encode(jsonEncode(issue.toJson())));
    final script =
        "\$snapshot=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encoded')) | ConvertFrom-Json\n"
        r'''
$ErrorActionPreference='Stop'
$base=$null; $key=$null
try {
  $hive='CurrentUser'; if($snapshot.Hive -eq 'HKLM') {$hive='LocalMachine'}
  $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::$hive,[Microsoft.Win32.RegistryView]::$($snapshot.View))
  $key=$base.OpenSubKey([string]$snapshot.KeyPath,$true)
  if (!$key -or $key.GetValueNames() -notcontains [string]$snapshot.ValueName) {exit 1}
  $kind=$key.GetValueKind([string]$snapshot.ValueName)
  if ($kind.ToString() -ne [string]$snapshot.ValueKind) {exit 1}
  $raw=$key.GetValue([string]$snapshot.ValueName,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
  if ($raw -isnot [string] -or $raw -cne [string]$snapshot.Data) {exit 1}
  $target=[string]$snapshot.Target
  if ($snapshot.Category -eq 'appPaths') {
    if ([Environment]::ExpandEnvironmentVariables($raw).Trim().Trim('"') -ine $target) {exit 1}
  } elseif ($snapshot.Category -eq 'startup') {
    $command=[Environment]::ExpandEnvironmentVariables($raw).Trim()
    $current=''
    if ($command -match '^"([^"]+)"') {$current=$Matches[1]}
    elseif ($command -match '^([A-Za-z]:\\.*?\.(?:exe|com|bat|cmd|ps1|vbs|js))(?=\s|$)') {$current=$Matches[1]}
    if ($current -ine $target) {exit 1}
  }
  [void](Get-Item -LiteralPath ([IO.Path]::GetPathRoot($target)) -Force -ErrorAction Stop)
  try { [void](Get-Item -LiteralPath $target -Force -ErrorAction Stop); exit 1 }
  catch [Management.Automation.ItemNotFoundException] {}
  if ($snapshot.View -eq 'Registry32') {
    $prefix=$env:SystemRoot.TrimEnd('\')+'\System32\'
    if ($target.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) {
      $alternate=$env:SystemRoot.TrimEnd('\')+'\SysWOW64\'+$target.Substring($prefix.Length)
      try { [void](Get-Item -LiteralPath $alternate -Force -ErrorAction Stop); exit 1 }
      catch [Management.Automation.ItemNotFoundException] {}
    }
  }
  $backupFolder=Join-Path $env:LOCALAPPDATA 'CleanWin\registry_backups'
  [void][IO.Directory]::CreateDirectory($backupFolder)
  $backupFile=Join-Path $backupFolder (([Guid]::NewGuid().ToString())+'.json')
  $snapshot | Add-Member -NotePropertyName BackedUpAtUtc -NotePropertyValue ([DateTime]::UtcNow.ToString('o'))
  $snapshot | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $backupFile -Encoding UTF8 -ErrorAction Stop
  $key.DeleteValue([string]$snapshot.ValueName,$true)
  $key.Flush()
  exit 0
} catch {Write-Error $_;exit 1}
finally {if($key){$key.Dispose()};if($base){$base.Dispose()}}
''';
    final response = await _run(script, const Duration(seconds: 20));
    if (response.success) _cache.invalidate(_cacheKey);
    return response.success;
  }
}
