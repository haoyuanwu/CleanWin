import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'process_utils.dart';
import 'cleanup_rules.dart';
import 'file_safety.dart';

class DownloadLocation {
  const DownloadLocation(
    this.path,
    this.source, {
    this.software = true,
    this.recursive = true,
  });
  final String path;
  final String source;
  final bool software;
  final bool recursive;
}

/// Inspect only explicit download roots, never whole installation trees.
class DownloadDiscovery {
  DownloadDiscovery(this.environment, this.runner);
  final Map<String, String> environment;
  final PowerShellRunner runner;

  Future<List<DownloadLocation>> discover(
    String systemDownloads,
    List<String> drives, {
    bool Function()? cancelled,
  }) async {
    final home = environment['USERPROFILE'] ?? '';
    final local =
        environment['LOCALAPPDATA'] ?? p.join(home, 'AppData', 'Local');
    final roaming =
        environment['APPDATA'] ?? p.join(home, 'AppData', 'Roaming');
    final result = <DownloadLocation>[];
    final seen = <String>{};
    void add(DownloadLocation location) {
      final path = p.normalize(location.path);
      if (RegExp(r'[\x00-\x1f]').hasMatch(path) ||
          !p.isAbsolute(path) ||
          path.startsWith(r'\\') ||
          p.equals(path, p.rootPrefix(path))) {
        return;
      }
      for (final protected in [
        home,
        local,
        roaming,
        environment['SystemRoot'],
        environment['ProgramData'],
        environment['ProgramFiles'],
        environment['ProgramFiles(x86)'],
        if (home.isNotEmpty)
          ...[
            'Documents',
            'Pictures',
            'Desktop',
            'Videos',
            'Music',
          ].map((name) => p.join(home, name)),
      ].whereType<String>().where((path) => path.isNotEmpty)) {
        if (p.equals(path.toLowerCase(), protected.toLowerCase()) ||
            p.isWithin(path.toLowerCase(), protected.toLowerCase())) {
          return;
        }
        if ([
          environment['SystemRoot'],
          environment['ProgramData'],
          environment['ProgramFiles'],
          environment['ProgramFiles(x86)'],
        ].whereType<String>().any(
          (root) => p.isWithin(root.toLowerCase(), path.toLowerCase()),
        )) {
          return;
        }
      }
      if (seen.add(path.toLowerCase())) {
        result.add(
          DownloadLocation(
            path,
            location.source,
            software: location.software,
            recursive: location.recursive,
          ),
        );
      }
    }

    add(DownloadLocation(systemDownloads, 'Windows 下载', software: false));
    if (home.isNotEmpty) {
      add(
        DownloadLocation(
          p.join(home, 'Downloads'),
          'Windows 默认下载',
          software: false,
        ),
      );
    }
    for (final base in {...drives, if (home.isNotEmpty) home, local, roaming}) {
      if (cancelled?.call() ?? false) break;
      for (final (relative, label, recursive) in const [
        ('QMDownload/SoftMgr', '腾讯电脑管家', true),
        ('QMDownload', '腾讯电脑管家', false),
        ('360Downloads/Software', '360 软件管家', true),
        ('360Downloads', '360 软件管家', false),
        ('Tencent/QQPCMgr/Download', '腾讯电脑管家', true),
        ('Tencent/QQPCMgr/Downloads', '腾讯电脑管家', true),
        ('QQPCMgr/Download', '腾讯电脑管家', true),
        ('QQPCMgr/Downloads', '腾讯电脑管家', true),
        ('360SoftMgr/Download', '360 软件管家', true),
        ('360SoftMgr/Downloads', '360 软件管家', true),
      ]) {
        add(
          DownloadLocation(
            p.joinAll([base, ...relative.split('/')]),
            label,
            recursive: recursive,
          ),
        );
      }
    }
    if (!(cancelled?.call() ?? false)) {
      final response = await runner(
        downloadSettingsScript,
        const Duration(seconds: 8),
      );
      if (response.success && response.stdout.trim().isNotEmpty) {
        try {
          final rows = jsonDecode(response.stdout);
          if (rows is List) {
            for (final row in rows.take(128).whereType<Map>()) {
              if (row['Path'] is String && row['Source'] is String) {
                add(
                  DownloadLocation(
                    row['Path'] as String,
                    row['Source'] as String,
                    software: row['PackagesOnly'] != false,
                  ),
                );
              }
            }
          }
        } on FormatException {
          // Optional vendor settings are not a prerequisite for known roots.
        }
      }
    }
    await for (final location in _browserDownloads(local, roaming, cancelled)) {
      add(location);
    }
    return result
      ..sort((a, b) => (b.software ? 1 : 0).compareTo(a.software ? 1 : 0));
  }

  Stream<DownloadLocation> _browserDownloads(
    String local,
    String roaming,
    bool Function()? cancelled,
  ) async* {
    final seen = <String>{};
    for (final (name, root) in browserProfileRoots(local, roaming)) {
      if (cancelled?.call() ?? false) return;
      if (name == 'Firefox') continue;
      try {
        if (await FileSystemEntity.type(root, followLinks: false) !=
                FileSystemEntityType.directory ||
            await hasLinkedAncestorAsync(root)) {
          continue;
        }
      } on FileSystemException {
        continue;
      }
      final candidates = <String>{p.join(root, 'Preferences')};
      try {
        var inspected = 0;
        await for (final child in Directory(root).list(followLinks: false)) {
          if (cancelled?.call() ?? false) return;
          if (++inspected > 256) break;
          if (child is Directory &&
              RegExp(r'^(Default|Profile [0-9]+|Opera Stable|Opera GX Stable)$')
                  .hasMatch(p.basename(child.path))) {
            candidates.add(p.join(child.path, 'Preferences'));
          }
        }
      } on FileSystemException {
        continue;
      }
      for (final preference in candidates) {
        if (cancelled?.call() ?? false) return;
        if (!seen.add(preference.toLowerCase())) continue;
        final text = await readDownloadPreferences(preference);
        if (text == null) continue;
        try {
          final decoded = jsonDecode(text);
          if (decoded is! Map) continue;
          final download = decoded['download'];
          if (download is! Map) continue;
          final configured = download['default_directory'];
          if (configured is String && configured.trim().isNotEmpty) {
            yield DownloadLocation(configured.trim(), name, software: false);
          }
        } on FormatException {
          // A damaged profile must not hide downloads from other profiles.
        }
      }
    }
  }
}

/// Bounded metadata reads only; never parse browsing history or session files.
Future<String?> readDownloadPreferences(String path) async {
  RandomAccessFile? handle;
  try {
    if (await hasLinkedAncestorAsync(path)) return null;
    handle = await File(path).open();
    const limit = 2 * 1024 * 1024;
    if (await handle.length() > limit) return null;
    final bytes = await handle.read(limit + 1);
    if (bytes.length > limit) return null;
    return utf8.decode(bytes);
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  } finally {
    await handle?.close();
  }
}

bool isDownloadedSoftwarePackage(String name) => const {
  '.exe',
  '.msi',
  '.msix',
  '.msixbundle',
  '.appx',
  '.appxbundle',
  '.zip',
  '.7z',
  '.rar',
  '.cab',
  '.iso',
  '.apk',
}.contains(p.extension(name).toLowerCase());

const downloadSettingsScript = r'''
$ErrorActionPreference='SilentlyContinue'
[Console]::OutputEncoding=[Text.Encoding]::UTF8
# CleanWinDownloadSettings: only read explicitly supported vendor keys.
$specs=@(
  @{Source='腾讯电脑管家'; Keys=@('Software\Tencent\QQPCMgr','Software\Tencent\QQPCMgr\SoftMgr','Software\Tencent\SoftMgr')},
  @{Source='360 软件管家'; Keys=@('Software\360\360SoftMgr','Software\360Safe\SoftMgr','Software\360SoftMgr')}
)
$rows=@(foreach($spec in $specs) {
  foreach($hive in @('HKCU:','HKLM:')) {
    foreach($prefix in @('','WOW6432Node\')) {
      foreach($key in $spec.Keys) {
        $relative=$key -replace '^Software\\',('Software\'+$prefix)
        $settings=Get-ItemProperty -LiteralPath ($hive+'\'+$relative)
        foreach($name in @('DownloadPath','DownloadDir','DownloadDirectory','DownPath','SavePath')) {
          $value=$settings.$name
          if($value -is [string] -and $value.Trim()) {
            [pscustomobject]@{Source=$spec.Source;Path=[Environment]::ExpandEnvironmentVariables($value.Trim())}
          }
        }
      }
    }
  }
})
# Read only the documented task default of installed Thunder clients.
function Read-TaskDefault([string]$ini) {
  $file=Get-Item -LiteralPath $ini -ErrorAction SilentlyContinue
  if(!$file -or $file.PSIsContainer -or $file.Length -gt 2097152 -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)){return}
  $stream=$null
  try {
    $stream=[IO.File]::Open($file.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    $buffer=New-Object byte[] 2097153;$length=0
    while($length -lt $buffer.Length) {
      $read=$stream.Read($buffer,$length,$buffer.Length-$length)
      if($read -eq 0){break};$length+=$read
    }
    if($length -ge $buffer.Length){return}
    if($length -ge 2 -and $buffer[0] -eq 255 -and $buffer[1] -eq 254) {
      $text=[Text.Encoding]::Unicode.GetString($buffer,0,$length)
    } else {
      try {$text=([Text.UTF8Encoding]::new($false,$true)).GetString($buffer,0,$length)}
      catch {$text=[Text.Encoding]::Default.GetString($buffer,0,$length)}
    }
  } catch {return} finally {if($stream){$stream.Dispose()}}
  $section='';$count=0
  foreach($line in ($text.TrimStart([char]0xFEFF) -split '\r?\n')) {
    if(++$count -gt 8192){break}
    $value=$line.Trim()
    if($value -match '^\[(.+)\]$'){$section=$Matches[1];continue}
    if($section -eq 'PrivateSpace' -and $value -match '^DefaultPath\s*=\s*(.+)$') {
      $download=[Environment]::ExpandEnvironmentVariables($Matches[1].Trim().Trim([char]34))
      if($download){[pscustomobject]@{Source='迅雷下载';Path=$download;PackagesOnly=$false}}
    }
  }
}
foreach($hive in @('HKCU:','HKLM:')) {
  foreach($key in @('Software\Microsoft\Windows\CurrentVersion\Uninstall\thunder_is1','Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\thunder_is1')) {
    $installation=(Get-ItemProperty -LiteralPath ($hive+'\'+$key) -ErrorAction SilentlyContinue).InstallLocation
    if($installation -is [string] -and [IO.Path]::IsPathRooted($installation)) {
      $rows+=@(Read-TaskDefault (Join-Path $installation 'Profiles\newtask.ini'))
    }
  }
}
ConvertTo-Json -InputObject $rows -Compress
''';
