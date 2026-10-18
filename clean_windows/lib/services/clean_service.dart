import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/clean_models.dart';
import 'file_safety.dart';
import 'process_utils.dart';
import 'registry_cache.dart';
import 'whitelist_service.dart';
import 'cache_discovery.dart';
import 'recycle_service.dart';

/// Delete only the reviewed snapshot; never widen a target during cleanup.
class CleanService {
  CleanService({
    PowerShellRunner? powerShellRunner,
    Future<bool> Function(String)? recycler,
  }) : _runPowerShell = powerShellRunner ?? runPowerShell,
       _recycler = recycler ?? recycleFile;
  final PowerShellRunner _runPowerShell;
  final Future<bool> Function(String) _recycler;
  WhitelistService? whitelist;

  Future<CleanReport> cleanItems(
    List<CleanItem> items, {
    void Function(CleanItem item, String message, int done, int total)? onItem,
    CleanCancellation? cancellation,
    bool recycle = false,
  }) async {
    if (whitelist?.readable == false) throw StateError(whitelist!.lastError!);
    var freed = 0;
    var recycled = 0;
    var deleted = 0;
    var skipped = 0;
    var failed = 0;
    var cancelled = false;
    final failures = <String>[];
    final completed = <String>{};
    final targets = items.where((i) => i.selected).toList();
    for (var index = 0; index < targets.length; index++) {
      if (cancellation?.requested ?? false) {
        cancelled = true;
        break;
      }
      final item = targets[index];
      onItem?.call(item, '正在清理 ${item.name}…', index, targets.length);
      _DeleteResult result;
      try {
        result = await _cleanItem(
          item,
          cancellation: cancellation,
          recycle: recycle && item.category == CleanCategory.downloads,
          onFile: onItem == null
              ? null
              : (path, done, total) {
                  onItem(
                    item,
                    '正在清理 ${item.name}（$done / $total 个文件）\n$path',
                    index,
                    targets.length,
                  );
                },
        );
      } on Exception catch (error) {
        result = _DeleteResult(error: error.toString());
      }
      if (recycle && item.category == CleanCategory.downloads) {
        recycled += result.freed;
      } else {
        freed += result.freed;
      }
      if (result.cancelled) {
        cancelled = true;
        onItem?.call(item, '正在取消，核对剩余文件…', index, targets.length);
        await _refreshRemaining(item);
        break;
      }
      final String message;
      if (result.ok) {
        deleted++;
        completed.add(item.id);
        item.sizeBytes = 0;
        item.fileCount = 0;
        item.selected = false;
        message = '已清理 ${item.name}';
      } else {
        if (result.skipped) {
          skipped++;
        } else {
          failed++;
        }
        failures.add('${item.name}: ${result.error ?? "未能完整清理"}');
        await _refreshRemaining(item);
        message = result.freed > 0
            ? '部分清理 ${item.name}，剩余文件已保留'
            : '跳过 ${item.name}';
      }
      onItem?.call(item, message, index + 1, targets.length);
    }
    return CleanReport(
      freedBytes: freed,
      deletedCount: deleted,
      skippedCount: skipped,
      failedCount: failed,
      failures: failures,
      completedItemIds: completed,
      cancelled: cancelled,
      recycledBytes: recycled,
    );
  }

  Future<_DeleteResult> _cleanItem(
    CleanItem item, {
    void Function(String path, int done, int total)? onFile,
    CleanCancellation? cancellation,
    bool recycle = false,
  }) async {
    if (item.category != CleanCategory.downloads &&
        item.category != CleanCategory.recycleBin &&
        protectedCachePath(item.path)) {
      return const _DeleteResult(skipped: true, error: '开发依赖、离线资源或本程序目录受保护');
    }
    if (cancellation?.requested ?? false) {
      return const _DeleteResult(cancelled: true);
    }
    if (whitelist?.isWhitelisted(item.path) ?? false) {
      return const _DeleteResult(skipped: true, error: '已加入白名单');
    }
    if (item.category == CleanCategory.downloads &&
        protectedSystemPath(item.path)) {
      return const _DeleteResult(skipped: true, error: '系统、安装程序或本程序运行目录受保护');
    }
    if (item.category == CleanCategory.registryJunk) {
      if (!RegistryCache.accepts(item)) {
        return const _DeleteResult(error: '缺少可验证的注册表快照，请重新扫描');
      }
      if (cancellation?.requested ?? false) {
        return const _DeleteResult(cancelled: true);
      }
      final result = await _runPowerShell(
        RegistryCache.cleanupScript(item),
        const Duration(seconds: 20),
      );
      return _DeleteResult(
        ok: result.success,
        error: result.success ? null : result.stderr,
      );
    }
    if (await hasLinkedAncestorAsync(item.path)) {
      return const _DeleteResult(skipped: true, error: '路径包含链接，请重新扫描');
    }
    if (item.removeEmptyDirectory) {
      final dir = Directory(item.path);
      if (!await dir.exists()) return const _DeleteResult(ok: true);
      if (!await dir.list(followLinks: false).isEmpty) {
        return const _DeleteResult(skipped: true, error: '目录已不为空');
      }
      if (cancellation?.requested ?? false) {
        return const _DeleteResult(cancelled: true);
      }
      await dir.delete(); // Non-recursive: never delete newly created contents.
      return const _DeleteResult(ok: true);
    }
    final paths = item.scannedFiles;
    if (paths == null) {
      return const _DeleteResult(skipped: true, error: '缺少文件清单，请重新扫描');
    }
    var freed = 0;
    var errors = 0;
    String? lastError;
    final root = p.normalize(p.absolute(item.path));
    final ordered = paths.toSet().toList();
    if (item.category == CleanCategory.recycleBin) {
      // Keep $I recovery metadata until its matching $R payload is removed.
      ordered.sort(
        (a, b) => _isRecycleMetadata(
          a,
          root,
        ).toString().compareTo(_isRecycleMetadata(b, root).toString()),
      );
    }
    final progressClock = Stopwatch()..start();
    var reportedAt = -100;
    for (var fileIndex = 0; fileIndex < ordered.length; fileIndex++) {
      if (cancellation?.requested ?? false) {
        return _DeleteResult(cancelled: true, freed: freed);
      }
      final path = ordered[fileIndex];
      if (progressClock.elapsedMilliseconds - reportedAt >= 100 ||
          fileIndex == ordered.length - 1) {
        reportedAt = progressClock.elapsedMilliseconds;
        onFile?.call(path, fileIndex, ordered.length);
        await Future<void>.delayed(Duration.zero);
      }
      if (cancellation?.requested ?? false) {
        return _DeleteResult(cancelled: true, freed: freed);
      }
      final absolute = p.normalize(p.absolute(path));
      if (item.category != CleanCategory.downloads &&
          item.category != CleanCategory.recycleBin &&
          protectedCachePath(path)) {
        errors++;
        lastError = '开发依赖或离线资源受保护';
        continue;
      }
      if (!(p.equals(root, absolute) || p.isWithin(root, absolute))) {
        errors++;
        lastError = '清单包含范围外路径，已跳过';
        continue;
      }
      if ((whitelist?.isWhitelisted(path) ?? false) ||
          await hasLinkedAncestorAsync(path)) {
        errors++;
        lastError = '文件受白名单保护或路径包含链接';
        continue;
      }
      try {
        if (item.category == CleanCategory.recycleBin &&
            _isRecycleMetadata(path, root)) {
          final payload = p.join(root, '\$R${p.basename(path).substring(2)}');
          final payloadType = await FileSystemEntity.type(
            payload,
            followLinks: false,
          );
          if (payloadType == FileSystemEntityType.directory &&
              await Directory(payload).list(followLinks: false).isEmpty) {
            if (cancellation?.requested ?? false) {
              return _DeleteResult(cancelled: true, freed: freed);
            }
            await Directory(payload).delete();
          }
          if (await FileSystemEntity.type(payload, followLinks: false) !=
              FileSystemEntityType.notFound) {
            errors++;
            lastError = '回收站内容未能完整删除，已保留恢复信息';
            continue;
          }
        }
        final type = await FileSystemEntity.type(path, followLinks: false);
        if (type == FileSystemEntityType.notFound) continue;
        if (type != FileSystemEntityType.file) {
          errors++;
          lastError = '扫描后文件类型已改变';
          continue;
        }
        final file = File(path);
        final stat = await file.stat();
        final expected = item.fileSignatures?[path];
        if (expected != null && expected != fileSignature(stat)) {
          errors++;
          lastError = '扫描后文件已改变，请重新扫描';
          continue;
        }
        final bytes = stat.size;
        if (item.requiredKeeperPath != null) {
          final keeper = await File(item.requiredKeeperPath!).stat();
          if (keeper.type != FileSystemEntityType.file ||
              fileSignature(keeper) != item.requiredKeeperSignature ||
              await hasLinkedAncestorAsync(item.requiredKeeperPath!)) {
            errors++;
            lastError = '保留副本已改变或不存在，已停止处理此文件';
            continue;
          }
        }
        if (cancellation?.requested ?? false) {
          return _DeleteResult(cancelled: true, freed: freed);
        }
        try {
          if (recycle) {
            if (!await _recycler(path) || await file.exists()) {
              throw FileSystemException('文件未移入回收站，已保留原文件', path);
            }
          } else {
            await file.delete();
          }
        } on FileSystemException catch (error) {
          // Retry a read-only file once; do not strip hidden/system attributes.
          if (recycle ||
              !Platform.isWindows ||
              ProcessUtils.debugSkip ||
              error.osError?.errorCode != 5) {
            rethrow;
          }
          if (cancellation?.requested ?? false) {
            return _DeleteResult(cancelled: true, freed: freed);
          }
          await clearReadOnlyAttribute(path);
          if (cancellation?.requested ?? false) {
            return _DeleteResult(cancelled: true, freed: freed);
          }
          await file.delete();
        }
        freed += bytes;
        if (item.category == CleanCategory.recycleBin) {
          await _removeEmptyParents(file.parent, root);
        }
      } on FileSystemException catch (error) {
        errors++;
        lastError = error.message;
      }
    }
    return _DeleteResult(
      ok: errors == 0,
      freed: freed,
      skipped: errors > 0 && freed == 0,
      error: lastError,
    );
  }

  Future<void> _refreshRemaining(CleanItem item) async {
    if (item.scannedFiles == null) return;
    var bytes = 0;
    var count = 0;
    for (final path in item.scannedFiles!) {
      try {
        if (await hasLinkedAncestorAsync(path)) continue;
        final stat = await File(path).stat();
        if (stat.type == FileSystemEntityType.file) {
          bytes += stat.size;
          count++;
        }
      } on FileSystemException {
        /* Keep the failure visible for retry. */
      }
    }
    item.sizeBytes = bytes;
    item.fileCount = count;
  }

  bool _isRecycleMetadata(String path, String root) =>
      p.equals(p.dirname(path), root) && p.basename(path).startsWith(r'$I');

  Future<void> _removeEmptyParents(Directory dir, String root) async {
    while (p.isWithin(root, dir.path)) {
      try {
        await dir.delete();
      } on FileSystemException {
        return;
      }
      dir = dir.parent;
    }
  }
}

class _DeleteResult {
  const _DeleteResult({
    this.ok = false,
    this.freed = 0,
    this.skipped = false,
    this.error,
    this.cancelled = false,
  });
  final bool ok;
  final int freed;
  final bool skipped;
  final String? error;
  final bool cancelled;
}
