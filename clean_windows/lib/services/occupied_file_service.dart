import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'process_utils.dart';

class OccupiedApplication {
  const OccupiedApplication({
    required this.pid,
    required this.name,
    required this.restartable,
    required this.safeToClose,
  });

  final int pid;
  final String name;
  final bool restartable;
  final bool safeToClose;
}

abstract class OccupiedFileCoordinator {
  Future<OccupiedFileSession?> open(List<String> paths);
}

abstract class OccupiedFileSession {
  List<OccupiedApplication> get applications;
  int get fileCount;
  String? get error;
  bool get canCloseAndRestore;
  Future<bool> close(Set<int> processIds);
  Future<bool> restore();
  Future<void> dispose();
}

class WindowsOccupiedFileCoordinator implements OccupiedFileCoordinator {
  const WindowsOccupiedFileCoordinator();

  @override
  Future<OccupiedFileSession?> open(List<String> paths) async {
    final unique = paths.toSet().where((path) => path.isNotEmpty).toList();
    if (!Platform.isWindows || unique.isEmpty || ProcessUtils.debugSkip) {
      return null;
    }
    return _PowerShellOccupiedSession.start(unique);
  }
}

class _PowerShellOccupiedSession implements OccupiedFileSession {
  _PowerShellOccupiedSession._(
    this._process,
    this._lines,
    this._resourceFile,
    this.applications,
    this.fileCount,
    this.error,
  );

  final Process _process;
  final StreamIterator<String> _lines;
  final File _resourceFile;
  @override
  final List<OccupiedApplication> applications;
  @override
  final int fileCount;
  @override
  final String? error;
  bool _closed = false;
  bool _disposed = false;

  @override
  bool get canCloseAndRestore =>
      error == null &&
      applications.any((app) => app.restartable && app.safeToClose);

  static Future<_PowerShellOccupiedSession?> start(List<String> paths) async {
    final suffix =
        '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    final resourceFile = File(
      '${Directory.systemTemp.path}\\cleanwin-locks-$suffix.json',
    );
    await resourceFile.writeAsString(jsonEncode(paths), flush: true);
    Process? process;
    StreamIterator<String>? lines;
    try {
      process = await Process.start(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-EncodedCommand',
          _encodePowerShell(_restartManagerScript),
        ],
        environment: {
          'CLEANWIN_LOCK_PATH_FILE': resourceFile.path,
          'CLEANWIN_APP_PID': '$pid',
        },
      );
      lines = StreamIterator(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      );
      final plan = await _nextProtocolLine(
        lines,
        'PLAN ',
        const Duration(seconds: 20),
      );
      if (plan == null) {
        process.kill();
        await _deleteResourceFile(resourceFile);
        return null;
      }
      final decoded = jsonDecode(plan);
      if (decoded is! Map) {
        process.kill();
        await _deleteResourceFile(resourceFile);
        return null;
      }
      final map = decoded.map((key, value) => MapEntry('$key', value));
      final apps = <OccupiedApplication>[
        for (final raw in (map['Apps'] as List? ?? const []))
          if (raw is Map)
            OccupiedApplication(
              pid: (raw['Pid'] as num?)?.toInt() ?? 0,
              name: raw['Name']?.toString().trim().isNotEmpty == true
                  ? raw['Name'].toString().trim()
                  : '进程 ${(raw['Pid'] as num?)?.toInt() ?? 0}',
              restartable: raw['Restartable'] == true,
              safeToClose: raw['Safe'] == true,
            ),
      ];
      return _PowerShellOccupiedSession._(
        process,
        lines,
        resourceFile,
        List.unmodifiable(apps),
        paths.length,
        map['Error']?.toString(),
      );
    } on Exception {
      process?.kill();
      await lines?.cancel();
      await _deleteResourceFile(resourceFile);
      return null;
    }
  }

  @override
  Future<bool> close(Set<int> processIds) async {
    final safeIds = applications
        .where((app) => app.restartable && app.safeToClose)
        .map((app) => app.pid)
        .toSet();
    if (_disposed || processIds.isEmpty || !safeIds.containsAll(processIds)) {
      return false;
    }
    _process.stdin.writeln(
      jsonEncode({'Action': 'close', 'Pids': processIds.toList()}),
    );
    await _process.stdin.flush();
    final response = await _nextProtocolLine(
      _lines,
      'CLOSE ',
      const Duration(seconds: 45),
    );
    if (response == null) return false;
    final decoded = jsonDecode(response);
    _closed = decoded is Map && decoded['Code'] == 0;
    return _closed;
  }

  @override
  Future<bool> restore() async {
    if (_disposed) return false;
    if (!_closed) {
      await dispose();
      return true;
    }
    try {
      _process.stdin.writeln('restart');
      await _process.stdin.flush();
      final response = await _nextProtocolLine(
        _lines,
        'RESTART ',
        const Duration(seconds: 30),
      );
      if (response == null) return false;
      final decoded = jsonDecode(response);
      return decoded is Map && decoded['Code'] == 0;
    } finally {
      await dispose();
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      if (!_closed) {
        _process.stdin.writeln('end');
        await _process.stdin.flush();
      }
    } on Exception {
      // The helper may already have exited.
    }
    try {
      await _process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      _process.kill();
    }
    await _lines.cancel();
    await _deleteResourceFile(_resourceFile);
  }
}

Future<String?> _nextProtocolLine(
  StreamIterator<String> lines,
  String prefix,
  Duration timeout,
) async {
  return () async {
    while (await lines.moveNext()) {
      final line = lines.current.trim();
      if (line.startsWith(prefix)) return line.substring(prefix.length);
    }
    return null;
  }().timeout(timeout, onTimeout: () => null);
}

Future<void> _deleteResourceFile(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } on FileSystemException {
    // A stale temp manifest contains paths only and can be removed by Windows.
  }
}

String _encodePowerShell(String script) {
  final units = script.codeUnits;
  final bytes = Uint8List(units.length * 2);
  final data = ByteData.sublistView(bytes);
  for (var index = 0; index < units.length; index++) {
    data.setUint16(index * 2, units[index], Endian.little);
  }
  return base64Encode(bytes);
}

const _restartManagerScript = r'''
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$source = @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class CleanWinRestartManager {
  public const int CCH_RM_SESSION_KEY = 32;
  public const int ERROR_MORE_DATA = 234;

  [StructLayout(LayoutKind.Sequential)]
  public struct RM_UNIQUE_PROCESS {
    public int dwProcessId;
    public System.Runtime.InteropServices.ComTypes.FILETIME ProcessStartTime;
  }

  public enum RM_APP_TYPE {
    RmUnknownApp = 0, RmMainWindow = 1, RmOtherWindow = 2,
    RmService = 3, RmExplorer = 4, RmConsole = 5, RmCritical = 1000
  }

  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct RM_PROCESS_INFO {
    public RM_UNIQUE_PROCESS Process;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string strAppName;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string strServiceShortName;
    public RM_APP_TYPE ApplicationType;
    public uint AppStatus;
    public uint TSSessionId;
    [MarshalAs(UnmanagedType.Bool)] public bool bRestartable;
  }

  [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
  public static extern int RmStartSession(out uint handle, int flags, StringBuilder key);
  [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
  public static extern int RmRegisterResources(uint handle, uint fileCount,
    string[] files, uint appCount, RM_UNIQUE_PROCESS[] apps,
    uint serviceCount, string[] services);
  [DllImport("rstrtmgr.dll")]
  public static extern int RmGetList(uint handle, out uint needed, ref uint count,
    [In, Out] RM_PROCESS_INFO[] apps, ref uint reasons);
  [DllImport("rstrtmgr.dll")]
  public static extern int RmShutdown(uint handle, uint flags, IntPtr callback);
  [DllImport("rstrtmgr.dll")]
  public static extern int RmRestart(uint handle, uint flags, IntPtr callback);
  [DllImport("rstrtmgr.dll")]
  public static extern int RmEndSession(uint handle);
}
'@

Add-Type -TypeDefinition $source -ErrorAction Stop
$handle = [uint32]0
$started = $false
try {
  $key = [Text.StringBuilder]::new(33)
  $code = [CleanWinRestartManager]::RmStartSession([ref]$handle, 0, $key)
  if ($code -ne 0) {
    Write-Output ('PLAN ' + (@{ Error = "Restart Manager $code"; Apps = @() } | ConvertTo-Json -Compress))
    return
  }
  $started = $true
  $paths = @(Get-Content -Raw -LiteralPath $env:CLEANWIN_LOCK_PATH_FILE | ConvertFrom-Json)
  $code = [CleanWinRestartManager]::RmRegisterResources($handle, $paths.Count, [string[]]$paths, 0, $null, 0, $null)
  if ($code -ne 0) {
    Write-Output ('PLAN ' + (@{ Error = "Register resources $code"; Apps = @() } | ConvertTo-Json -Compress))
    return
  }
  [uint32]$needed = 0
  [uint32]$count = 0
  [uint32]$reasons = 0
  $code = [CleanWinRestartManager]::RmGetList($handle, [ref]$needed, [ref]$count, $null, [ref]$reasons)
  $native = @()
  if ($needed -gt 0) {
    $native = New-Object CleanWinRestartManager+RM_PROCESS_INFO[] $needed
    $count = $needed
    $code = [CleanWinRestartManager]::RmGetList($handle, [ref]$needed, [ref]$count, $native, [ref]$reasons)
  }
  if ($code -ne 0) {
    Write-Output ('PLAN ' + (@{ Error = "List processes $code"; Apps = @() } | ConvertTo-Json -Compress))
    return
  }
  $cleanWinPid = [int]$env:CLEANWIN_APP_PID
  $apps = @($native | Select-Object -First $count | ForEach-Object {
    $type = [int]$_.ApplicationType
    $safe = $_.Process.dwProcessId -ne $cleanWinPid -and $_.bRestartable -and $type -in @(1, 2, 5)
    [ordered]@{
      Pid = $_.Process.dwProcessId
      Name = $_.strAppName
      Restartable = [bool]$_.bRestartable
      Safe = [bool]$safe
    }
  })
  Write-Output ('PLAN ' + (ConvertTo-Json -InputObject @{ Apps = $apps } -Compress -Depth 4))
  [void][CleanWinRestartManager]::RmEndSession($handle)
  $started = $false
  $command = [Console]::In.ReadLine()
  if ($command -eq 'end') { return }
  $request = $command | ConvertFrom-Json
  $pids = @($request.Pids | ForEach-Object { [int]$_ })
  $safePids = @($apps | Where-Object { $_.Safe } | ForEach-Object { [int]$_.Pid })
  if ($request.Action -ne 'close' -or $pids.Count -eq 0 -or @($pids | Where-Object { $_ -notin $safePids }).Count -gt 0) {
    Write-Output ('CLOSE ' + (@{ Code = -1 } | ConvertTo-Json -Compress))
    return
  }
  $selected = @($native | Where-Object { $_.Process.dwProcessId -in $pids })
  $processes = New-Object CleanWinRestartManager+RM_UNIQUE_PROCESS[] $selected.Count
  for ($index = 0; $index -lt $selected.Count; $index++) {
    $processes[$index] = $selected[$index].Process
  }
  $key = [Text.StringBuilder]::new(33)
  $code = [CleanWinRestartManager]::RmStartSession([ref]$handle, 0, $key)
  if ($code -ne 0) {
    Write-Output ('CLOSE ' + (@{ Code = $code } | ConvertTo-Json -Compress))
    return
  }
  $started = $true
  $code = [CleanWinRestartManager]::RmRegisterResources($handle, 0, $null, $processes.Count, $processes, 0, $null)
  if ($code -ne 0) {
    Write-Output ('CLOSE ' + (@{ Code = $code } | ConvertTo-Json -Compress))
    return
  }
  $code = [CleanWinRestartManager]::RmShutdown($handle, 0, [IntPtr]::Zero)
  Write-Output ('CLOSE ' + (@{ Code = $code } | ConvertTo-Json -Compress))
  if ($code -ne 0) { return }
  $command = [Console]::In.ReadLine()
  if ($command -eq 'restart') {
    $code = [CleanWinRestartManager]::RmRestart($handle, 0, [IntPtr]::Zero)
    Write-Output ('RESTART ' + (@{ Code = $code } | ConvertTo-Json -Compress))
  }
}
catch {
  Write-Output ('PLAN ' + (@{ Error = $_.Exception.Message; Apps = @() } | ConvertTo-Json -Compress))
}
finally {
  if ($started) { [void][CleanWinRestartManager]::RmEndSession($handle) }
}
''';
