# Checks the application EXE, not the self-elevating Inno Setup loader.
param(
  [Parameter(Mandatory = $true)]
  [string]$ExecutablePath
)
$ErrorActionPreference = 'Stop'
$executable = (Resolve-Path -LiteralPath $ExecutablePath).Path
if (-not ('CleanWin.ManifestResource' -as [type])) {
  Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace CleanWin {
  public static class ManifestResource {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern IntPtr LoadLibraryEx(string path, IntPtr file, uint flags);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern IntPtr FindResource(IntPtr module, IntPtr name, IntPtr type);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr LoadResource(IntPtr module, IntPtr resource);
    [DllImport("kernel32.dll")]
    public static extern IntPtr LockResource(IntPtr resource);
    [DllImport("kernel32.dll")]
    public static extern uint SizeofResource(IntPtr module, IntPtr resource);
    [DllImport("kernel32.dll")]
    public static extern bool FreeLibrary(IntPtr module);
  }
}
"@
}
# LOAD_LIBRARY_AS_DATAFILE | LOAD_LIBRARY_AS_IMAGE_RESOURCE: never execute the binary.
$module = [CleanWin.ManifestResource]::LoadLibraryEx($executable, [IntPtr]::Zero, 0x22)
if ($module -eq [IntPtr]::Zero) { throw '无法作为资源文件读取 EXE。' }
try {
  $resource = [CleanWin.ManifestResource]::FindResource($module, [IntPtr]1, [IntPtr]24)
  if ($resource -eq [IntPtr]::Zero) { throw 'EXE 缺少嵌入式应用清单。' }
  $size = [CleanWin.ManifestResource]::SizeofResource($module, $resource)
  $loaded = [CleanWin.ManifestResource]::LoadResource($module, $resource)
  $pointer = [CleanWin.ManifestResource]::LockResource($loaded)
  if ($size -eq 0 -or $pointer -eq [IntPtr]::Zero) { throw '无法读取 EXE 清单。' }
  $bytes = New-Object byte[] $size
  [Runtime.InteropServices.Marshal]::Copy($pointer, $bytes, 0, [int]$size)
  [xml]$manifest = [Text.Encoding]::UTF8.GetString($bytes).Trim([char]0, [char]0xFEFF)
  $level = $manifest.SelectSingleNode("//*[local-name()='requestedExecutionLevel']")
  if ($null -eq $level -or $level.level -ne 'requireAdministrator' -or $level.uiAccess -ne 'false') {
    throw 'EXE 必须嵌入 requireAdministrator / uiAccess=false 清单，请重新构建。'
  }
  Write-Host "已验证管理员清单：$executable"
} finally {
  [void][CleanWin.ManifestResource]::FreeLibrary($module)
}
