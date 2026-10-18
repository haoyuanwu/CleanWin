import 'dart:io';

import 'package:flutter/services.dart';

import 'process_utils.dart';

class FileActions {
  static Future<void> copyPath(String path) =>
      Clipboard.setData(ClipboardData(text: path));
  static Future<void> reveal(String path) async {
    if (!Platform.isWindows || ProcessUtils.debugSkip) return;
    if (await Directory(path).exists()) {
      await Process.start('explorer.exe', [
        path,
      ], mode: ProcessStartMode.detached);
    } else {
      await Process.start('explorer.exe', [
        '/select,',
        path,
      ], mode: ProcessStartMode.detached);
    }
  }

  static Future<void> recycleBin() async {
    if (!Platform.isWindows || ProcessUtils.debugSkip) return;
    await Process.start('explorer.exe', [
      'shell:RecycleBinFolder',
    ], mode: ProcessStartMode.detached);
  }
}
