param(
  [string]$BundlePath,
  [string]$IsccPath,
  [string]$AppVersion
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $BundlePath) { $BundlePath = Join-Path $projectRoot 'build\windows\x64\runner\Release' }
$bundle = (Resolve-Path -LiteralPath $BundlePath).Path
foreach ($relative in @('clean_windows.exe', 'flutter_windows.dll', 'data\flutter_assets', 'data\icudtl.dat', 'data\app.so')) {
  if (-not (Test-Path -LiteralPath (Join-Path $bundle $relative))) {
    throw "Release 文件不完整：$relative。请先构建 Windows Release。"
  }
}
& (Join-Path $PSScriptRoot 'Test-AdminManifest.ps1') -ExecutablePath (Join-Path $bundle 'clean_windows.exe')
if (-not $AppVersion) {
  $versionLine = Select-String -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') -Pattern '^version:\s*([^+\s]+)' | Select-Object -First 1
  if (-not $versionLine) { throw '无法读取项目版本。' }
  $AppVersion = $versionLine.Matches[0].Groups[1].Value
}
if ($AppVersion -notmatch '^\d+\.\d+\.\d+(\.\d+)?$') { throw '版本号必须为数字版本，例如 1.0.0。' }
if (-not $IsccPath) {
  $compiler = Get-Command ISCC.exe -ErrorAction SilentlyContinue
  if ($compiler) { $IsccPath = $compiler.Source }
  $candidates = @(
    'C:\Program Files\Inno Setup 7\ISCC.exe',
    'C:\Program Files (x86)\Inno Setup 7\ISCC.exe',
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 6\ISCC.exe'
  )
  # Also support custom installation directories recorded by the installer.
  $uninstallRoots = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
  )
  foreach ($installation in (Get-ItemProperty -Path $uninstallRoots -ErrorAction SilentlyContinue |
      Where-Object { $_.DisplayName -match '^Inno Setup' -and $_.InstallLocation })) {
    $candidates += Join-Path $installation.InstallLocation 'ISCC.exe'
  }
  foreach ($candidate in $candidates) {
    if (-not $IsccPath -and (Test-Path -LiteralPath $candidate)) { $IsccPath = $candidate }
  }
}
if (-not $IsccPath -or -not (Test-Path -LiteralPath $IsccPath)) {
  throw '未找到 Inno Setup 6.3+ 的 ISCC.exe，请安装编译器或通过 -IsccPath 指定。'
}
$output = Join-Path $projectRoot 'dist'
& $IsccPath "/DBundleDir=$bundle" "/DAppVersion=$AppVersion" "/DOutputDir=$output" (Join-Path $projectRoot 'packaging\windows\cleanwin.iss')
if ($LASTEXITCODE -ne 0) { throw "安装包编译失败：$LASTEXITCODE" }
Write-Host "安装包已生成：$output"
