#Requires -RunAsAdministrator

# CleanWin 本地运行脚本
# 修复：部分环境缺少 ProgramFiles(x86) 导致 flutter build/run 失败
# 以及 exe 被占用导致 LNK1104

$ErrorActionPreference = 'Stop'

# 1) 补全常见 Windows 环境变量
if (-not [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) {
  [Environment]::SetEnvironmentVariable('ProgramFiles(x86)', 'C:\Program Files (x86)', 'Process')
}
if (-not $env:ProgramFiles) {
  [Environment]::SetEnvironmentVariable('ProgramFiles', 'C:\Program Files', 'Process')
}
if (-not $env:ProgramW6432) {
  [Environment]::SetEnvironmentVariable('ProgramW6432', 'C:\Program Files', 'Process')
}

# 2) 确保 vswhere / VS Installer 在 PATH
$vsInstaller = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer'
if ((Test-Path $vsInstaller) -and ($env:PATH -notlike "*$vsInstaller*")) {
  $env:PATH = "$vsInstaller;$env:PATH"
}

# 3) 项目迁移后 CMake 缓存中的绝对路径必须重新生成。
$projectRoot = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
$windowsBuild = Join-Path $projectRoot 'build\windows'
$cmakeCache = Join-Path $windowsBuild 'x64\CMakeCache.txt'
if (Test-Path -LiteralPath $cmakeCache) {
  $sourceEntry = Select-String -LiteralPath $cmakeCache -Pattern '^CMAKE_HOME_DIRECTORY:INTERNAL=(.+)$' | Select-Object -First 1
  $expectedSource = [IO.Path]::GetFullPath((Join-Path $projectRoot 'windows')).Replace('\', '/').TrimEnd('/')
  if ($sourceEntry -and $sourceEntry.Matches[0].Groups[1].Value.TrimEnd('/') -ine $expectedSource) {
    $buildBackup = [IO.Path]::GetFullPath((Join-Path $projectRoot ('build\windows.before-move-' + [Guid]::NewGuid().ToString('N'))))
    $buildSource = [IO.Path]::GetFullPath($windowsBuild)
    if (-not $buildSource.StartsWith($projectRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
        -not $buildBackup.StartsWith($projectRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
        ((Get-Item -LiteralPath $buildSource).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
      throw '构建目录不在当前项目内或包含链接，无法自动重建。'
    }
    Move-Item -LiteralPath $buildSource -Destination $buildBackup
    Write-Host '已备份旧路径的构建缓存，将为当前项目重新生成。'
  }
}

# 4) 命令不在 PATH 时，复用项目记录的 Flutter SDK。
$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
$flutterLauncher = if ($flutterCommand) { $flutterCommand.Source } else { $null }
if (-not $flutterLauncher) {
  $packageConfig = Join-Path $projectRoot '.dart_tool\package_config.json'
  if (Test-Path -LiteralPath $packageConfig) {
    $flutterRootUri = (Get-Content -LiteralPath $packageConfig -Raw | ConvertFrom-Json).flutterRoot
    if ($flutterRootUri) {
      $flutterLauncher = Join-Path ([Uri]$flutterRootUri).LocalPath 'bin\flutter.bat'
    }
  }
}
if (-not $flutterLauncher -or -not (Test-Path -LiteralPath $flutterLauncher)) {
  throw '未找到 Flutter SDK，请先配置 Flutter 或在项目中运行 flutter pub get。'
}

# 5) 关闭占用 exe 的进程，避免链接失败
Get-Process clean_windows -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 300

# 6) 进入项目目录运行
Set-Location $PSScriptRoot
& $flutterLauncher run -d windows @args
exit $LASTEXITCODE
