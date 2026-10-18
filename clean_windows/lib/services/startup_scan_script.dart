/// Read-only discovery. Each source records its exact identity, not just a name.
const startupScanScript = r'''
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$items = New-Object System.Collections.ArrayList
$warnings = New-Object System.Collections.ArrayList
function Warn([string]$source) { [void]$warnings.Add($source) }
function Add-Entry($entry) { [void]$items.Add([PSCustomObject]$entry) }
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
    foreach ($leaf in @('Run','RunOnce','Policies')) {
      $path = 'Software\Microsoft\Windows\CurrentVersion\' + $leaf
      if ($leaf -eq 'Policies') { $path = 'Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run' }
      $base = $null; $key = $null
      try {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
          [Microsoft.Win32.RegistryHive]::$hive, [Microsoft.Win32.RegistryView]::$view)
        foreach ($disabled in @($false,$true)) {
          $readPath = $path
          if ($disabled) { $readPath += '\CleanWinDisabled' }
          $key = $base.OpenSubKey($readPath)
          if ($null -eq $key) { continue }
          foreach ($name in $key.GetValueNames()) {
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
              CanToggle=($leaf -ne 'Policies' -and $approved -eq $true)
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

# COM enumeration includes hidden tasks and walks every task folder.
function Read-Tasks($folder) {
  try {
    foreach ($task in $folder.GetTasks(1)) {
      try {
        $triggers = @($task.Definition.Triggers | Where-Object { $_.Type -in @(8,9) })
        if ($triggers.Count -eq 0) { continue }
        $actions = @($task.Definition.Actions | ForEach-Object {
          if ($_.Type -eq 0) { '"' + $_.Path + '" ' + $_.Arguments }
          else { 'COM handler: ' + $_.ClassId }
        })
        $enabledTriggers = @($triggers | Where-Object {$_.Enabled}).Count -gt 0
        Add-Entry @{
          Name=$task.Name; Command=($actions -join ' ; '); Location='ScheduledTask'; Group='task'
          Enabled=($task.Enabled -and $enabledTriggers); StateKnown=$true; CanToggle=$false
          SourceFile=$task.Path; Publisher=$task.Definition.RegistrationInfo.Author
          Detail=($task.Path + ' / ' + (@($triggers | ForEach-Object {if($_.Type -eq 8){'开机'}else{'登录'}}) -join '、'))
        }
      } catch { Warn ('Task/' + $task.Path) }
    }
  } catch { Warn ('Tasks/' + $folder.Path) }
  try { foreach ($child in $folder.GetFolders(0)) { Read-Tasks $child } }
  catch { Warn ('TaskFolders/' + $folder.Path) }
}
try {
  $scheduler = New-Object -ComObject Schedule.Service
  $scheduler.Connect()
  Read-Tasks ($scheduler.GetFolder('\'))
  [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($scheduler)
} catch { Warn 'ScheduledTasks' }

try {
  foreach ($service in Get-CimInstance Win32_Service -Filter "StartMode = 'Auto'" -ErrorAction Stop) {
    Add-Entry @{
      Name=$service.DisplayName; Command=$service.PathName; Location='Service'; Group='service'
      Enabled=$true; StateKnown=$true; CanToggle=$false; SourceFile=$service.Name
      Detail=($service.Name + ' / 自动启动' + $(if($service.DelayedAutoStart){'（延迟）'}else{''}) + ' / ' + $service.State)
    }
  }
} catch { Warn 'AutomaticServices' }

# A manifest declaration does not establish the user's current startup state.
try {
  foreach ($package in Get-AppxPackage -ErrorAction Stop) {
    try {
      $manifest = Get-AppxPackageManifest -Package $package.PackageFullName -ErrorAction Stop
      foreach ($extension in $manifest.SelectNodes("//*[local-name()='Extension' and @Category='windows.startupTask']")) {
        foreach ($task in $extension.SelectNodes(".//*[local-name()='StartupTask']")) {
          Add-Entry @{
            Name=$package.Name; Command=([string]$extension.Executable); Location='PackagedApp'; Group='package'
            Enabled=$false; StateKnown=$false; CanToggle=$false; SourceFile=($package.PackageFamilyName + '/' + $task.TaskId)
            Publisher=$package.Publisher; Detail=($task.TaskId + ' / 已声明，启用状态请在 Windows 启动应用中查看')
          }
        }
      }
    } catch { Warn ('Package/' + $package.Name) }
  }
} catch { Warn 'PackagedStartupApps' }

foreach ($value in @('Shell','Userinit')) {
  try {
    $key = Get-Item -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction Stop
    $command = [string]$key.GetValue($value)
    if ($command) {
      Add-Entry @{Name=('Winlogon / ' + $value); Command=$command; Location='Winlogon'; Group='system'; Enabled=$true; StateKnown=$true; CanToggle=$false; SourceFile=$value; Detail='系统登录组件 / 只读'}
    }
  } catch { Warn ('Winlogon/' + $value) }
}
@{Items=@($items.ToArray()); Warnings=@($warnings.ToArray() | Select-Object -Unique)} | ConvertTo-Json -Depth 6 -Compress
''';
