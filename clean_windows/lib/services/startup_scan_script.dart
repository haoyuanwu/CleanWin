/// Read-only discovery. Each source records its exact identity, not just a name.
const startupScanScript = r'''
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$items = New-Object System.Collections.ArrayList
$warnings = New-Object System.Collections.ArrayList
function Warn([string]$source) { [void]$warnings.Add($source) }
function Add-Entry($entry) { if ($entry.CanToggle -and $entry.StateKnown) { [void]$items.Add([PSCustomObject]$entry) } }
function Approval([string]$hive, [string]$bucket, [string]$name) {
  $root = $null; $key = $null
  try {
    $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
      [Microsoft.Win32.RegistryHive]::$hive, [Microsoft.Win32.RegistryView]::Default)
    $key = $root.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\' + $bucket)
    if ($null -eq $key) { return $true }
    $data = $key.GetValue($name)
    if ($data -is [byte[]] -and $data.Length -gt 0) {
      if ($data[0] -in @(3,7)) { return $false }
      if ($data[0] -in @(2,6)) { return $true }
      Warn ('StartupApproved/UnknownState/' + $hive + '/' + $name)
      return $null
    } elseif ($null -ne $data) {
      Warn ('StartupApproved/UnknownData/' + $hive + '/' + $name)
      return $null
    }
  } catch { Warn ('StartupApproved/' + $hive + '/' + $bucket); return $null }
  finally { if ($key) {$key.Dispose()}; if ($root) {$root.Dispose()} }
  return $true
}
$views = @('Registry32')
if ([Environment]::Is64BitOperatingSystem) { $views = @('Registry64','Registry32') }
foreach ($hive in @('CurrentUser','LocalMachine')) {
  foreach ($view in $views) {
    foreach ($leaf in @('Run','RunOnce')) {
      $path = 'Software\Microsoft\Windows\CurrentVersion\' + $leaf
      $base = $null; $key = $null
      try {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
          [Microsoft.Win32.RegistryHive]::$hive, [Microsoft.Win32.RegistryView]::$view)
        foreach ($disabled in @($false,$true)) {
          $readPath = $path
          if ($disabled) { $readPath += '\CleanWinDisabled' }
          $key = $base.OpenSubKey($readPath)
          if ($null -eq $key) { continue }
          $writeSource = $null; $writeTarget = $null; $writeParent = $null
          $targetPath = $path + '\CleanWinDisabled'; if ($disabled) {$targetPath = $path}
          try {
            $writeSource = $base.OpenSubKey($readPath, $true)
            $writeTarget = $base.OpenSubKey($targetPath, $true)
            $writeParent = $base.OpenSubKey($path, $true)
            if (!$writeSource -or !$writeParent) {continue}
            $targetNames = @(); if ($writeTarget) {$targetNames = @($writeTarget.GetValueNames())}
          } catch { continue }
          finally {
            if($writeSource){$writeSource.Dispose()}; if($writeTarget){$writeTarget.Dispose()}; if($writeParent){$writeParent.Dispose()}
          }
          foreach ($name in $key.GetValueNames()) {
            if ($targetNames -contains $name) {continue}
            if ([string]::IsNullOrEmpty($name)) { continue }
            if ($key.GetValueKind($name) -notin @([Microsoft.Win32.RegistryValueKind]::String,[Microsoft.Win32.RegistryValueKind]::ExpandString)) { continue }
            $command = [string]$key.GetValue($name, '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            if ([string]::IsNullOrWhiteSpace($command)) { continue }
            $approved = $true
            if ($leaf -eq 'Run') {
              $bucket = 'Run'; if ($view -eq 'Registry32' -and [Environment]::Is64BitOperatingSystem) {$bucket = 'Run32'}
              $approved = Approval $hive $bucket $name
            }
            Add-Entry @{
              Name=$name; Command=$command; Location='Registry'; Group='registry'
              Enabled=(!$disabled -and $approved -eq $true); StateKnown=($disabled -or $null -ne $approved)
              CanToggle=($approved -eq $true)
              Hive=$hive; View=$view; Key=$path; ValueName=$name; Disabled=$disabled
              Detail=($(if($hive -eq 'CurrentUser'){'当前用户'}else{'所有用户'}) + ' / ' + $view + ' / ' + $leaf + $(if(!$approved){' / Windows 已禁用'}else{''}))
            }
          }
          $key.Dispose(); $key = $null
        }
      } catch { Warn ('Registry/' + $hive + '/' + $view + '/' + $leaf) }
      finally { if($key){$key.Dispose()}; if($base){$base.Dispose()} }
    }
  }
}
$renameProbeReady = $false
try {
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class CleanWinStartupAccess {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  private static extern SafeFileHandle CreateFile(string path, uint access, uint share,
      IntPtr security, uint creation, uint flags, IntPtr template);
  public static bool CanRename(string file, string folder) {
    using (var source = CreateFile(file, 0x10000, 7, IntPtr.Zero, 3, 0x02000000, IntPtr.Zero))
    using (var parent = CreateFile(folder, 2, 7, IntPtr.Zero, 3, 0x02000000, IntPtr.Zero)) {
      return !source.IsInvalid && !parent.IsInvalid;
    }
  }
}
'@
  $renameProbeReady = $true
} catch { Warn 'StartupFolder/AccessProbe' }
$shell = $null
try { $shell = New-Object -ComObject WScript.Shell } catch { Warn 'Shortcut targets' }
$folders = @(
  @{Path=[Environment]::GetFolderPath('Startup'); Hive='CurrentUser'; Label='StartupFolder-User'},
  @{Path=[Environment]::GetFolderPath('CommonStartup'); Hive='LocalMachine'; Label='StartupFolder-Common'}
)
foreach ($folder in $folders) {
  try {
    if (!$folder.Path -or !(Test-Path -LiteralPath $folder.Path)) { continue }
    foreach ($file in Get-ChildItem -LiteralPath $folder.Path -Force -File -ErrorAction Stop) {
      if ($file.Name -ieq 'desktop.ini') { continue }
      $disabled = $file.Name.EndsWith('.disabled', [StringComparison]::OrdinalIgnoreCase)
      $approvalName = $file.Name
      if ($disabled) { $approvalName = $file.Name.Substring(0, $file.Name.Length - 9) }
      $target = $file.FullName + '.disabled'
      if ($disabled) {$target = $file.FullName.Substring(0, $file.FullName.Length - 9)}
      if (($file.Attributes -band ([IO.FileAttributes]::ReadOnly -bor [IO.FileAttributes]::ReparsePoint)) -ne 0 -or
          (Test-Path -LiteralPath $target) -or !$renameProbeReady -or
          ![CleanWinStartupAccess]::CanRename($file.FullName, $folder.Path)) {continue}
      $approved = Approval $folder.Hive 'StartupFolder' $approvalName
      $command = $file.FullName
      if ($file.Extension -ieq '.lnk' -and $shell) {
        try {
          $link = $shell.CreateShortcut($file.FullName)
          if ($link.TargetPath) { $command = '"' + $link.TargetPath + '" ' + $link.Arguments }
        } catch { Warn ('Shortcut/' + $file.FullName) }
      }
      Add-Entry @{
        Name=$file.BaseName; Command=$command; Location=$folder.Label; Group='folder'; SourceFile=$file.FullName
        Enabled=(!$disabled -and $approved -eq $true); StateKnown=($disabled -or $null -ne $approved); Disabled=$disabled
        CanToggle=($approved -eq $true); Detail=$file.FullName
      }
    }
  } catch { Warn ('StartupFolder/' + $folder.Label) }
}
if ($shell) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }

@{Items=@($items.ToArray()); Warnings=@($warnings.ToArray() | Select-Object -Unique)} | ConvertTo-Json -Depth 6 -Compress
''';
