import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 从可执行文件提取图标，缓存为 PNG
class AppIconService {
  AppIconService() {
    try {
      final dir = Directory(_cacheDir);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
    } on Exception catch (_) {
      // 缓存目录创建失败时跳过图标功能
    }
  }

  static String get _cacheDir {
    final local =
        Platform.environment['LOCALAPPDATA'] ??
        '${Platform.environment['USERPROFILE']}\\AppData\\Local';
    return '$local\\CleanWin\\icons';
  }

  final Map<String, String> _resolved = {};
  final Set<String> _failed = {};

  /// 解析软件图标路径，返回本地 PNG 路径；失败返回 null
  Future<String?> resolveIcon({
    required String appName,
    String? installLocation,
    String? uninstallString,
    String? displayIcon,
  }) async {
    final key = appName.toLowerCase();
    if (_resolved.containsKey(key)) return _resolved[key];
    if (_failed.contains(key)) return null;

    final candidates = <String>[];
    if (displayIcon != null && displayIcon.trim().isNotEmpty) {
      candidates.add(_cleanIconPath(displayIcon));
    }
    // 从卸载命令里抠 exe 路径
    if (uninstallString != null) {
      final exe = _extractExePath(uninstallString);
      if (exe != null) candidates.add(exe);
    }
    // 安装目录下的 exe
    if (installLocation != null && installLocation.trim().isNotEmpty) {
      candidates.addAll(_exesInDir(installLocation));
    }

    for (final exe in candidates) {
      if (exe.isEmpty) continue;
      final png = await _extractIcon(exe, key);
      if (png != null) {
        _resolved[key] = png;
        return png;
      }
    }

    _failed.add(key);
    return null;
  }

  String _cleanIconPath(String raw) {
    // 形如 "C:\Path\app.exe,0"
    var s = raw.trim();
    if (s.startsWith('"')) {
      final end = s.indexOf('"', 1);
      if (end > 0) s = s.substring(1, end);
    } else {
      final comma = s.indexOf(',');
      if (comma > 0 && s.toLowerCase().contains('.exe')) {
        s = s.substring(0, comma).trim();
      }
    }
    return s.replaceAll('/', '\\');
  }

  String? _extractExePath(String uninstall) {
    final s = uninstall.trim();
    final exeMatch = RegExp(r'"([^"]+\.(?:exe|EXE))"').firstMatch(s);
    if (exeMatch != null) return exeMatch.group(1);
    final match = RegExp(r'([A-Za-z]:\\[^,\s"]+\.(?:exe|EXE))').firstMatch(s);
    return match?.group(1);
  }

  List<String> _exesInDir(String dirPath) {
    final results = <String>[];
    try {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) return results;
      // 只看一层，避免太慢
      for (final entity in dir.listSync(followLinks: false)) {
        if (entity is File) {
          final name = entity.path.split(Platform.pathSeparator).last;
          if (name.toLowerCase().endsWith('.exe')) {
            results.add(entity.path);
          }
        }
      }
    } on FileSystemException catch (_) {}
    // 常见子目录
    for (final sub in ['bin', 'app', 'launcher']) {
      try {
        final d = Directory(p.join(dirPath, sub));
        if (!d.existsSync()) continue;
        for (final entity in d.listSync(followLinks: false)) {
          if (entity is File && entity.path.toLowerCase().endsWith('.exe')) {
            results.add(entity.path);
          }
        }
      } on FileSystemException catch (_) {}
    }
    return results;
  }

  /// 调 PowerShell 提取关联图标并存 PNG
  Future<String?> _extractIcon(String exePath, String key) async {
    final file = File(exePath);
    if (!file.existsSync()) return null;

    final outPath =
        '$_cacheDir\\${key.hashCode.toRadixString(16)}_${p.basenameWithoutExtension(exePath)}.png';
    if (File(outPath).existsSync()) return outPath;

    // 转义单引号
    final escaped = exePath.replaceAll("'", "''");
    final escapedOut = outPath.replaceAll("'", "''");

    final script =
        '''
\$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
\$icon = [System.Drawing.Icon]::ExtractAssociatedIcon('$escaped')
if (\$icon -eq \$null) { exit 2 }
\$bmp = \$icon.ToBitmap()
\$bmp.Save('$escapedOut', [System.Drawing.Imaging.ImageFormat]::Png)
\$bmp.Dispose()
\$icon.Dispose()
exit 0
''';

    try {
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', script],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(seconds: 8));

      if (result.exitCode == 0 && File(outPath).existsSync()) {
        // 至少像张图
        final size = File(outPath).lengthSync();
        if (size > 100) return outPath;
      }
    } on Exception catch (_) {}
    return null;
  }

  void clearCache() {
    _resolved.clear();
    _failed.clear();
    try {
      final dir = Directory(_cacheDir);
      if (dir.existsSync()) {
        for (final f in dir.listSync()) {
          if (f is File) f.deleteSync();
        }
      }
    } on FileSystemException catch (_) {}
  }
}
