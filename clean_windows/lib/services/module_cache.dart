import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'path_utils.dart';

/// 通用临时缓存（内存 + 可选落盘）
class ModuleCache {
  ModuleCache({
    this.namespace = 'default',
    this.ttl = const Duration(minutes: 30),
    this.storageDirectory,
  });
  final String? storageDirectory;

  final String namespace;
  final Duration ttl;

  final Map<String, _CacheEntry> _mem = {};
  bool _loaded = false;
  int _writeVersion = 0;

  File get _file {
    final dir = Directory(storageDirectory ?? '$localAppData\\CleanWin\\cache');
    if (!dir.existsSync()) {
      try {
        dir.createSync(recursive: true);
      } on Exception catch (_) {}
    }
    return File('${dir.path}\\$namespace.json');
  }

  void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = _file;
      if (!f.existsSync()) return;
      final text = f.readAsStringSync();
      if (text.trim().isEmpty) return;
      final map = jsonDecode(text) as Map<String, dynamic>;
      map.forEach((k, v) {
        if (v is Map) {
          final ts =
              DateTime.tryParse(v['t']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          _mem[k] = _CacheEntry(v['v'], ts);
        }
      });
    } on Exception catch (_) {}
  }

  bool _fresh(_CacheEntry e) => DateTime.now().difference(e.time) < ttl;

  T? get<T>(String key) {
    _ensureLoaded();
    final e = _mem[key];
    if (e == null) return null;
    if (!_fresh(e)) {
      _mem.remove(key);
      return null;
    }
    final v = e.value;
    if (v is T) return v;
    return null;
  }

  Map<String, dynamic>? getMap(String key) {
    _ensureLoaded();
    final e = _mem[key];
    if (e == null || !_fresh(e)) return null;
    final v = e.value;
    if (v is Map<String, dynamic>) return v;
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), val));
    }
    return null;
  }

  List<dynamic>? getList(String key) {
    _ensureLoaded();
    final e = _mem[key];
    if (e == null || !_fresh(e)) return null;
    final v = e.value;
    if (v is List) return v;
    return null;
  }

  void set(String key, Object? value) {
    _ensureLoaded();
    _mem[key] = _CacheEntry(value, DateTime.now());
    _persist();
  }

  /// Large scan snapshots encode and write off the UI isolate. An older write
  /// must never overwrite a newer set, clear, invalidate, or durable save.
  Future<void> setAsync(String key, Object? value) async {
    _ensureLoaded();
    _mem[key] = _CacheEntry(value, DateTime.now());
    await _persistAsync();
  }

  Future<void> _persistAsync({bool rethrowErrors = false}) async {
    final version = ++_writeVersion;
    final destination =
        '${Directory(storageDirectory ?? '$localAppData\\CleanWin\\cache').path}\\$namespace.json';
    final data = {
      for (final entry in _mem.entries)
        entry.key: {
          'v': entry.value.value,
          't': entry.value.time.toIso8601String(),
        },
    };
    String? temporary;
    try {
      temporary = await _writeSnapshotAsync(destination, data);
      // Commit is a single metadata operation, with no await between the
      // generation check and rename so synchronous preference saves stay safe.
      if (version == _writeVersion) {
        File(temporary).renameSync(destination);
      } else if (rethrowErrors) {
        throw StateError('缓存保存已被新的更改取代');
      }
    } catch (_) {
      if (rethrowErrors) rethrow;
      // Cache failures must not turn a successful cleanup into a failed task.
    } finally {
      if (temporary != null) {
        try {
          await File(temporary).delete();
        } on FileSystemException {
          /* Already renamed or removed. */
        }
        try {
          await File(temporary).parent.delete();
        } on FileSystemException {
          /* Only remove our empty write directory, never recurse. */
        }
      }
    }
  }

  /// Keep durable preference writes off the UI isolate while retaining rollback.
  Future<void> setDurableAsync(String key, Object? value) async {
    _ensureLoaded();
    final previous = _mem[key];
    final pending = _CacheEntry(value, DateTime.now());
    _mem[key] = pending;
    try {
      await _persistAsync(rethrowErrors: true);
    } catch (_) {
      if (identical(_mem[key], pending)) {
        if (previous == null) {
          _mem.remove(key);
        } else {
          _mem[key] = previous;
        }
      }
      rethrow;
    }
  }

  /// Invalidate memory immediately; encode and write remaining snapshots later.
  Future<void> invalidateAsync(String key) async {
    _ensureLoaded();
    _mem.remove(key);
    await _persistAsync();
  }

  /// Preferences must not appear saved when their disk write failed.
  void setDurable(String key, Object? value) {
    _ensureLoaded();
    final previous = _mem[key];
    _mem[key] = _CacheEntry(value, DateTime.now());
    try {
      _persist(rethrowErrors: true);
    } catch (_) {
      if (previous == null) {
        _mem.remove(key);
      } else {
        _mem[key] = previous;
      }
      rethrow;
    }
  }

  void invalidate(String key) {
    _ensureLoaded();
    _mem.remove(key);
    _persist();
  }

  void clear() {
    _mem.clear();
    _persist();
  }

  void _persist({bool rethrowErrors = false}) {
    _writeVersion++;
    try {
      final data = <String, dynamic>{};
      _mem.forEach((k, v) {
        data[k] = {'v': v.value, 't': v.time.toIso8601String()};
      });
      final encoded = jsonEncode(data);
      if (rethrowErrors) {
        final destination = _file;
        final temporary = File(
          '${destination.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
        );
        try {
          temporary.writeAsStringSync(encoded, flush: true);
          temporary.renameSync(destination.path);
        } finally {
          if (temporary.existsSync()) temporary.deleteSync();
        }
      } else {
        _file.writeAsStringSync(encoded);
      }
    } on Exception catch (_) {
      if (rethrowErrors) rethrow;
    }
  }
}

Future<String> _writeSnapshotAsync(
  String destination,
  Map<String, dynamic> data,
) => Isolate.run(() {
  final parent = File(destination).parent..createSync(recursive: true);
  // OS-generated directories cannot collide with simultaneous durable writes
  // or other isolates, even when the platform clock returns equal timestamps.
  final temporary = parent.createTempSync('.cache-write-');
  final file = File('${temporary.path}${Platform.pathSeparator}snapshot.tmp');
  try {
    file.writeAsStringSync(jsonEncode(data), flush: true);
    return file.path;
  } catch (_) {
    if (file.existsSync()) file.deleteSync();
    temporary.deleteSync();
    rethrow;
  }
});

class _CacheEntry {
  _CacheEntry(this.value, this.time);
  final Object? value;
  final DateTime time;
}

/// 全局缓存注册表（按模块）
class AppCache {
  static final scan = ModuleCache(namespace: 'scan');
  static final largeFiles = ModuleCache(
    namespace: 'large_files',
    ttl: const Duration(hours: 2),
  );
  static final apps = ModuleCache(
    namespace: 'apps',
    ttl: const Duration(hours: 6),
  );
  static final startup = ModuleCache(
    namespace: 'startup',
    ttl: const Duration(hours: 2),
  );
  static final registry = ModuleCache(
    namespace: 'registry',
    ttl: const Duration(hours: 2),
  );
  static final disk = ModuleCache(
    namespace: 'disk',
    ttl: const Duration(hours: 2),
  );
  static final downloads = ModuleCache(namespace: 'downloads');

  static void clearAll() {
    scan.clear();
    largeFiles.clear();
    apps.clear();
    startup.clear();
    registry.clear();
    disk.clear();
    downloads.clear();
  }
}
