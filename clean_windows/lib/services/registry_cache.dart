import 'dart:convert';

import '../models/clean_models.dart';

/// Registry cleanup is restricted to individual values captured in the preview.
class RegistryCache {
  static const scanScript = r'''
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$out = @()
$muiPaths = @(
  'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache',
  'HKCU:\Software\Microsoft\Windows\ShellNoRoam\MUICache'
)
foreach ($path in $muiPaths) {
  if (-not (Test-Path -LiteralPath $path)) { continue }
  $key = Get-Item -LiteralPath $path
  foreach ($name in $key.GetValueNames()) {
    if ($name -notmatch '^([A-Za-z]:\\.+?\.exe)(?:\.[^\\]+)?$') { continue }
    $exe = $Matches[1]
    if (-not [IO.Directory]::Exists([IO.Path]::GetPathRoot($exe))) { continue }
    if (Test-Path -LiteralPath $exe) { continue }
    $value = $key.GetValue($name)
    if ($value -isnot [string]) { continue }
    $out += [PSCustomObject]@{ Name='失效 MUI 缓存'; Path=$path; Kind='MuiCache'; ValueName=$name; Value=$value; Executable=$exe }
  }
}
$appPaths = @(
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths',
  'HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths',
  'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths'
)
foreach ($root in $appPaths) {
  if (-not (Test-Path -LiteralPath $root)) { continue }
  foreach ($key in Get-ChildItem -LiteralPath $root) {
    $raw = $key.GetValue('')
    if ($raw -isnot [string]) { continue }
    $exe = [Environment]::ExpandEnvironmentVariables($raw).Trim().Trim('"')
    if ($exe -notmatch '^[A-Za-z]:\\.+\.exe$') { continue }
    if (-not [IO.Directory]::Exists([IO.Path]::GetPathRoot($exe))) { continue }
    if (Test-Path -LiteralPath $exe) { continue }
    $path = $root + '\' + $key.PSChildName
    $out += [PSCustomObject]@{ Name='失效程序路径'; Path=$path; Kind='AppPaths'; ValueName=''; Value=$raw; Executable=$exe }
  }
}
ConvertTo-Json -InputObject @($out) -Compress -Depth 4
''';

  static bool accepts(CleanItem item) {
    final path = item.path.toLowerCase();
    if (item.registryValueName == null ||
        item.registryValueData == null ||
        item.registryExecutable == null) {
      return false;
    }
    if (!RegExp(
      r'^[A-Za-z]:\\.+\.exe$',
      caseSensitive: false,
    ).hasMatch(item.registryExecutable!)) {
      return false;
    }
    if (item.note == 'MuiCache') {
      final match = RegExp(
        r'^([A-Za-z]:\\.+?\.exe)(?:\.[^\\]+)?$',
        caseSensitive: false,
      ).firstMatch(item.registryValueName!);
      if (match == null ||
          match.group(1)!.toLowerCase() !=
              item.registryExecutable!.toLowerCase()) {
        return false;
      }
      return path ==
              r'hkcu:\software\classes\local settings\software\microsoft\windows\shell\muicache' ||
          path == r'hkcu:\software\microsoft\windows\shellnoroam\muicache';
    }
    if (item.note != 'AppPaths' || item.registryValueName != '') return false;
    return [
      r'hkcu:\software\microsoft\windows\currentversion\app paths\',
      r'hklm:\software\microsoft\windows\currentversion\app paths\',
      r'hklm:\software\wow6432node\microsoft\windows\currentversion\app paths\',
    ].any(
      (root) =>
          path.startsWith(root) &&
          path.substring(root.length).isNotEmpty &&
          !path.substring(root.length).contains('\\'),
    );
  }

  static String cleanupScript(CleanItem item) {
    final data = base64Encode(
      utf8.encode(
        jsonEncode({
          'Path': item.path,
          'ValueName': item.registryValueName,
          'Value': item.registryValueData,
          'Executable': item.registryExecutable,
        }),
      ),
    );
    return "\$snapshot = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$data')) | ConvertFrom-Json\n"
        r'''
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $snapshot.Path)) { exit 0 }
$baseKey = if ([string]$snapshot.Path -like 'HKCU:\*') {
  [Microsoft.Win32.Registry]::CurrentUser
} else { [Microsoft.Win32.Registry]::LocalMachine }
$key = $baseKey.OpenSubKey(([string]$snapshot.Path).Substring(6), $true)
if ($null -eq $key) { exit 0 }
try {
if ($key.GetValueNames() -notcontains [string]$snapshot.ValueName) { exit 0 }
$current = $key.GetValue([string]$snapshot.ValueName)
if ($current -isnot [string] -or $current -cne [string]$snapshot.Value) {
  throw '扫描后注册表值已改变，请重新扫描'
}
if (-not [IO.Directory]::Exists([IO.Path]::GetPathRoot($snapshot.Executable))) {
  throw '目标磁盘未就绪，已跳过'
}
if (Test-Path -LiteralPath $snapshot.Executable) {
  throw '目标程序已恢复，已跳过'
}
$key.DeleteValue([string]$snapshot.ValueName, $false)
} finally { $key.Dispose() }
''';
  }
}
