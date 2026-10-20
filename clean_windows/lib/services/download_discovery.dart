import 'dart:convert';

import 'package:path/path.dart' as p;

import 'process_utils.dart';

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
      if (!p.isAbsolute(path) ||
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
        if (location.software &&
            [
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
    return result
      ..sort((a, b) => (b.software ? 1 : 0).compareTo(a.software ? 1 : 0));
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
ConvertTo-Json -InputObject $rows -Compress
''';
