import 'dart:async';

import 'package:clean_windows/models/clean_models.dart';
import 'package:clean_windows/pages/downloads_page.dart';
import 'package:clean_windows/services/download_list_index.dart';
import 'package:clean_windows/services/module_cache.dart';
import 'package:clean_windows/services/scan_service.dart';
import 'package:clean_windows/state/app_state.dart';
import 'package:clean_windows/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

DownloadListEntry row(
  int index,
  String path,
  int bytes, {
  String? id,
  DateTime? modified,
}) => (
  index: index,
  id: id ?? '$index',
  name: path.split(r'\').last,
  path: path,
  root: downloadFolder(path, id ?? '$index'),
  bytes: bytes,
  modified: modified,
);

class _Cache extends ModuleCache {
  final saved = Completer<void>();
  @override
  void set(String key, Object? value) =>
      throw StateError('Synchronous scan persistence blocks UI');
  @override
  Future<void> setAsync(String key, Object? value) async {
    saved.complete();
  }

  @override
  Map<String, dynamic>? getMap(String key) => null;
}

class _Scanner extends ScanService {
  @override
  Future<Map<CleanCategory, ScanCategory>> scanAll({
    Set<CleanCategory>? categories,
    void Function(ScanProgress)? onProgress,
    void Function(ScanCategory)? onCategoryDone,
  }) async => {};
}

class _State extends AppState {
  _State(this.items) : super(preferencesCache: _Cache());
  final List<CleanItem> items;
  late final _category = ScanCategory(
    category: CleanCategory.downloads,
    items: items,
    scanDuration: Duration.zero,
  );
  @override
  Map<CleanCategory, ScanCategory> get results => {
    CleanCategory.downloads: _category,
  };
}

void main() {
  test('groups normalized Windows paths, preserves software root and sorts by bytes', () {
    final index = buildDownloadListIndex(
      DownloadListRequest([
        row(0, r'C:\Users\A\Downloads\small.zip', 10),
        row(1, r'c:\users\a\Downloads\large.zip', 30),
        row(2, r'D:\QMDownload\SoftMgr', 70, id: 'dl_software_root'),
        row(3, r'E:\Downloads\video.mp4', 20),
      ]),
    );
    expect(index.groups, hasLength(3));
    expect(index.groups.first.path, r'D:\QMDownload\SoftMgr');
    expect(index.groups[1].indices, [1, 0]);
    expect(index.groups[1].bytes, 40);
    expect(index.totalBytes, 130);
    expect(index.kindCounts['压缩 / 镜像'], 2);
  });

  test('search and age filter change visible groups while retaining full statistics', () {
    final index = buildDownloadListIndex(
      DownloadListRequest(
        [
          row(
            0,
            r'C:\Downloads\old.zip',
            30,
            modified: DateTime.now().subtract(const Duration(days: 40)),
          ),
          row(1, r'C:\Downloads\new.zip', 20, modified: DateTime.now()),
          row(2, r'D:\Downloads\unknown.zip', 10),
        ],
        query: r'c:\downloads',
        kind: '压缩 / 镜像',
        minimumDays: 30,
      ),
    );
    expect(index.groups.single.indices, [0]);
    expect(index.visibleCount, 1);
    expect(index.totalBytes, 60);
    expect(index.sizeById['1'], 20);
  });

  test('large result index can be prepared on a worker isolate', () async {
    final result = await compute(
      buildDownloadListIndex,
      DownloadListRequest([
        for (var i = 0; i < 10000; i++) row(i, 'C:\\Downloads\\$i.zip', i),
      ]),
    );
    expect(result.visibleCount, 10000);
    expect(result.groups.single.indices.first, 9999);
    expect(result.groups.single.indices.last, 0);
  });

  test('scan completion uses asynchronous cache persistence', () async {
    AppState.debugSkipProcess = true;
    final cache = _Cache();
    final state = AppState(
      scanService: _Scanner(),
      scanCache: cache,
      preferencesCache: _Cache(),
    );
    try {
      await state.scan(categories: {CleanCategory.downloads});
      expect(cache.saved.isCompleted, isTrue);
      expect(state.scanning, isFalse);
    } finally {
      state.dispose();
      AppState.debugSkipProcess = false;
    }
  });

  testWidgets(
    'folder collapse preserves selections and result removal updates totals',
    (tester) async {
      AppState.debugSkipProcess = true;
      final state = _State([
        CleanItem(
          id: 'a',
          name: 'alpha.zip',
          path: r'C:\Downloads\alpha.zip',
          sizeBytes: 100,
          category: CleanCategory.downloads,
          selected: false,
        ),
        CleanItem(
          id: 'b',
          name: 'beta.exe',
          path: r'D:\Packages\beta.exe',
          sizeBytes: 50,
          category: CleanCategory.downloads,
          selected: false,
        ),
      ]);
      addTearDown(() {
        state.dispose();
        AppState.debugSkipProcess = false;
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => tester.view.resetPhysicalSize());
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: DownloadsPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey(r'download-folder-C:\Downloads')),
        findsOneWidget,
      );
      await tester.tap(find.text('alpha.zip'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.text('打开所在位置'), findsOneWidget);
      expect(find.text('勾选此项'), findsOneWidget);
      await tester.tap(find.text('勾选此项'));
      await tester.pumpAndSettle();
      expect(state.selectedDownloadIds, {'a'});
      await tester.tap(
        find.byKey(const ValueKey(r'download-folder-C:\Downloads')),
      );
      await tester.pumpAndSettle();
      expect(find.text('alpha.zip'), findsNothing);
      expect(state.selectedDownloadIds, {'a'});
      await tester.tap(
        find.byKey(const ValueKey(r'download-folder-C:\Downloads')),
      );
      await tester.pumpAndSettle();
      expect(find.text('alpha.zip'), findsOneWidget);
      state.items.removeLast();
      state.toggleDownloadSelection('a');
      await tester.pumpAndSettle();
      expect(find.text('beta.exe'), findsNothing);
      expect(
        find.byKey(const ValueKey(r'download-folder-D:\Packages')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
