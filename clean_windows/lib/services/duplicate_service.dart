import 'dart:io';

import '../models/clean_models.dart';
import 'cache_discovery.dart';
import 'content_digest.dart';
import 'disk_services.dart';
import 'whitelist_service.dart';
import 'file_safety.dart';

class DuplicateGroup {
  DuplicateGroup(this.digest, this.files);
  final String digest;
  final List<FileEntry> files;
}

class DuplicateService {
  DuplicateService({WhitelistService? whitelist, LargeFileService? cleaner})
    : whitelist = whitelist ?? WhitelistService(),
      cleaner = cleaner ?? LargeFileService();
  final WhitelistService whitelist;
  final LargeFileService cleaner;
  int skipped = 0;
  Future<List<DuplicateGroup>> scan(
    String root, {
    int minBytes = 1024 * 1024,
    CleanCancellation? cancellation,
    void Function(String)? onProgress,
  }) async {
    if (!whitelist.readable) throw StateError(whitelist.lastError ?? '白名单未能读取');
    skipped = 0;
    final sizes = <int, List<FileEntry>>{};
    await for (final file in walkFiles(
      Directory(root),
      cancelled: () => cancellation?.requested ?? false,
      exclude: (path) =>
          whitelist.isWhitelisted(path) ||
          protectedCachePath(path) ||
          protectedSystemPath(path),
      onError: (_) => skipped++,
      onPath: onProgress,
    )) {
      try {
        final stat = await file.stat();
        if (stat.size < minBytes || stat.type != FileSystemEntityType.file) {
          continue;
        }
        sizes
            .putIfAbsent(stat.size, () => [])
            .add(
              FileEntry(
                path: file.path,
                name: file.path.replaceAll('\\', '/').split('/').last,
                sizeBytes: stat.size,
                modified: stat.modified,
              ),
            );
      } catch (_) {
        skipped++;
      }
    }
    final hashes = <String, List<FileEntry>>{};
    for (final candidates in sizes.values.where((files) => files.length > 1)) {
      for (final file in candidates) {
        if (cancellation?.requested ?? false) return [];
        onProgress?.call('内容校验 · ${file.path}');
        final digest = await contentDigest(
          file.path,
          cancellation: cancellation,
        );
        if (digest == null) {
          skipped++;
          continue;
        }
        final group = hashes.putIfAbsent(digest, () => []);
        var sameFile = false;
        for (final other in group) {
          if (await FileSystemEntity.identical(file.path, other.path)) {
            sameFile = true;
            break;
          }
        }
        if (!sameFile) group.add(file);
      }
    }
    return hashes.entries
        .where((entry) => entry.value.length > 1)
        .map((entry) => DuplicateGroup(entry.key, entry.value))
        .toList()
      ..sort(
        (a, b) => (b.files.first.sizeBytes * (b.files.length - 1)).compareTo(
          a.files.first.sizeBytes * (a.files.length - 1),
        ),
      );
  }

  Future<CleanReport> recycleSelected(
    List<DuplicateGroup> groups,
    CleanCancellation cancellation,
  ) async {
    final targets = <FileEntry>[];
    final failures = <String>[];
    for (final group in groups) {
      final selected = group.files.where((file) => file.selected).toList();
      if (selected.isEmpty) continue;
      final kept = group.files.where((file) => !file.selected).toList();
      if (kept.isEmpty || cancellation.requested) {
        failures.add('必须保留至少一个副本');
        continue;
      }
      var validKeeper = false;
      FileEntry? keeper;
      for (final file in kept) {
        if (await contentDigest(file.path, cancellation: cancellation) ==
            group.digest) {
          validKeeper = true;
          keeper = file;
          break;
        }
      }
      if (!validKeeper) {
        failures.add('保留副本已改变或不可读取，整组未处理');
        continue;
      }
      for (final file in selected) {
        if (cancellation.requested) break;
        if (await contentDigest(file.path, cancellation: cancellation) ==
            group.digest) {
          file.keeperPath = keeper!.path;
          file.keeperSignature =
              '${keeper.sizeBytes}:${keeper.modified.microsecondsSinceEpoch}';
          targets.add(file);
        } else {
          failures.add('${file.name} 已改变，已跳过');
        }
      }
    }
    cleaner.whitelist = whitelist;
    final result = await cleaner.deleteReviewedFiles(
      targets,
      cancellation: cancellation,
    );
    return CleanReport(
      freedBytes: result.freedBytes,
      recycledBytes: result.recycledBytes,
      deletedCount: result.deletedCount,
      skippedCount: result.skippedCount + failures.length,
      failedCount: result.failedCount,
      cancelled: result.cancelled || cancellation.requested,
      failures: [...failures, ...result.failures],
      completedItemIds: result.completedItemIds,
    );
  }
}
