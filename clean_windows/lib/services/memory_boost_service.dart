import 'dart:convert';
import 'dart:io';

import 'process_utils.dart';

class MemoryBoostResult {
  const MemoryBoostResult({
    required this.candidates,
    required this.trimmed,
    required this.beforeAvailable,
    required this.afterAvailable,
  });
  final int candidates, trimmed, beforeAvailable, afterAvailable;
  int get availableChange => afterAvailable - beforeAvailable;
}

class MemoryBoostService {
  MemoryBoostService({PowerShellRunner? runner})
    : _run = runner ?? runPowerShell;
  final PowerShellRunner _run;
  Future<MemoryBoostResult> inspect() => _sample(false);
  Future<MemoryBoostResult> optimize() => _sample(true);
  Future<MemoryBoostResult> _sample(bool apply) async {
    final result = await _run(
      '$script\n[CleanWinBackgroundMemory]::Run(${apply ? r'$true' : r'$false'}, $pid) | ConvertTo-Json -Compress',
      const Duration(seconds: 25),
    );
    if (!result.success) throw StateError('内存操作未完成，请重试');
    final raw = jsonDecode(result.stdout);
    if (raw is! Map ||
        raw['Candidates'] is! num ||
        raw['Trimmed'] is! num ||
        raw['BeforeAvailable'] is! num ||
        raw['AfterAvailable'] is! num) {
      throw const FormatException('内存操作结果不完整');
    }
    return MemoryBoostResult(
      candidates: (raw['Candidates'] as num).toInt(),
      trimmed: (raw['Trimmed'] as num).toInt(),
      beforeAvailable: (raw['BeforeAvailable'] as num).toInt(),
      afterAvailable: (raw['AfterAvailable'] as num).toInt(),
    );
  }

  // A bounded, user-confirmed operation. No privilege changes, process exits,
  // standby-list purge, drivers or third-party private RPC calls.
  static const script = r'''
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.Encoding]::UTF8
Add-Type -TypeDefinition @"
using System;
using System.Diagnostics;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Security.Principal;
public class CleanWinMemoryResult { public int Candidates,Trimmed; public ulong BeforeAvailable,AfterAvailable; }
public static class CleanWinBackgroundMemory {
 [StructLayout(LayoutKind.Sequential)] struct MemoryStatus {
  public uint Length,Load;
  public ulong TotalPhysical,AvailablePhysical,TotalPage,AvailablePage,TotalVirtual,AvailableVirtual,AvailableExtended;
 }
 [DllImport("kernel32.dll")] static extern bool GlobalMemoryStatusEx(ref MemoryStatus s);
 [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access,bool inherit,int pid);
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
 [DllImport("advapi32.dll")] static extern bool OpenProcessToken(IntPtr process,uint access,out IntPtr token);
 [DllImport("psapi.dll")] static extern bool EmptyWorkingSet(IntPtr h);
 static ulong Available(){var s=new MemoryStatus();s.Length=(uint)Marshal.SizeOf(s);if(!GlobalMemoryStatusEx(ref s))throw new InvalidOperationException("Memory status unavailable");return s.AvailablePhysical;}
 public static CleanWinMemoryResult Run(bool apply,int appPid){
  var result=new CleanWinMemoryResult();result.BeforeAvailable=Available();
  var sid=WindowsIdentity.GetCurrent().User.Value;int session=Process.GetCurrentProcess().SessionId;
  var protectedNames=new HashSet<string>(StringComparer.OrdinalIgnoreCase){"System","Registry","smss","csrss","wininit","winlogon","lsass","services","svchost","dwm","sihost","fontdrvhost","explorer","SearchHost","StartMenuExperienceHost","ShellExperienceHost","SecurityHealthSystray","Memory Compression"};
  var watch=Stopwatch.StartNew();
  foreach(var process in Process.GetProcesses()){
   IntPtr handle=IntPtr.Zero,token=IntPtr.Zero;
   try{
    if(watch.ElapsedMilliseconds>8000)break;
    if(process.Id<=4 || process.Id==appPid || process.Id==Process.GetCurrentProcess().Id || process.SessionId!=session || protectedNames.Contains(process.ProcessName) || process.MainWindowHandle!=IntPtr.Zero || process.WorkingSet64<32L*1024*1024)continue;
    handle=OpenProcess(0x1000|0x0100,false,process.Id);
    if(handle==IntPtr.Zero || !OpenProcessToken(handle,8,out token))continue;
    using(var owner=new WindowsIdentity(token)){if(owner.User==null || owner.User.Value!=sid)continue;}
    result.Candidates++;if(apply && EmptyWorkingSet(handle))result.Trimmed++;
   }catch{}finally{if(token!=IntPtr.Zero)CloseHandle(token);if(handle!=IntPtr.Zero)CloseHandle(handle);process.Dispose();}
  }
  result.AfterAvailable=Available();return result;
 }
}
"@
''';
}
