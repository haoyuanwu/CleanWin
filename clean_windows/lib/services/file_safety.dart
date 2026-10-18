import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

bool protectedSystemPath(String path) {
  final target = p.windows.normalize(path).toLowerCase();
  return [
    Platform.environment['SystemRoot'],
    Platform.environment['ProgramFiles'],
    Platform.environment['ProgramFiles(x86)'],
    Platform.environment['ProgramData'],
    File(Platform.resolvedExecutable).parent.path,
  ].whereType<String>().where((root) => root.isNotEmpty).any((root) {
    final base = p.windows.normalize(root).toLowerCase();
    return target == base || target.startsWith('$base\\');
  });
}

String fileSignature(FileStat stat) =>
    '${stat.size}:${stat.modified.microsecondsSinceEpoch}';

/// Check both the target and its parents without following links.
bool hasLinkedAncestor(String path) {
  var current = File(path).absolute.path;
  while (true) {
    if (FileSystemEntity.typeSync(current, followLinks: false) ==
        FileSystemEntityType.link) {
      return true;
    }
    final parent = Directory(current).parent.path;
    if (parent == current) return false;
    current = parent;
  }
}

/// Cleanup runs on the UI isolate: filesystem probes must yield to rendering.
Future<bool> hasLinkedAncestorAsync(String path) async {
  var current = File(path).absolute.path;
  while (true) {
    if (await FileSystemEntity.type(current, followLinks: false) ==
        FileSystemEntityType.link) {
      return true;
    }
    final parent = Directory(current).parent.path;
    if (parent == current) return false;
    current = parent;
  }
}

/// Retry only read-only failures; never clear hidden or system attributes.
Future<void> clearReadOnlyAttribute(String path) async {
  final process = await Process.start('attrib', [
    '-r',
    path,
  ], runInShell: false);
  final output = Future.wait([
    process.stdout.drain<void>(),
    process.stderr.drain<void>(),
  ]);
  try {
    final code = await process.exitCode.timeout(const Duration(seconds: 5));
    if (code != 0) throw FileSystemException('无法修改只读属性', path);
  } on TimeoutException {
    process.kill();
    rethrow;
  } finally {
    await output;
  }
}
