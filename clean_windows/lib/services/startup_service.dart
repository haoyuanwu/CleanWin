import 'dart:convert';

import 'module_cache.dart';
import 'process_utils.dart';
import 'startup_scan_script.dart';

class StartupItem {
  StartupItem({
    required this.name,
    required this.command,
    required this.location,
    required this.enabled,
    this.publisher,
    this.group = 'registry',
    this.detail = '',
    this.stateKnown = true,
    this.canToggle = false,
    this.hive = '',
    this.view = '',
    this.key = '',
    this.valueName = '',
    this.sourceFile = '',
    this.disabled = false,
  });

  final String name, command, location, group, detail;
  final String hive, view, key, valueName, sourceFile;
  final String? publisher;
  final bool stateKnown, canToggle, disabled;
  bool enabled;

  String get id => '$location|$hive|$view|$key|$valueName|$sourceFile|$disabled'
      .toLowerCase();
  String get locationLabel => detail.isNotEmpty ? detail : location;
  String get groupLabel => switch (group) {
    'registry' => '注册表',
    'folder' => '启动文件夹',
    'task' => '计划任务',
    'service' => '自动服务',
    'package' => '商店应用',
    _ => '系统登录',
  };
  String get shortCommand =>
      command.length <= 80 ? command : '${command.substring(0, 77)}…';

  factory StartupItem.fromJson(Map<String, dynamic> json) => StartupItem(
    name: '${json['Name'] ?? ''}',
    command: '${json['Command'] ?? ''}',
    location: '${json['Location'] ?? ''}',
    enabled: json['Enabled'] == true,
    publisher: json['Publisher']?.toString(),
    group: '${json['Group'] ?? 'registry'}',
    detail: '${json['Detail'] ?? ''}',
    stateKnown: json['StateKnown'] != false,
    canToggle: json['CanToggle'] == true,
    disabled: json['Disabled'] == true,
    hive: '${json['Hive'] ?? ''}',
    view: '${json['View'] ?? ''}',
    key: '${json['Key'] ?? ''}',
    valueName: '${json['ValueName'] ?? ''}',
    sourceFile: '${json['SourceFile'] ?? ''}',
  );

  Map<String, dynamic> toJson() => {
    'Name': name,
    'Command': command,
    'Location': location,
    'Enabled': enabled,
    'Publisher': publisher,
    'Group': group,
    'Detail': detail,
    'StateKnown': stateKnown,
    'CanToggle': canToggle,
    'Disabled': disabled,
    'Hive': hive,
    'View': view,
    'Key': key,
    'ValueName': valueName,
    'SourceFile': sourceFile,
  };
}

class StartupService {
  StartupService({PowerShellRunner? powerShellRunner, ModuleCache? cache})
    : _run = powerShellRunner ?? runPowerShell,
      _cache = cache ?? AppCache.startup;
  final PowerShellRunner _run;
  final ModuleCache _cache;
  List<String> warnings = [];
  static const _cacheKey = 'startup_sources_v3';

  Future<List<StartupItem>> list({bool force = false}) async {
    Map<String, dynamic>? data;
    if (!force) data = _cache.getMap(_cacheKey);
    if (data == null) {
      final result = await _run(startupScanScript, const Duration(seconds: 90));
      if (!result.success) throw Exception('启动项扫描失败：${result.stderr}');
      if (result.stdout.trim().isEmpty && ProcessUtils.debugSkip) return [];
      final parsed = jsonDecode(result.stdout);
      if (parsed is! Map ||
          parsed['Items'] is! List ||
          parsed['Warnings'] is! List) {
        throw const FormatException('启动项结果格式不完整');
      }
      data = Map<String, dynamic>.from(parsed);
      _cache.set(_cacheKey, data);
    }
    final nextWarnings = (data['Warnings'] as List)
        .map((value) => value.toString())
        .toList();
    final seen = <String>{};
    final items =
        (data['Items'] as List)
            .whereType<Map>()
            .map((row) => StartupItem.fromJson(Map<String, dynamic>.from(row)))
            .where((item) => item.name.isNotEmpty && seen.add(item.id))
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    warnings = nextWarnings;
    return items;
  }

  /// Windows runs all Run value names; a .disabled suffix does not disable them.
  /// Move reviewed values to a non-executable subkey, preserving their data type.
  Future<bool> setEnabled(StartupItem item, bool enabled) async {
    if (!item.canToggle || !item.stateKnown || item.enabled == enabled) {
      return false;
    }
    if (item.group == 'registry') {
      const keys = {
        r'Software\Microsoft\Windows\CurrentVersion\Run',
        r'Software\Microsoft\Windows\CurrentVersion\RunOnce',
      };
      if (item.location != 'Registry' ||
          !keys.contains(item.key) ||
          !{'CurrentUser', 'LocalMachine'}.contains(item.hive) ||
          !{'Registry32', 'Registry64'}.contains(item.view) ||
          item.valueName.isEmpty) {
        return false;
      }
    } else if (item.group != 'folder' ||
        !item.location.startsWith('StartupFolder-') ||
        item.sourceFile.isEmpty) {
      return false;
    }
    final payload = {...item.toJson(), 'Enable': enabled};
    final result = await _run(
      _operation(payload, remove: false),
      const Duration(seconds: 20),
    );
    if (result.success) _cache.invalidate(_cacheKey);
    return result.success;
  }

  Future<bool> removeFile(StartupItem item) async {
    if (item.group != 'folder' ||
        !item.location.startsWith('StartupFolder-') ||
        item.sourceFile.isEmpty) {
      return false;
    }
    final result = await _run(
      _operation(item.toJson(), remove: true),
      const Duration(seconds: 20),
    );
    if (result.success) _cache.invalidate(_cacheKey);
    return result.success;
  }

  String _operation(Map<String, dynamic> payload, {required bool remove}) {
    final encoded = base64Encode(utf8.encode(jsonEncode(payload)));
    return "\$data = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encoded')) | ConvertFrom-Json\n"
        "\$remove = ${remove ? '\$true' : '\$false'}\n"
        r'''
$ErrorActionPreference = 'Stop'
try {
  if ($data.Group -eq 'registry') {
    $base = $null; $source = $null; $target = $null
    try {
      $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::$($data.Hive), [Microsoft.Win32.RegistryView]::$($data.View))
      $from = [string]$data.Key; $to = $from + '\CleanWinDisabled'
      if ($data.Enable) { $from = $to; $to = [string]$data.Key }
      $source = $base.OpenSubKey($from, $true)
      if (!$source -or $source.GetValueNames() -notcontains [string]$data.ValueName) {exit 1}
      $kind = $source.GetValueKind([string]$data.ValueName)
      if ($kind -notin @([Microsoft.Win32.RegistryValueKind]::String,[Microsoft.Win32.RegistryValueKind]::ExpandString)) {exit 1}
      $value = $source.GetValue([string]$data.ValueName, '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
      if ([string]$value -cne [string]$data.Command) {exit 1}
      $target = $base.CreateSubKey($to, $true)
      if ($target.GetValueNames() -contains [string]$data.ValueName) {exit 1}
      $target.SetValue([string]$data.ValueName, $value, $kind)
      $target.Flush()
      try { $source.DeleteValue([string]$data.ValueName, $true) }
      catch { $target.DeleteValue([string]$data.ValueName, $false); throw }
      $source.Flush()
    } finally {
      if($target){$target.Dispose()}; if($source){$source.Dispose()}; if($base){$base.Dispose()}
    }
  } else {
    $file = [IO.Path]::GetFullPath([string]$data.SourceFile)
    $folder = [Environment]::GetFolderPath('Startup')
    if ($data.Location -eq 'StartupFolder-Common') {$folder = [Environment]::GetFolderPath('CommonStartup')}
    if ([IO.Path]::GetDirectoryName($file).TrimEnd('\') -ine $folder.TrimEnd('\')) {exit 1}
    if (!(Test-Path -LiteralPath $file -PathType Leaf)) {exit 1}
    if ($remove) { Remove-Item -LiteralPath $file -Force -ErrorAction Stop }
    else {
      $target = $file + '.disabled'
      if ($data.Enable) {
        if (!$file.EndsWith('.disabled', [StringComparison]::OrdinalIgnoreCase)) {exit 1}
        $target = $file.Substring(0, $file.Length - 9)
      }
      if (Test-Path -LiteralPath $target) {exit 1}
      Rename-Item -LiteralPath $file -NewName ([IO.Path]::GetFileName($target)) -ErrorAction Stop
    }
  }
  exit 0
} catch { Write-Error $_; exit 1 }
''';
  }
}
