import 'dart:io';

import 'file_operability.dart';

String diagnosticPath(String path) =>
    path.endsWith(r'\*') || path.endsWith('/*')
    ? path.substring(0, path.length - 2)
    : path;

String describeReadFailure(FileSystemException error) {
  final code = error.osError?.errorCode;
  final cause = switch (code) {
    5 => '目录访问被拒绝',
    32 || 33 => '读取时发生占用冲突',
    206 => '路径过长',
    1920 || 4390 || 4392 || 4393 => '链接或重解析点不可访问',
    362 || 4350 => '云端或离线文件未就绪',
    _ => '文件系统读取失败',
  };
  return '$cause${code == null ? '' : '（Windows $code）'}：${diagnosticPath(error.path ?? '未知路径')}';
}

String? readDiagnostics(
  Map<String, FileSystemException> errors,
  Iterable<String> notices,
) {
  final lines = <String>[
    if (errors.isNotEmpty) '有 ${errors.length} 个位置未完整读取，已保留其他位置的结果。',
    ...errors.values.take(20).map(describeReadFailure),
    if (errors.length > 20) '另有 ${errors.length - 20} 个位置未展开。',
    ...notices,
  ];
  return lines.isEmpty ? null : lines.join('\n');
}

String? cleanupDiagnostics(Map<String, CleanupPathBlock> blocked) {
  if (blocked.isEmpty) return null;
  final counts = <CleanupBlockReason, int>{};
  for (final block in blocked.values) {
    counts.update(block.reason, (count) => count + 1, ifAbsent: () => 1);
  }
  final samples = <MapEntry<String, CleanupPathBlock>>[];
  final sampledReasons = <CleanupBlockReason>{};
  final sampledPaths = <String>{};
  for (final entry in blocked.entries) {
    if (sampledReasons.add(entry.value.reason)) {
      samples.add(entry);
      sampledPaths.add(entry.key);
    }
  }
  for (final entry in blocked.entries) {
    if (samples.length >= 12) break;
    if (sampledPaths.add(entry.key)) samples.add(entry);
  }
  return [
    '已统计但未加入清理：${blocked.length} 个候选文件；这不等于目录无法读取。',
    for (final entry in counts.entries)
      '${entry.key.label} ${entry.value} 个 · ${entry.key.action}',
    for (final entry in samples)
      '${entry.value.reason.label}${entry.value.windowsError == null ? '' : '（Windows ${entry.value.windowsError}）'}：${entry.key}',
    if (blocked.length > samples.length)
      '另有 ${blocked.length - samples.length} 个同类文件未展开。',
  ].join('\n');
}
