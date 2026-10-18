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

# 3) 关闭占用 exe 的进程，避免链接失败
Get-Process clean_windows -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 300

# 4) 进入项目目录运行
Set-Location $PSScriptRoot
flutter run -d windows @args
