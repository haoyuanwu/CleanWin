import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'file_safety.dart';
import 'path_utils.dart';
import 'registry_scan_service.dart';

class RegistryBackup {
  RegistryBackup(this.path, this.issue, this.time);
  final String path;
  final RegistryIssue issue;
  final DateTime time;
}

class RegistryBackups {
  RegistryBackups({String? directory})
    : directory =
          directory ?? p.join(localAppData, 'CleanWin', 'registry_backups');
  final String directory;
  final List<String> warnings = [];
  Future<List<RegistryBackup>> list() async {
    warnings.clear();
    if (await hasLinkedAncestorAsync(directory)) {
      throw StateError('备份目录包含链接，已停止读取');
    }
    final root = Directory(directory);
    if (!await root.exists()) return [];
    final result = <RegistryBackup>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.json')) {
        continue;
      }
      try {
        if ((await entity.length()) > 1024 * 1024) {
          throw const FormatException('备份文件过大');
        }
        final decoded = jsonDecode(
          (await entity.readAsString()).replaceFirst('\ufeff', ''),
        );
        if (decoded is! Map) throw const FormatException('备份文件格式不完整');
        final issue = RegistryIssue.fromJson(
          Map<String, dynamic>.from(decoded),
        );
        if (!issue.canDelete) throw const FormatException('备份包含不支持的注册表位置');
        result.add(
          RegistryBackup(
            entity.path,
            issue,
            DateTime.tryParse('${decoded['BackedUpAtUtc']}') ??
                (await entity.stat()).modified,
          ),
        );
      } catch (_) {
        warnings.add(p.basename(entity.path));
      }
    }
    return result..sort((a, b) => b.time.compareTo(a.time));
  }
}
