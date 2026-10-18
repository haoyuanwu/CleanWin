/// Discover cleanable values in explicit roots. Discovery never modifies the registry.
const registryAuditScript = r'''
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$issues = New-Object Collections.ArrayList
$coverage = New-Object Collections.ArrayList
$warnings = New-Object Collections.ArrayList
$fileCache = @{}
function Warn([string]$path) {
  $script:scope.Status = 'partial'
  [void]$warnings.Add($path)
}
function Open-Key([string]$path) {
  try {
    $key = $script:base.OpenSubKey($path)
    if ($key) { $script:scope.Keys++ }
    return $key
  } catch { Warn ($script:scope.Hive + '\' + $path); return $null }
}
function Read-Value($key, [string]$name) {
  if ($key.GetValueNames() -notcontains $name) {return $null}
  $script:scope.Checked++
  return $key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
}
function File-State([string]$path) {
  $id = $path.ToLowerInvariant()
  if ($fileCache.ContainsKey($id)) {return $fileCache[$id]}
  if ($path.Length -lt 3 -or $path[1] -ne ':') {return 'unknown'}
  $drive = [IO.Path]::GetPathRoot($path)
  try { [void](Get-Item -LiteralPath $drive -Force -ErrorAction Stop) }
  catch { $fileCache[$id] = 'unknown'; return 'unknown' }
  try {
    [void](Get-Item -LiteralPath $path -Force -ErrorAction Stop)
    $state = 'exists'
  } catch [Management.Automation.ItemNotFoundException] { $state = 'missing' }
  catch { $state = 'unknown' }
  $fileCache[$id] = $state
  return $state
}
function Target([string]$raw, [string]$mode) {
  $text = [Environment]::ExpandEnvironmentVariables($raw).Trim()
  if ($mode -eq 'command') {
    if ($text -match '^"([^"]+)"') {return $Matches[1]}
    if ($text -match '^([A-Za-z]:\\.*?\.(?:exe|com|bat|cmd|ps1|vbs|js))(?=\s|$)') {return $Matches[1]}
    return ''
  }
  $text = $text.Trim('"')
  if ($mode -eq 'typelib' -and $text -match '^(.+\.(?:dll|ocx|tlb|olb|exe))(?:\\\d+)?$') {return $Matches[1]}
  return $text
}
function Add-Record([string]$path, [string]$name, $data, [string]$valueKind,
                    [string]$target, [string]$detail, [bool]$allowDelete) {
  [void]$issues.Add([PSCustomObject]@{
    Title=($script:spec.Label + ': ' + $(if($name){$name}else{[IO.Path]::GetFileName($path)}))
    Detail=$detail; Hive=$script:scope.Hive; View=$script:scope.View; KeyPath=$path
    ValueName=$name; Severity=$(if($allowDelete){'warn'}else{'info'})
    Category=$script:spec.Kind; Data=$data; ValueKind=$valueKind
    Target=$target; CanDelete=$allowDelete
  })
}
function Check-Value([string]$path, $key, [string]$name, [string]$mode, [string]$override='') {
  if ($key.GetValueNames() -notcontains $name) {return}
  $valueKind = $key.GetValueKind($name).ToString()
  if ($valueKind -notin @('String','ExpandString')) {return}
  $raw = Read-Value $key $name
  if ($null -eq $raw) {return}
  $text = [string]$raw
  if ($override) {$text = $override}
  $target = Target $text $mode
  if (!$target -or $target -notmatch '^[A-Za-z]:\\.+\.(exe|com|bat|cmd|ps1|vbs|js)$') {$script:scope.Unverified++; return}
  if ($script:spec.Kind -in @('mui','appPaths') -and $target -notmatch '\.exe$') {return}
  $state = File-State $target
  if ($state -eq 'missing' -and $script:scope.View -eq 'Registry32') {
    $system32 = $env:SystemRoot.TrimEnd('\') + '\System32\'
    if ($target.StartsWith($system32,[StringComparison]::OrdinalIgnoreCase)) {
      $alternate = $env:SystemRoot.TrimEnd('\') + '\SysWOW64\' + $target.Substring($system32.Length)
      if ((File-State $alternate) -ne 'missing') { $state = 'unknown' }
    }
  }
  if ($state -eq 'unknown') { $script:scope.Unverified++; return }
  if ($state -ne 'missing') {return}
  $allow = $script:spec.Kind -in @('mui','appPaths','startup') -and $valueKind -in @('String','ExpandString')
  Add-Record $path $name $raw $valueKind $target ('目标未找到: ' + $target) $allow
}
function Scan-Key([string]$path, $key) {
  switch ($script:spec.Kind) {
    'startup' {
      foreach ($name in $key.GetValueNames()) {if ($name) {Check-Value $path $key $name 'command'}}
    }
    'mui' {
      foreach ($name in $key.GetValueNames()) {
        if ($name -match '^([A-Za-z]:\\.+?\.exe)(?:\.[^\\]+)?$') {Check-Value $path $key $name 'path' $Matches[1]}
      }
    }
    'appPaths' {
      foreach ($child in $key.GetSubKeyNames()) {
        $childPath = $path + '\' + $child; $entry = Open-Key $childPath
        if (!$entry) {continue}
        try {Check-Value $childPath $entry '' 'path'}
        catch {Warn $childPath} finally {$entry.Dispose()}
      }
    }
  }
}
$specs = @(
  @{Kind='startup';Label='失效启动命令';Path='Software\Microsoft\Windows\CurrentVersion\Run'},
  @{Kind='startup';Label='失效一次性启动命令';Path='Software\Microsoft\Windows\CurrentVersion\RunOnce'},
  @{Kind='appPaths';Label='失效程序路径';Path='Software\Microsoft\Windows\CurrentVersion\App Paths'},
  @{Kind='mui';Label='失效 MUI 缓存';Path='Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache';UserOnly=$true},
  @{Kind='mui';Label='失效旧版 MUI 缓存';Path='Software\Microsoft\Windows\ShellNoRoam\MUICache';UserOnly=$true}
)
$views = @('Registry32'); if ([Environment]::Is64BitOperatingSystem) {$views=@('Registry64','Registry32')}
foreach ($hive in @('CurrentUser','LocalMachine')) {
  foreach ($view in $views) {
    $script:base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::$hive,[Microsoft.Win32.RegistryView]::$view)
    try {
      foreach ($spec in $specs) {
        if ($spec.UserOnly -and $hive -ne 'CurrentUser') {continue}
        $script:spec = $spec
        $script:scope = @{Hive=$(if($hive -eq 'CurrentUser'){'HKCU'}else{'HKLM'});View=$view;Path=$spec.Path;Category=$spec.Kind;Status='ok';Keys=0;Checked=0;Unverified=0}
        $key = Open-Key $spec.Path
        if ($key) {
          try { Scan-Key $spec.Path $key } catch {Warn $spec.Path} finally {$key.Dispose()}
        } elseif ($script:scope.Status -eq 'ok') {$script:scope.Status='missing'}
        [void]$coverage.Add([PSCustomObject]$script:scope)
      }
    } finally {$script:base.Dispose()}
  }
}
@{Issues=@($issues.ToArray()); Coverage=@($coverage.ToArray()); Warnings=@($warnings.ToArray() | Select-Object -Unique)} | ConvertTo-Json -Compress -Depth 7
''';
