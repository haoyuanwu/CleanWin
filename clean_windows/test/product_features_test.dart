import 'dart:convert';
import 'dart:io';

import 'package:clean_windows/models/clean_models.dart';
import 'package:clean_windows/models/scan_options.dart';
import 'package:clean_windows/services/activity_service.dart';
import 'package:clean_windows/services/clean_service.dart';
import 'package:clean_windows/services/content_digest.dart';
import 'package:clean_windows/services/disk_services.dart';
import 'package:clean_windows/services/duplicate_service.dart';
import 'package:clean_windows/services/file_move_service.dart';
import 'package:clean_windows/services/file_safety.dart';
import 'package:clean_windows/services/module_cache.dart';
import 'package:clean_windows/services/process_utils.dart';
import 'package:clean_windows/services/registry_backups.dart';
import 'package:clean_windows/services/registry_scan_service.dart';
import 'package:clean_windows/services/scan_service.dart';
import 'package:clean_windows/services/whitelist_service.dart';
import 'package:clean_windows/widgets/disk_treemap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory fixture;
  setUp(
    () =>
        fixture = Directory('.dart_tool')
            .createTempSync('product_features_')
            .absolute,
  );
  tearDown(() {
    expect(
      p.isWithin(Directory('.dart_tool').absolute.path, fixture.path),
      isTrue,
    );
    fixture.deleteSync(recursive: true);
  });
  File put(String name, String content) {
    final file = File(p.join(fixture.path, name));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  test('duplicate content checks distinguish equal sizes and preserve the last copy', () async {
    final a = put('a.bin', '01234567');
    final b = put('b.bin', '01234567');
    final c = put('c.bin', '76543210');
    var recycled = 0;
    final service = DuplicateService(
      whitelist: WhitelistService(storageDirectory: fixture.path),
      cleaner: LargeFileService(
        cleaner: CleanService(
          recycler: (path) async {
            recycled++;
            await File(path).rename('$path.recycled');
            return true;
          },
        ),
      ),
    );
    final groups = await service.scan(fixture.path, minBytes: 1);
    expect(groups, hasLength(1));
    expect(groups.single.files, hasLength(2));
    for (final file in groups.single.files) {
      file.selected = true;
    }
    expect(
      (await service.recycleSelected(
        groups,
        CleanCancellation(),
      )).completedItemIds,
      isEmpty,
    );
    expect(recycled, 0);
    groups.single.files.first.selected = false;
    final keeper = groups.single.files.first.path;
    final result = await service.recycleSelected(groups, CleanCancellation());
    expect(result.deletedCount, 1);
    expect(result.recycledBytes, 8);
    expect(result.freedBytes, 0);
    expect(File(keeper).readAsStringSync(), '01234567');
    expect(c.readAsStringSync(), '76543210');
    expect(a.existsSync() || b.existsSync(), isTrue);
  });
  test('changed or missing keeper prevents duplicate deletion', () async {
    put('a.bin', 'same');
    put('b.bin', 'same');
    final service = DuplicateService(
      whitelist: WhitelistService(storageDirectory: fixture.path),
      cleaner: LargeFileService(
        cleaner: CleanService(
          recycler: (_) async => throw StateError('must not recycle'),
        ),
      ),
    );
    final groups = await service.scan(fixture.path, minBytes: 1);
    groups.single.files.last.selected = true;
    File(groups.single.files.first.path).writeAsStringSync('changed');
    final report = await service.recycleSelected(groups, CleanCancellation());
    expect(report.completedItemIds, isEmpty);
    expect(File(groups.single.files.last.path).existsSync(), isTrue);
  });
  test('cancelled content hashing does not read or delete files', () async {
    final file = put('content', 'same');
    expect(
      await contentDigest(
        file.path,
        cancellation: CleanCancellation()..cancel(),
      ),
      isNull,
    );
    expect(file.readAsStringSync(), 'same');
  });
  test(
    'verified movement refuses existing targets and retains source on mismatch',
    () async {
      final source = put('source/data.bin', 'content');
      final target = put('target/data.bin', 'existing');
      final mover = FileMoveService(
        WhitelistService(storageDirectory: fixture.path),
      );
      final signature = fileSignature(source.statSync());
      await expectLater(
        mover.move(
          source.path,
          target.parent.path,
          signature,
          CleanCancellation(),
        ),
        throwsStateError,
      );
      expect(source.readAsStringSync(), 'content');
      expect(target.readAsStringSync(), 'existing');
      target.deleteSync();
      source.writeAsStringSync('changed content');
      await expectLater(
        mover.move(
          source.path,
          target.parent.path,
          signature,
          CleanCancellation(),
        ),
        throwsStateError,
      );
      final result = await mover.move(
        source.path,
        target.parent.path,
        fileSignature(source.statSync()),
        CleanCancellation(),
      );
      expect(result, startsWith('已移动'));
      expect(source.existsSync(), isFalse);
      expect(target.readAsStringSync(), 'changed content');
    },
  );
  test('journal retains cancelled and recycled outcomes across instances', () {
    ModuleCache cache() =>
        ModuleCache(namespace: 'history', storageDirectory: fixture.path);
    ActivityJournal(cache: cache()).record(
      'Downloads',
      CleanReport(
        freedBytes: 0,
        recycledBytes: 1024,
        deletedCount: 1,
        skippedCount: 0,
        failedCount: 0,
        cancelled: true,
      ),
    );
    final record = ActivityJournal(cache: cache()).records.single;
    expect(record['cancelled'], isTrue);
    expect(record['recycled'], 1024);
    expect(record['freed'], 0);
  });
  test('task cancellation is one-shot and completed tasks disappear', () {
    final board = TaskBoard();
    var count = 0;
    board.update('test', 'task', 'running', cancel: () => count++);
    board.cancel('test');
    board.cancel('test');
    expect(count, 1);
    expect(board.tasks['test']!.cancel, isNull);
    board.finish('test');
    expect(board.tasks, isEmpty);
    board.dispose();
  });
  test('map areas match bytes and a refreshed directory does not reuse old child totals', () async {
    final nodes = [
      for (final bytes in [90, 9, 1])
        DirUsage(path: '$bytes', name: '$bytes', sizeBytes: bytes),
    ];
    final tiles = layoutDiskMap(nodes, const Size(1000, 500));
    for (final tile in tiles) {
      expect(
        tile.rect.width * tile.rect.height / 500000,
        closeTo(tile.node.sizeBytes / 100, .000001),
      );
    }
    final file = put('folder/data.bin', 'old');
    final service = DiskAnalysisService(
      cache: ModuleCache(namespace: 'disk', storageDirectory: fixture.path),
    );
    final first = await service.analyzeDirectory(file.parent.path);
    file.writeAsStringSync('longer new content');
    service.invalidate(file.parent.path);
    final second = await service.analyzeDirectory(file.parent.path);
    expect(second.sizeBytes, greaterThan(first.sizeBytes));
  });
  test('registry backup restore is limited to supported values and refuses overwrites', () async {
    final issue = RegistryIssue(
      title: 'app',
      detail: '',
      hive: 'HKCU',
      keyPath: r'Software\Microsoft\Windows\CurrentVersion\App Paths\app.exe',
      valueName: '',
      severity: 'warn',
      category: 'appPaths',
      valueKind: 'String',
      data: r'C:\Missing\app.exe',
      target: r'C:\Missing\app.exe',
      deletable: true,
    );
    put(
      'backups/app.json',
      jsonEncode({...issue.toJson(), 'BackedUpAtUtc': '2026-10-18T00:00:00Z'}),
    );
    final backups = await RegistryBackups(
      directory: p.join(fixture.path, 'backups'),
    ).list();
    expect(backups, hasLength(1));
    String? script;
    final service = RegistryScanService(
      cache: ModuleCache(namespace: 'registry', storageDirectory: fixture.path),
      powerShellRunner: (value, _) async {
        script = value;
        return PsResult(exitCode: 0, stdout: '', stderr: '');
      },
    );
    expect(await service.restoreValue(backups.single.issue), isTrue);
    expect(script, contains('禁止覆盖'));
    expect(script, contains('RegistryView'));
  });
  test(
    'permission batches can cancel while preserving only verified results',
    () async {
      final local = p.join(fixture.path, 'Local');
      for (var i = 0; i < 300; i++) {
        put(p.join('Local', 'Temp', '$i.tmp'), 'a').setLastModifiedSync(
          DateTime.now().subtract(const Duration(days: 10)),
        );
      }
      final token = CleanCancellation();
      final service = ScanService(
        environment: {
          'USERPROFILE': fixture.path,
          'LOCALAPPDATA': local,
          'APPDATA': p.join(fixture.path, 'Roaming'),
          'SystemRoot': p.join(fixture.path, 'Windows'),
        },
        operabilityProbe: (paths) async => paths.toSet(),
      )..cancellation = token;
      final result = await service.scanAll(
        onProgress: (progress) {
          if (progress.message.contains('256 / 300')) token.cancel();
        },
      );
      expect(token.requested, isTrue);
      expect(result[CleanCategory.systemCache]!.items.single.fileCount, 256);
      expect(result.containsKey(CleanCategory.appCache), isFalse);
    },
  );
  test(
    'quick and deep discovery protect developer dependencies in either mode',
    () async {
      final local = p.join(fixture.path, 'Local');
      put(p.join('Local', 'Vendor', 'Cache', 'data'), 'vendor');
      put(p.join('Local', 'Code', 'Cache', 'data'), 'code');
      put(p.join('Local', 'Pub', 'Cache', 'package.dart'), 'dependency');
      final service = ScanService(
        environment: {
          'USERPROFILE': fixture.path,
          'LOCALAPPDATA': local,
          'APPDATA': p.join(fixture.path, 'Roaming'),
          'SystemRoot': p.join(fixture.path, 'Windows'),
        },
        operabilityProbe: (paths) async => paths.toSet(),
      );
      final quick = await service.scanAll();
      expect(quick[CleanCategory.appCache]!.items, hasLength(1));
      service.options = const ScanOptions(deepScan: true);
      final deep = await service.scanAll();
      expect(deep[CleanCategory.appCache]!.items, hasLength(2));
      expect(
        deep.values
            .expand((category) => category.items)
            .any((item) => item.path.contains('Pub')),
        isFalse,
      );
    },
  );
}
