const registryTargetScript = r'''
function Resolve-CleanupTarget([string]$category,[string]$raw,[string]$name) {
  $text=[Environment]::ExpandEnvironmentVariables($raw).Trim()
  if($category -in @('startup','applications','contextMenu')) {
    if($text -match '^"([^"]+)"'){return $Matches[1]}
    if($text -match '^([A-Za-z]:\\.*?\.(?:exe|com|bat|cmd|ps1|vbs|js))(?=\s|$)'){return $Matches[1]}
    return ''
  }
  if($category -eq 'mui') {
    if($name -match '^([A-Za-z]:\\.+?\.exe)(?:\.[^\\]+)?$'){return $Matches[1]}
    return ''
  }
  if($category -eq 'sharedDll'){return $name}
  $text=$text.Trim('"')
  if($category -eq 'fonts' -and $text -notmatch '^[A-Za-z]:\\') {
    if($text -notmatch '^[^\\/:]+\.(ttf|otf|ttc|fon)$'){return ''}
    return [IO.Path]::Combine($env:SystemRoot,'Fonts',$text)
  }
  return $text
}
function Test-CleanupExtension([string]$category,[string]$target) {
  if($category -eq 'fonts'){return $target -match '^[A-Za-z]:\\.+\.(ttf|otf|ttc|fon)$'}
  if($category -eq 'sharedDll'){return $target -match '^[A-Za-z]:\\.+\.(dll|ocx)$'}
  return $target -match '^[A-Za-z]:\\.+\.(exe|com|bat|cmd|ps1|vbs|js)$'
}
function Test-FontAlternateMissing([string]$raw) {
  $text=[Environment]::ExpandEnvironmentVariables($raw).Trim().Trim('"')
  if($text -match '^[A-Za-z]:\\'){return $true}
  if($text -notmatch '^[^\\/:]+\.(ttf|otf|ttc|fon)$'){return $false}
  $alternate=[IO.Path]::Combine($env:LOCALAPPDATA,'Microsoft','Windows','Fonts',$text)
  try { [void](Get-Item -LiteralPath $alternate -Force -ErrorAction Stop); return $false }
  catch [Management.Automation.ItemNotFoundException] { return $true }
  catch { return $false }
}
''';
