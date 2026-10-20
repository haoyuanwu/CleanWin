import 'dart:io';

import 'package:clean_windows/models/clean_models.dart';
import 'package:clean_windows/services/cache_discovery.dart';
import 'package:clean_windows/services/clean_service.dart';
import 'package:clean_windows/services/process_utils.dart';
import 'package:clean_windows/services/scan_service.dart';
import 'package:clean_windows/services/whitelist_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _Whitelist implements WhitelistService {
  _Whitelist(this.protected);
  final String protected;
  @override
  bool get readable => true;
  @override
  bool isWhitelisted(String path) =>
      p.equals(path, protected) || p.isWithin(protected, path);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestDirectory implements Directory {
  _TestDirectory(this.path, this.children);
  @override
  final String path;
  final List<FileSystemEntity>? children;
  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) {
    if (children == null) {
      return Stream.error(
        FileSystemException(
          'Access denied',
          path,
          const OSError('Access denied', 5),
        ),
      );
    }
    return Stream.fromIterable(children!);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory fixture;
  late Map<String, String> environment;
  late ScanService service;

  File put(String path, [int bytes = 7]) {
    final file = File(path)..parent.createSync(recursive: true);
    file.writeAsBytesSync(List.filled(bytes, 1));
    file.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 10)));
    return file;
  }

  setUp(() {
    fixture = Directory.systemTemp.createTempSync('scan_test_').absolute;
    environment = {
      'USERPROFILE': fixture.path,
      'DOWNLOADS': p.join(fixture.path, 'Downloads'),
      'USER_SID': 'S-1-5-21-100',
      'ProgramFiles': p.join(fixture.path, 'Program Files'),
      'ProgramFiles(x86)': p.join(fixture.path, 'Program Files (x86)'),
      'LOCALAPPDATA': p.join(fixture.path, 'AppData', 'Local'),
      'APPDATA': p.join(fixture.path, 'AppData', 'Roaming'),
      'SystemRoot': p.join(fixture.path, 'Windows'),
      'SystemDrive': fixture.path,
      'ProgramData': p.join(fixture.path, 'ProgramData'),
      'TEMP': p.join(fixture.path, 'RedirectedTemp'),
      'TMP': p.join(fixture.path, 'RedirectedTemp'),
    };
    service = ScanService(environment: environment, driveRoots: const []);
    ProcessUtils.debugSkip = true;
  });

  tearDown(() {
    ProcessUtils.debugSkip = false;
    fixture.deleteSync(recursive: true);
  });

  test(
    'finds small deep vendor, Store, LocalLow and ProgramData caches',
    () async {
      final expected = [
        p.join(
          environment['APPDATA']!,
          'Vendor',
          'App',
          'v1',
          'User',
          'Default',
          'Code Cache',
          'data',
        ),
        p.join(
          environment['LOCALAPPDATA']!,
          'Microsoft',
          'Teams',
          'Cache',
          'data',
        ),
        p.join(
          environment['LOCALAPPDATA']!,
          'Packages',
          'Test.App',
          'LocalCache',
          'Roaming',
          'App',
          'GPUCache',
          'data',
        ),
        p.join(
          environment['LOCALAPPDATA']!,
          'Packages',
          'Test.App',
          'TempState',
          'data',
        ),
        p.join(fixture.path, 'AppData', 'LocalLow', 'Vendor', 'Cache', 'data'),
        p.join(environment['ProgramData']!, 'Vendor', 'Cache', 'data'),
      ];
      for (final path in expected) {
        put(path);
      }
      for (final folder in [
        'MyCacheBackup',
        'Service Worker',
        'blob_storage',
        'UserData',
        'Installer Cache',
      ]) {
        put(p.join(environment['APPDATA']!, 'Other', folder, 'keep'));
      }
      final result = await service.scanAll(
        categories: {CleanCategory.appCache},
      );
      expect(result[CleanCategory.appCache]!.error, isNull);
      final files = result[CleanCategory.appCache]!.items.expand(
        (i) => i.scannedFiles!,
      );
      expect(files, unorderedEquals(expected));
      expect(
        result[CleanCategory.appCache]!.totalSizeBytes,
        expected.length * 7,
      );
    },
  );

  test(
    'browser custom profiles and root shader caches exclude personal data',
    () async {
      final root = p.join(
        environment['LOCALAPPDATA']!,
        'Google',
        'Chrome',
        'User Data',
      );
      final cache = put(
        p.join(root, 'CustomProfile', 'Cache', 'Cache_Data', 'data'),
      );
      final shader = put(p.join(root, 'ShaderCache', 'GPUCache', 'shader'));
      final cookies = put(p.join(root, 'CustomProfile', 'Network', 'Cookies'));
      final password = put(p.join(root, 'CustomProfile', 'Login Data'));
      final result = await service.scanAll(
        categories: {CleanCategory.browserCache, CleanCategory.appCache},
      );
      expect(result.values.every((c) => c.error == null), isTrue);
      final files = result.values
          .expand((c) => c.items)
          .expand((i) => i.scannedFiles!);
      expect(files, unorderedEquals([cache.path, shader.path]));
      expect(cookies.existsSync() && password.existsSync(), isTrue);
    },
  );

  test(
    'depth limit prunes and nested cache directories do not overlap',
    () async {
      final root = Directory(p.join(fixture.path, 'Discovery'));
      put(p.join(root.path, 'App', 'Cache', 'GPUCache', 'data'));
      put(p.join(root.path, 'Deep', 'a', 'b', 'Cache', 'data'));
      final caches = await discoverCaches(root, maxDepth: 2).toList();
      expect(caches.map((d) => d.path), [p.join(root.path, 'App', 'Cache')]);
    },
  );

  test(
    'system cache honors redirected temp and does not double count files',
    () async {
      put(p.join(environment['TEMP']!, 'temp.bin'), 9);
      put(p.join(environment['LOCALAPPDATA']!, 'Temp', 'temp.bin'), 11);
      put(p.join(environment['LOCALAPPDATA']!, 'D3DSCache', 'shader'), 13);
      final result = await service.scanAll(
        categories: {CleanCategory.systemCache},
      );
      expect(result[CleanCategory.systemCache]!.error, isNull);
      expect(result[CleanCategory.systemCache]!.totalSizeBytes, 20);
    },
  );

  test(
    'cleaning respects scan filters, nested whitelist and later-created files',
    () async {
      final root = p.join(
        environment['LOCALAPPDATA']!,
        'Microsoft',
        'Windows',
        'Explorer',
      );
      final thumbnail = put(p.join(root, 'thumbcache_32.db'), 10);
      final unrelated = put(p.join(root, 'settings.ini'), 20);
      final database = put(p.join(root, 'settings.db'), 20);
      final protected = put(p.join(root, 'Protected', 'thumbcache_96.db'), 30);
      service.whitelist = _Whitelist(p.dirname(protected.path));
      final result = await service.scanAll(
        categories: {CleanCategory.systemCache},
      );
      final items = result[CleanCategory.systemCache]!.items;
      expect(items.expand((i) => i.scannedFiles!), [thumbnail.path]);
      final later = put(p.join(root, 'thumbcache_new.db'), 40);
      for (final item in items) {
        item.selected = true;
      }
      final report = await CleanService().cleanItems(items);
      expect(report.freedBytes, 10);
      expect(thumbnail.existsSync(), isFalse);
      expect(
        [unrelated, database, protected, later].every((f) => f.existsSync()),
        isTrue,
      );
    },
  );

  test('rescanning clears deduplication state', () async {
    put(p.join(environment['TEMP']!, 'data'), 12);
    final first = await service.scanAll(
      categories: {CleanCategory.systemCache},
    );
    final second = await service.scanAll(
      categories: {CleanCategory.systemCache},
    );
    expect(first[CleanCategory.systemCache]!.totalSizeBytes, 12);
    expect(second[CleanCategory.systemCache]!.totalSizeBytes, 12);
  });

  test(
    'denied child reports an issue without hiding accessible siblings',
    () async {
      final good = put(p.join(fixture.path, 'Good', 'Cache', 'data'));
      final denied = _TestDirectory(p.join(fixture.path, 'Denied'), null);
      final root = _TestDirectory(fixture.path, [
        denied,
        Directory(p.join(fixture.path, 'Good')),
      ]);
      final errors = <FileSystemException>[];
      final files = await walkFiles(root, onError: errors.add).toList();
      expect(files.map((f) => f.path), [good.path]);
      expect(errors.single.path, denied.path);
      errors.clear();
      final caches = await discoverCaches(root, onError: errors.add).toList();
      expect(caches.map((d) => d.path), [good.parent.path]);
      expect(errors.single.path, denied.path);
    },
  );

  test('memory dumps remain unselected after scanning', () async {
    put(p.join(environment['SystemRoot']!, 'Minidump', 'crash.dmp'));
    put(p.join(environment['SystemRoot']!, 'MEMORY.DMP'));
    final result = await service.scanAll(
      categories: {CleanCategory.memoryDumps},
    );
    expect(result[CleanCategory.memoryDumps]!.items, hasLength(2));
    expect(
      result[CleanCategory.memoryDumps]!.items.every((i) => !i.selected),
      isTrue,
    );
  });
  test(
    'path progress arrives before category completion and clears at finish',
    () async {
      put(p.join(environment['LOCALAPPDATA']!, 'Vendor', 'Cache', 'data'));
      final progress = <ScanProgress>[];
      var completed = false;
      var sawLivePath = false;
      await service.scanAll(
        categories: {CleanCategory.appCache},
        onProgress: (event) {
          progress.add(event);
          if (event.currentPath.isNotEmpty) {
            expect(completed, isFalse);
            expect(event.currentCategory, CleanCategory.appCache);
            expect(event.completedCategories, 0);
            expect(event.totalCategories, 1);
            sawLivePath = true;
          }
        },
        onCategoryDone: (_) {
          completed = true;
        },
      );
      expect(sawLivePath, isTrue);
      expect(progress.last.currentPath, isEmpty);
      expect(progress.last.completedCategories, 1);
      final copied = progress
          .firstWhere((p) => p.currentPath.isNotEmpty)
          .copyWith(foundBytes: 7);
      expect(copied.currentPath, isNotEmpty);
      expect(copied.copyWith(currentPath: '').currentPath, isEmpty);
    },
  );

  test(
    'traversal reports nested directories and files before they are counted',
    () async {
      final root = Directory(p.join(fixture.path, 'Walker'));
      final file = put(p.join(root.path, 'nested', 'data.bin'));
      final reported = <String>[];
      final files = await walkFiles(root, onPath: reported.add).toList();
      expect(files.map((file) => file.path), [file.path]);
      expect(reported, [root.path, file.parent.path, file.path]);
      final discovery = <String>[];
      await discoverCaches(root, onPath: discovery.add).toList();
      expect(discovery, [root.path, file.parent.path]);
    },
  );
}
