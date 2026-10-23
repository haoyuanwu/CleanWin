import 'startup_scan_script.dart';

// Local, read-only inspection. No DNS requests, pings or settings mutations.
const healthScriptPreamble = r'''
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$rows = New-Object System.Collections.ArrayList
function Add-Row([string]$id,[string]$label,[string]$value,[string]$status='info') {
  if ([string]::IsNullOrWhiteSpace($value)) { $value='无法读取'; $status='unavailable' }
  [void]$rows.Add(@{id=$id;label=$label;value=$value;status=$status})
}
function Read-Item([string]$id,[string]$label,[scriptblock]$query) {
  try { Add-Row $id $label ([string](& $query)) } catch { Add-Row $id $label '无法读取（权限或系统接口不可用）' 'unavailable' }
}
''';
const healthScriptEnd = r'''
ConvertTo-Json -InputObject @($rows.ToArray()) -Depth 5 -Compress
''';

const hardwareHealthScript = r'''
Read-Item 'cpu' '处理器' { (Get-CimInstance Win32_Processor -OperationTimeoutSec 4 | ForEach-Object { $_.Name.Trim() + ' / ' + $_.NumberOfCores + ' 核 ' + $_.NumberOfLogicalProcessors + ' 线程' }) -join "`n" }
Read-Item 'ram' '物理内存' { $cs=Get-CimInstance Win32_ComputerSystem -OperationTimeoutSec 4; '{0:N1} GB' -f ($cs.TotalPhysicalMemory/1GB) }
Read-Item 'board' '主板' { (Get-CimInstance Win32_BaseBoard -OperationTimeoutSec 4 | ForEach-Object { $_.Manufacturer + ' ' + $_.Product }) -join "`n" }
Read-Item 'gpu' '显卡' { (Get-CimInstance Win32_VideoController -OperationTimeoutSec 4 | ForEach-Object { $_.Name + ' / 驱动 ' + $_.DriverVersion }) -join "`n" }
Read-Item 'disk' '物理磁盘' { (Get-CimInstance Win32_DiskDrive -OperationTimeoutSec 4 | ForEach-Object { $_.Model + (' / {0:N0} GB' -f ($_.Size/1GB)) }) -join "`n" }
Read-Item 'nic' '网卡' { (Get-CimInstance Win32_NetworkAdapter -Filter 'PhysicalAdapter=True' -OperationTimeoutSec 4 | ForEach-Object { $_.Name }) -join "`n" }
Read-Item 'audio' '音频设备' { (Get-CimInstance Win32_SoundDevice -OperationTimeoutSec 4 | ForEach-Object { $_.Name }) -join "`n" }
Read-Item 'display' '显示器' { (Get-CimInstance Win32_DesktopMonitor -OperationTimeoutSec 4 | ForEach-Object { $_.Name }) -join "`n" }
Read-Item 'os' '操作系统' { $os=Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 4; $os.Caption + ' / ' + $os.Version + ' / ' + $os.OSArchitecture }
''';

const networkHealthScript = r'''
try {
  $profiles=@(Get-NetConnectionProfile -ErrorAction Stop)
  if ($profiles.Count -eq 0) { Add-Row 'connection' '系统连通状态' '未检测到网络连接' 'attention' }
  else {
    $internet=@($profiles | Where-Object { $_.IPv4Connectivity -eq 'Internet' -or $_.IPv6Connectivity -eq 'Internet' }).Count -gt 0
    $state='attention'; if($internet){$state='normal'}
    Add-Row 'connection' '系统连通状态' (($profiles | ForEach-Object { $_.InterfaceAlias + ' / IPv4: ' + $_.IPv4Connectivity + ' / IPv6: ' + $_.IPv6Connectivity }) -join "`n") $state
  }
} catch { Add-Row 'connection' '系统连通状态' '无法读取系统连通状态' 'unavailable' }
try {
  $adapters=@(Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=True' -OperationTimeoutSec 5)
  if($adapters.Count -eq 0){ Add-Row 'adapters' '网络配置' '未检测到启用 IP 的适配器' 'attention' }
  foreach($a in $adapters){
    $prefix='adapter_' + $a.Index
    Add-Row ($prefix+'_ip') $a.Description ('IP: ' + ($a.IPAddress -join ', ') + "`n子网: " + ($a.IPSubnet -join ', '))
    Add-Row ($prefix+'_gateway') '默认网关' $(if($a.DefaultIPGateway){$a.DefaultIPGateway -join ', '}else{'未设置（隧道或专用网络可能不需要）'})
    Add-Row ($prefix+'_dns') 'DNS 服务器' $(if($a.DNSServerSearchOrder){$a.DNSServerSearchOrder -join ', '}else{'系统未返回配置'})
    Add-Row ($prefix+'_dhcp') 'IP 获取方式' $(if($a.DHCPEnabled){'DHCP 自动获取'}else{'静态配置'})
  }
} catch { Add-Row 'adapters' '网络配置' '无法读取适配器配置' 'unavailable' }
try {
  $proxy=Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
  $text='手动代理未开启'; if($proxy.ProxyEnable -eq 1){$text='手动代理：' + $proxy.ProxyServer}
  if($proxy.AutoConfigURL){$text+="`n自动配置："+$proxy.AutoConfigURL}
  Add-Row 'proxy' '系统代理' $text
} catch { Add-Row 'proxy' '系统代理' '无法读取系统代理' 'unavailable' }
try {
  $envRows=@(); foreach($scope in @('User','Machine')){
    foreach($name in @('http_proxy','https_proxy','all_proxy','no_proxy')){
      $v=[Environment]::GetEnvironmentVariable($name,$scope)
      if($v){$envRows+=($scope + ' / ' + $name + ': ' + $v)}
    }
  }
  Add-Row 'proxy_env' '代理环境变量' $(if($envRows.Count){$envRows -join "`n"}else{'未配置'})
} catch { Add-Row 'proxy_env' '代理环境变量' '无法读取环境变量' 'unavailable' }
''';

const storageHealthScript = r'''
try {
  foreach($d in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -OperationTimeoutSec 5)){
    if(!$d.Size -or $d.Size -le 0){continue}
    $free=[double]$d.FreeSpace/[double]$d.Size*100
    $state='normal'; if($free -lt 10){$state='attention'}
    Add-Row ('drive_'+$d.DeviceID) ($d.DeviceID + ' 可用空间') ('{0:N1} / {1:N1} GB · {2:N0}% 可用' -f ($d.FreeSpace/1GB),($d.Size/1GB),$free) $state
  }
} catch { Add-Row 'drives' '磁盘空间' '无法读取磁盘空间' 'unavailable' }
Read-Item 'memory' '可用内存' { $os=Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 4; '{0:N1} / {1:N1} GB' -f ($os.FreePhysicalMemory/1MB),($os.TotalVisibleMemorySize/1MB) }
Read-Item 'recent' '最近文件快捷方式' {
  $root=[Environment]::GetFolderPath('Recent')
  if(!$root -or !(Test-Path -LiteralPath $root)){ '0 项' }
  else { $count=0; foreach($f in [IO.Directory]::EnumerateFiles($root,'*.lnk',[IO.SearchOption]::TopDirectoryOnly)){ $count++ }; [string]$count + ' 项（原文件保持不变）' }
}
''';

const preferencesHealthScript = r'''
Read-Item 'browser' '默认浏览器' { $v=Get-ItemPropertyValue -LiteralPath 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice' -Name ProgId -ErrorAction SilentlyContinue; if($v){$v}else{'由 Windows 默认应用管理'} }
Read-Item 'pdf' 'PDF 打开方式' { $v=Get-ItemPropertyValue -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf\UserChoice' -Name ProgId -ErrorAction SilentlyContinue; if($v){$v}else{'由 Windows 默认应用管理'} }
Read-Item 'taskbar' '任务栏搜索' { $v=Get-ItemPropertyValue -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name SearchboxTaskbarMode -ErrorAction SilentlyContinue; if($null -eq $v){'由系统管理'}else{switch([int]$v){0{'隐藏'}1{'搜索图标'}2{'搜索框'}default{'系统模式 '+$v}}} }
Read-Item 'lockscreen' '锁屏设置' { '壁纸、通知与超时可在 Windows 设置中调整' }
Read-Item 'notifications' '弹窗与通知' { '使用 Windows 通知设置按应用管理' }
''';

// Explicit user action only. Fixed target; no discovered URL is executed.
const connectivityHealthScript = r'''
$target='www.microsoft.com'
try {
  $task=[System.Net.Dns]::GetHostAddressesAsync($target)
  if(!$task.Wait(4000)){throw 'DNS timeout'}
  $addresses=@($task.Result | ForEach-Object {$_.IPAddressToString})
  if(!$addresses.Count){throw 'No addresses'}
  Add-Row 'probe_dns' '外网 DNS 解析' ($target + ': ' + ($addresses -join ', ')) 'normal'
} catch { Add-Row 'probe_dns' '外网 DNS 解析' '目标解析未成功，可能受 DNS、网络或访问策略影响' 'attention' }
$times=@();$ping=New-Object System.Net.NetworkInformation.Ping
try {
  for($i=0;$i -lt 3;$i++){
    try {
      $task=$ping.SendPingAsync($target,1000)
      if($task.Wait(1500) -and $task.Result.Status -eq [System.Net.NetworkInformation.IPStatus]::Success){ $times+=$task.Result.RoundtripTime }
    } catch {}
  }
} finally { $ping.Dispose() }
if($times.Count){
  Add-Row 'probe_latency' '目标响应延迟' (('{0:N0} ms' -f (($times | Measure-Object -Average).Average)) + ' / ' + $target) 'info'
} else { Add-Row 'probe_latency' '目标响应延迟' '未收到 ICMP 回复；服务器或防火墙可能屏蔽，不能据此判定断网' 'info' }
Add-Row 'probe_loss' '探测未响应比例' (('{0:N0}%' -f ((3-$times.Count)/3*100)) + ' / 共 3 次；仅代表此目标的 ICMP 探测') 'info'
''';

// Reuse the same manageable-item filter and permission checks as StartupPage.
final applicationsHealthScript =
    r'''
try {
  $snapshotJson = & {
''' +
    startupScanScript +
    r'''
  }
  $snapshot=$snapshotJson | ConvertFrom-Json
  $enabled=@($snapshot.Items | Where-Object {$_.Enabled}).Count
  $disabled=@($snapshot.Items | Where-Object {!$_.Enabled}).Count
  Add-Row 'startup' '可管理启动项' ([string]$enabled + ' 项开启 / ' + $disabled + ' 项关闭')
  if(@($snapshot.Warnings).Count -gt 0){ Add-Row 'startup_partial' '启动项读取范围' '部分来源未能读取，可在启动项中查看详情' 'unavailable' }
} catch { Add-Row 'startup' '可管理启动项' '无法读取，请到启动项页面重试' 'unavailable' }
try {
  $names=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  $partial=$false
  foreach($hive in @('CurrentUser','LocalMachine')){
    $views=@('Registry32');if([Environment]::Is64BitOperatingSystem){$views=@('Registry64','Registry32')}
    foreach($view in $views){
      $base=$null;$key=$null
      try {
        $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::$hive,[Microsoft.Win32.RegistryView]::$view)
        $key=$base.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Uninstall')
        if(!$key){continue}
        foreach($subName in $key.GetSubKeyNames()){
          $app=$null
          try {
            $app=$key.OpenSubKey($subName)
            if(!$app){$partial=$true;continue}
            $name=[string]$app.GetValue('DisplayName')
            if(!$name -or $app.GetValue('SystemComponent') -eq 1 -or $app.GetValue('ParentKeyName')){continue}
            $identity=$name+'|'+[string]$app.GetValue('Publisher')+'|'+[string]$app.GetValue('DisplayVersion')
            [void]$names.Add($identity)
          } catch {$partial=$true} finally {if($app){$app.Dispose()}}
        }
      } catch {$partial=$true} finally {if($key){$key.Dispose()};if($base){$base.Dispose()}}
    }
  }
  Add-Row 'apps' '桌面软件登记' ([string]$names.Count + ' 项（不含商店应用，完整清单见软件卸载）')
  if($partial){Add-Row 'apps_partial' '软件读取范围' '部分登记项未能读取' 'unavailable'}
} catch { Add-Row 'apps' '桌面软件登记' '无法读取桌面软件登记' 'unavailable' }
''';
