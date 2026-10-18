import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'module_cache.dart';
import '../models/clean_models.dart';
import 'clean_service.dart';
import 'whitelist_service.dart';
import 'cache_discovery.dart';

/// 目录占用节点
class DirUsage {
  DirUsage({
    required this.path,
    required this.name,
    required this.sizeBytes,
    this.fileCount = 0,
    this.children = const [],
    this.isDirectory = true,
    this.unreadablePaths = const [],
  });

  final String path;
  final String name;
  final int sizeBytes;
  final int fileCount;
  final List<DirUsage> children;
  final bool isDirectory;
  final List<String> unreadablePaths;

  bool get isFile => !isDirectory;
}

/// 磁盘分析服务：带内存缓存、可并行、可取消
class DiskAnalysisService {
  DiskAnalysisService({ModuleCache? cache})
    : _diskCache = cache ?? AppCache.disk;
  final ModuleCache _diskCache;

  /// path(lower) -> DirUsage
  final Map<String, DirUsage> _cache = {};

  void clearCache() {
    _cache.clear();
    _diskCache.clear();
  }

  void invalidate(String path) {
    // Child totals must also be refreshed, otherwise the root reuses old sizes.
    clearCache();
  }

  bool isCached(String path) => _cache.containsKey(_norm(path));

  String _norm(String p) =>
      p.replaceAll('/', '\\').toLowerCase().replaceAll(RegExp(r'\\+$'), '');

  /// 分析一层子目录占用（并行），结果进缓存
  Future<DirUsage> analyzeDirectory(
    String path, {
    int maxConcurrent = 8,
    void Function(DirUsage partial)? onProgress,
    CancelToken? cancel,
  }) async {
    final key = _norm(path);
    final cached = _cache[key] ?? _fromCache(_diskCache.getMap(key));
    // 仅当已有「一层子项」时才可直接用缓存做钻取
    if (cached != null &&
        (cached.children.isNotEmpty ||
            cached.fileCount == 0 && cached.sizeBytes == 0)) {
      _cache[key] = cached;
      return cached;
    }

    final dir = Directory(path);
    if (!dir.existsSync()) {
      return DirUsage(
        path: path,
        name: _name(path),
        sizeBytes: 0,
        unreadablePaths: [path],
      );
    }

    List<FileSystemEntity> entries;
    try {
      entries = await dir.list(followLinks: false).toList();
    } on Exception catch (_) {
      return DirUsage(
        path: path,
        name: _name(path),
        sizeBytes: 0,
        unreadablePaths: [path],
      );
    }

    final children = <DirUsage>[];
    final rootUnreadable = <String>[];
    var fileBytes = 0;
    var fileCount = 0;

    // 先放文件（快）
    for (final e in entries) {
      if (cancel?.cancelled ?? false) break;
      if (e is File) {
        try {
          final s = await e.length();
          fileBytes += s;
          fileCount++;
          children.add(
            DirUsage(
              path: e.path,
              name: _name(e.path),
              sizeBytes: s,
              fileCount: 1,
              isDirectory: false,
            ),
          );
        } on Exception catch (_) {
          rootUnreadable.add(e.path);
        }
      }
    }

    // 子目录并行求大小
    final dirs = entries.whereType<Directory>().toList();
    final results = <DirUsage>[];
    var index = 0;

    Future<void> worker() async {
      while (true) {
        if (cancel?.cancelled ?? false) return;
        if (index >= dirs.length) return;
        final d = dirs[index++];
        final name = _name(d.path).toLowerCase();
        if (name == '\$recycle.bin' ||
            name == 'system volume information' ||
            name == 'recovery') {
          rootUnreadable.add(d.path);
          continue;
        }
        final child = await _dirSize(d, cancel: cancel);
        results.add(child);
        // 进度：合并已有部分
        if (onProgress != null) {
          final partial = DirUsage(
            path: path,
            name: _name(path),
            sizeBytes:
                fileBytes + results.fold<int>(0, (s, c) => s + c.sizeBytes),
            fileCount:
                fileCount + results.fold<int>(0, (s, c) => s + c.fileCount),
            children: [...results, ...children]
              ..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes)),
            unreadablePaths: [
              ...rootUnreadable,
              ...results.expand((child) => child.unreadablePaths),
            ],
          );
          onProgress(partial);
        }
      }
    }

    final workers = List.generate(maxConcurrent.clamp(1, 16), (_) => worker());
    await Future.wait(workers);

    final all = [...results, ...children]
      ..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    final total = fileBytes + results.fold<int>(0, (s, c) => s + c.sizeBytes);
    final files = fileCount + results.fold<int>(0, (s, c) => s + c.fileCount);

    final usage = DirUsage(
      path: path,
      name: _name(path),
      sizeBytes: total,
      fileCount: files,
      children: all,
      unreadablePaths: [
        ...rootUnreadable,
        ...results.expand((child) => child.unreadablePaths),
      ],
    );
    if (!(cancel?.cancelled ?? false)) {
      _cache[key] = usage;
      _persistUsage(key, usage);
    }
    return usage;
  }

  void _persistUsage(String key, DirUsage usage) {
    _diskCache.set(key, {
      'path': usage.path,
      'name': usage.name,
      'sizeBytes': usage.sizeBytes,
      'fileCount': usage.fileCount,
      'isDirectory': usage.isDirectory,
      'unreadablePaths': usage.unreadablePaths,
      'children': usage.children
          .map(
            (c) => {
              'path': c.path,
              'name': c.name,
              'sizeBytes': c.sizeBytes,
              'fileCount': c.fileCount,
              'isDirectory': c.isDirectory,
            },
          )
          .toList(),
    });
  }

  DirUsage? _fromCache(dynamic raw) {
    if (raw is! Map) return null;
    final m = raw.map((k, v) => MapEntry(k.toString(), v));
    if (!m.containsKey('unreadablePaths')) return null;
    final childrenRaw = m['children'];
    final children = <DirUsage>[];
    if (childrenRaw is List) {
      for (final c in childrenRaw) {
        if (c is! Map) continue;
        final cm = c.map((k, v) => MapEntry(k.toString(), v));
        children.add(
          DirUsage(
            path: cm['path']?.toString() ?? '',
            name: cm['name']?.toString() ?? '',
            sizeBytes: (cm['sizeBytes'] as num?)?.toInt() ?? 0,
            fileCount: (cm['fileCount'] as num?)?.toInt() ?? 0,
            isDirectory: cm['isDirectory'] != false,
          ),
        );
      }
    }
    return DirUsage(
      path: m['path']?.toString() ?? '',
      name: m['name']?.toString() ?? '',
      sizeBytes: (m['sizeBytes'] as num?)?.toInt() ?? 0,
      fileCount: (m['fileCount'] as num?)?.toInt() ?? 0,
      children: children,
      isDirectory: m['isDirectory'] != false,
      unreadablePaths: (m['unreadablePaths'] as List? ?? [])
          .map((value) => '$value')
          .toList(),
    );
  }

  Future<DirUsage> _dirSize(Directory dir, {CancelToken? cancel}) async {
    final key = _norm(dir.path);
    final hit = _cache[key] ?? _fromCache(_diskCache.getMap(key));
    if (hit != null) {
      _cache[key] = hit;
      return hit;
    }

    var total = 0;
    var files = 0;
    final unreadable = <String>[];
    try {
      await for (final e in walkFiles(
        dir,
        cancelled: () => cancel?.cancelled ?? false,
        onError: (error) => unreadable.add(error.path ?? dir.path),
      )) {
        if (cancel?.cancelled ?? false) break;
        if (e is File) {
          try {
            total += await e.length();
            files++;
          } on Exception catch (_) {
            unreadable.add(e.path);
          }
        }
        if (files % 300 == 0 && files > 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
    } on Exception catch (_) {
      unreadable.add(dir.path);
    }

    final usage = DirUsage(
      path: dir.path,
      name: _name(dir.path),
      sizeBytes: total,
      fileCount: files,
      unreadablePaths: unreadable,
    );
    if (!(cancel?.cancelled ?? false)) {
      _cache[key] = usage;
      _persistUsage(key, usage);
    }
    return usage;
  }

  /// 可用磁盘列表
  List<String> availableDrives() {
    final drives = <String>[];
    for (final code in List.generate(26, (i) => 65 + i)) {
      final letter = String.fromCharCode(code);
      try {
        if (Directory('$letter:\\').existsSync()) drives.add(letter);
      } on Exception catch (_) {}
    }
    return drives;
  }

  Future<({int total, int free})?> driveSpace(String letter) async {
    try {
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        "\$d=Get-PSDrive $letter; \"\$(\$d.Used+\$d.Free) \$(\$d.Free)\"",
      ], stdoutEncoding: utf8);
      final parts = r.stdout.toString().trim().split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        return (
          total: int.tryParse(parts[0]) ?? 0,
          free: int.tryParse(parts[1]) ?? 0,
        );
      }
    } on Exception catch (_) {}
    return null;
  }

  String _name(String path) {
    final parts = path.replaceAll('/', '\\').split('\\');
    for (final p in parts.reversed) {
      if (p.isNotEmpty) return p;
    }
    return path;
  }
}

/// 简单取消令牌
class CancelToken {
  bool _cancelled = false;
  bool get cancelled => _cancelled;
  void cancel() => _cancelled = true;
  void reset() => _cancelled = false;
}

/// 大文件扫描（异步、可取消、不阻塞 UI）
class LargeFileService {
  LargeFileService({CleanService? cleaner})
    : _cleaner = cleaner ?? CleanService();
  final CleanService _cleaner;
  WhitelistService? whitelist;
  int unreadable = 0;
  bool complete = false;
  Future<CleanReport> deleteReviewedFiles(
    List<FileEntry> files, {
    CleanCancellation? cancellation,
    void Function(CleanItem, String, int, int)? onProgress,
  }) {
    _cleaner.whitelist = whitelist ?? WhitelistService();
    return _cleaner.cleanItems(
      [
        for (final file in files)
          CleanItem(
            id: file.path,
            name: file.name,
            path: file.path,
            sizeBytes: file.sizeBytes,
            fileCount: 1,
            category: CleanCategory.downloads,
            requiredKeeperPath: file.keeperPath,
            requiredKeeperSignature: file.keeperSignature,
            scannedFiles: [file.path],
            fileSignatures: {
              file.path:
                  '${file.sizeBytes}:${file.modified.microsecondsSinceEpoch}',
            },
          ),
      ],
      recycle: true,
      cancellation: cancellation,
      onItem: onProgress,
    );
  }

  /// 读取缓存的大文件列表
  List<FileEntry> loadCached(String root, int minBytes) {
    final key = 'lf_${root}_$minBytes';
    final raw = AppCache.largeFiles.getList(key);
    if (raw == null) return [];
    return raw.whereType<Map>().map((m) {
      return FileEntry(
        path: (m['path'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        sizeBytes: (m['sizeBytes'] as num?)?.toInt() ?? 0,
        modified:
            DateTime.tryParse((m['modified'] ?? '').toString()) ??
            DateTime.now(),
      );
    }).toList();
  }

  Future<void> saveCached(
    String root,
    int minBytes,
    List<FileEntry> files,
  ) async {
    final key = 'lf_${root}_$minBytes';
    await AppCache.largeFiles.setAsync(
      key,
      files
          .map(
            (f) => {
              'path': f.path,
              'name': f.name,
              'sizeBytes': f.sizeBytes,
              'modified': f.modified.toIso8601String(),
            },
          )
          .toList(),
    );
  }

  Stream<FileEntry> scanLargeFiles(
    String root, {
    int minBytes = 500 * 1024 * 1024,
    void Function(int found, String currentDir)? onProgress,
    CancelToken? cancel,
  }) async* {
    unreadable = 0;
    complete = false;
    final dir = Directory(root);
    if (!dir.existsSync()) return;

    final queue = <String>[root];
    var found = 0;
    var processed = 0;

    while (queue.isNotEmpty) {
      if (cancel?.cancelled ?? false) return;
      final current = queue.removeLast();
      List<FileSystemEntity> entries;
      try {
        entries = await Directory(current)
            .list(followLinks: false)
            .toList()
            .timeout(const Duration(seconds: 5));
      } on Exception catch (_) {
        unreadable++;
        continue;
      }

      if (cancel?.cancelled ?? false) return;
      onProgress?.call(found, current);

      for (final e in entries) {
        if (cancel?.cancelled ?? false) return;
        if (e is File) {
          try {
            final size = await e.length();
            if (size >= minBytes) {
              found++;
              DateTime modified;
              try {
                modified = e.lastModifiedSync();
              } on Exception catch (_) {
                modified = DateTime.now();
              }
              yield FileEntry(
                path: e.path,
                name: e.path.split(Platform.pathSeparator).last,
                sizeBytes: size,
                modified: modified,
              );
            }
          } on Exception catch (_) {
            unreadable++;
          }
        } else if (e is Directory) {
          final name = e.path.split(Platform.pathSeparator).last.toLowerCase();
          if (name == '\$recycle.bin' ||
              name == 'system volume information' ||
              name == 'windows') {
            continue;
          }
          queue.add(e.path);
        }
      }

      processed++;
      if (processed % 4 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    complete = true;
    onProgress?.call(found, root);
  }
}

class FileEntry {
  FileEntry({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.modified,
    this.selected = false,
  });

  final String path;
  final String name;
  final int sizeBytes;
  final DateTime modified;
  bool selected;
  String? keeperPath;
  String? keeperSignature;
}
