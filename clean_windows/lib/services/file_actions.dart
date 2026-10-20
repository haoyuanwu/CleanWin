import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'process_utils.dart';

class FileActions {
  /// Extract a path for navigation only. Never execute a startup command.
  static String? executablePath(String command) {
    final expanded = command.trim().replaceAllMapped(RegExp(r'%([^%]+)%'), (
      match,
    ) {
      for (final entry in Platform.environment.entries) {
        if (entry.key.toLowerCase() == match[1]!.toLowerCase()) {
          return entry.value;
        }
      }
      return match[0]!;
    });
    final match = expanded.startsWith('"')
        ? RegExp(r'^"([^"]+)"').firstMatch(expanded)
        : RegExp(
            r'^(.+?\.(?:exe|com|cmd|bat|lnk))(?:\s|,|$)',
            caseSensitive: false,
          ).firstMatch(expanded);
    final path = match?.group(1);
    return path != null && p.windows.isAbsolute(path) ? path : null;
  }

  static Future<void> copyPath(String path) =>
      Clipboard.setData(ClipboardData(text: path));
  static Future<List<String>> explorerArguments(String path) async {
    if (path.trim().isEmpty || !p.isAbsolute(path)) {
      throw FileSystemException('不是有效的文件路径', path);
    }
    if (await Directory(path).exists()) return [path];
    if (await File(path).exists()) return ['/select,', path];
    final parent = File(path).parent;
    if (!await parent.exists()) throw FileSystemException('路径已不存在', path);
    return [parent.path];
  }

  static Future<void> reveal(String path) async {
    if (!Platform.isWindows || ProcessUtils.debugSkip) return;
    await Process.start(
      'explorer.exe',
      await explorerArguments(path),
      mode: ProcessStartMode.detached,
    );
  }

  static Future<void> recycleBin() async {
    if (!Platform.isWindows || ProcessUtils.debugSkip) return;
    await Process.start('explorer.exe', [
      'shell:RecycleBinFolder',
    ], mode: ProcessStartMode.detached);
  }
}
