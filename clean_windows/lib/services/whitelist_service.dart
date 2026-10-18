import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'path_utils.dart';

/// 白名单条目
class WhitelistEntry {
  WhitelistEntry({required this.path, required this.addedAt, this.note});

  final String path;
  final DateTime addedAt;
  final String? note;

  String get name {
    final parts = path.replaceAll('/', '\\').split('\\');
    for (final p in parts.reversed) {
      if (p.isNotEmpty) return p;
    }
    return path;
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'addedAt': addedAt.toIso8601String(),
    if (note != null) 'note': note,
  };

  factory WhitelistEntry.fromJson(Map<String, dynamic> json) {
    return WhitelistEntry(
      path: (json['path'] as String? ?? '').replaceAll('/', '\\'),
      addedAt:
          DateTime.tryParse(json['addedAt'] as String? ?? '') ?? DateTime.now(),
      note: json['note'] as String?,
    );
  }
}

/// 白名单服务：持久化到本地 JSON，扫描时过滤
class WhitelistService {
  WhitelistService({this.storageDirectory, this.writeSnapshot}) {
    _loadSync();
  }

  final List<WhitelistEntry> _entries = [];
  final String? storageDirectory;
  final void Function(File, String)? writeSnapshot;
  File? _file;
  String? lastError;
  bool readable = true;

  List<WhitelistEntry> get entries => List.unmodifiable(_entries);

  bool get isEmpty => _entries.isEmpty;
  int get length => _entries.length;

  File get _storageFile {
    if (_file != null) return _file!;
    final dir = Directory(storageDirectory ?? '$localAppData\\CleanWin');
    dir.createSync(recursive: true);
    return _file = File(p.join(dir.path, 'whitelist.json'));
  }

  void _loadSync() {
    try {
      final f = _storageFile;
      if (!f.existsSync()) return;
      final text = f.readAsStringSync();
      if (text.trim().isEmpty) throw const FormatException('白名单文件为空');
      final decoded = jsonDecode(text);
      if (decoded is! List) throw const FormatException('白名单格式不正确');
      if (decoded.any(
        (entry) =>
            entry is! Map ||
            entry['path'] is! String ||
            !p.windows.isAbsolute(entry['path'] as String),
      )) {
        throw const FormatException('白名单包含无效路径');
      }
      {
        _entries
          ..clear()
          ..addAll(
            decoded.whereType<Map>().map(
              (e) => WhitelistEntry.fromJson(
                e.map((k, v) => MapEntry(k.toString(), v)),
              ),
            ),
          );
      }
    } on Exception catch (_) {
      readable = false;
      lastError = '白名单无法读取，已暂停删除。请检查保护文件后重新启动。';
    }
  }

  void _commit(List<WhitelistEntry> next) {
    if (!readable) throw StateError(lastError!);
    Directory? temporary;
    try {
      final destination = _storageFile;
      temporary = destination.parent.createTempSync('.whitelist-');
      final staged = File(p.join(temporary.path, 'snapshot.json'));
      final data = jsonEncode(next.map((e) => e.toJson()).toList());
      if (writeSnapshot != null) {
        writeSnapshot!(staged, data);
      } else {
        staged.writeAsStringSync(data, flush: true);
      }
      staged.renameSync(destination.path);
      _entries
        ..clear()
        ..addAll(next);
      lastError = null;
    } catch (_) {
      lastError = '白名单保存失败，原有保护仍保留。请检查目录权限或可用空间后重试。';
      rethrow;
    } finally {
      if (temporary != null) {
        try {
          final staged = File(p.join(temporary.path, 'snapshot.json'));
          if (staged.existsSync()) staged.deleteSync();
          temporary.deleteSync();
        } on FileSystemException {
          /* Empty staging cleanup is best effort. */
        }
      }
    }
  }

  Future<void> save() async => _commit([..._entries]);
  Future<void> add(String path, {String? note}) => addAll([path], note: note);
  Future<void> addAll(Iterable<String> paths, {String? note}) async {
    final next = [..._entries];
    for (final path in paths) {
      final normalized = normalizePath(path);
      if (normalized.isEmpty ||
          next.any(
            (entry) =>
                normalizePath(entry.path).toLowerCase() ==
                normalized.toLowerCase(),
          )) {
        continue;
      }
      if (!p.windows.isAbsolute(normalized)) {
        lastError = '请输入完整的文件或文件夹路径';
        throw FormatException(lastError!);
      }
      next.add(
        WhitelistEntry(path: normalized, addedAt: DateTime.now(), note: note),
      );
    }
    _commit(next);
  }

  Future<void> remove(String path) async => _commit(
    _entries
        .where(
          (e) =>
              normalizePath(e.path).toLowerCase() !=
              normalizePath(path).toLowerCase(),
        )
        .toList(),
  );
  Future<void> clear() async => _commit([]);

  bool contains(String path) {
    final n = normalizePath(path);
    return _entries.any(
      (e) => normalizePath(e.path).toLowerCase() == n.toLowerCase(),
    );
  }

  /// path 是否命中白名单（相等，或位于白名单目录之下）
  bool isWhitelisted(String path) {
    final n = normalizePath(path);
    if (n.isEmpty) return false;
    for (final e in _entries) {
      final w = normalizePath(e.path);
      if (w.isEmpty) continue;
      if (n.toLowerCase() == w.toLowerCase()) return true;
      // 目录前缀匹配
      final prefix = w.endsWith('\\') ? w : '$w\\';
      if (n.toLowerCase().startsWith(prefix.toLowerCase())) return true;
    }
    return false;
  }

  static String normalizePath(String path) {
    if (path.trim().isEmpty) return '';
    var normalized = p.windows.normalize(path.trim().replaceAll('/', '\\'));
    while (normalized.length > 3 && normalized.endsWith('\\')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }
}
