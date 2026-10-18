import 'dart:io';

import 'package:clean_windows/models/clean_models.dart';
import 'package:clean_windows/services/clean_service.dart';
import 'package:clean_windows/services/file_safety.dart';
import 'package:clean_windows/services/module_cache.dart';
import 'package:clean_windows/services/scan_service.dart';
import 'package:clean_windows/services/whitelist_service.dart';
import 'package:clean_windows/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _Scan extends ScanService {
  _Scan(this.items);
  final List<CleanItem> items;
  @override
  Future<Map<CleanCategory, ScanCategory>> scanAll({
    Set<CleanCategory>? categories,
    void Function(ScanProgress)? onProgress,
    void Function(ScanCategory)? onCategoryDone,
  }) async => {
    CleanCategory.systemCache: ScanCategory(
      category: CleanCategory.systemCache,
      items: items,
      scanDuration: Duration.zero,
    ),
  };
}

void main() {
  late Directory fixture;
  setUp(() {
    AppState.debugSkipProcess = true;
    fixture = Directory('.dart_tool')
        .createTempSync('cancel_cleanup_')
        .absolute;
  });
  tearDown(() {
    expect(
      p.isWithin(Directory('.dart_tool').absolute.path, fixture.path),
      isTrue,
    );
    fixture.deleteSync(recursive: true);
    AppState.debugSkipProcess = false;
  });
  File put(String name, String content) =>
      File(p.join(fixture.path, name))..writeAsStringSync(content);
  CleanItem item(String id, List<File> files) => CleanItem(
    id: id,
    name: id,
    path: files.length == 1 ? files.single.path : fixture.path,
    sizeBytes: files.fold(0, (sum, file) => sum + file.lengthSync()),
    fileCount: files.length,
    category: CleanCategory.systemCache,
    scannedFiles: files.map((file) => file.path).toList(),
    fileSignatures: {
      for (final file in files) file.path: fileSignature(file.statSync()),
    },
  );

  test('cancellation before starting does not touch reviewed files', () async {
    final file = put('untouched.tmp', 'keep');
    final cancellation = CleanCancellation()..cancel();
    final report = await CleanService().cleanItems([
      item('untouched', [file]),
    ], cancellation: cancellation);
    expect(report.cancelled, isTrue);
    expect(report.freedBytes, 0);
    expect(report.completedItemIds, isEmpty);
    expect(report.failedCount, 0);
    expect(file.readAsStringSync(), 'keep');
  });

  test('cancellation inside one folder retains accurate remaining size and selection', () async {
    final a = put('a.tmp', 'first');
    final b = put('b.tmp', 'second');
    final c = put('c.tmp', 'remaining');
    final target = item('folder', [a, b, c]);
    final cancellation = CleanCancellation();
    final report = await CleanService().cleanItems(
      [target],
      cancellation: cancellation,
      onItem: (_, message, _, _) {
        if (message.endsWith(c.path)) cancellation.cancel();
      },
    );
    expect(report.cancelled, isTrue);
    expect(report.freedBytes, 11);
    expect(report.completedItemIds, isEmpty);
    expect(report.failedCount, 0);
    expect(report.skippedCount, 0);
    expect(a.existsSync(), isFalse);
    expect(b.existsSync(), isFalse);
    expect(c.readAsStringSync(), 'remaining');
    expect(target.sizeBytes, 9);
    expect(target.fileCount, 1);
    expect(target.selected, isTrue);
    final retry = await CleanService().cleanItems([target]);
    expect(retry.cancelled, isFalse);
    expect(retry.freedBytes, 9);
    expect(retry.completedItemIds, {'folder'});
  });

  test(
    'state keeps unfinished items and a later cleanup uses a fresh token',
    () async {
      final a = put('first.tmp', 'first');
      final b = put('second.tmp', 'second');
      final state = AppState(
        scanService: _Scan([
          item('first', [a]),
          item('second', [b]),
        ]),
        whitelistService: WhitelistService(storageDirectory: fixture.path),
        scanCache: ModuleCache(
          namespace: 'scan',
          storageDirectory: fixture.path,
        ),
        preferencesCache: ModuleCache(
          namespace: 'prefs',
          storageDirectory: fixture.path,
        ),
      );
      addTearDown(state.dispose);
      await state.scan(force: true);
      final report = await state.cleanSelected(
        onProgress: (_, _, done, _) {
          if (done == 1) state.cancelCleaning();
        },
      );
      expect(report.cancelled, isTrue);
      expect(report.completedItemIds, {'first'});
      expect(report.freedBytes, 5);
      expect(state.cleaning, isFalse);
      expect(
        state.results[CleanCategory.systemCache]!.items.single.id,
        'second',
      );
      expect(b.existsSync(), isTrue);
      final retry = await state.cleanSelected();
      expect(retry.cancelled, isFalse);
      expect(retry.completedItemIds, {'second'});
      expect(retry.freedBytes, 6);
      expect(state.results[CleanCategory.systemCache]!.items, isEmpty);
    },
  );
}
