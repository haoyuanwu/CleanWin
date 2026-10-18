import 'dart:async';
import 'dart:io';

import 'package:clean_windows/models/clean_models.dart';
import 'package:clean_windows/pages/clean_page.dart';
import 'package:clean_windows/services/module_cache.dart';
import 'package:clean_windows/services/clean_service.dart';
import 'package:clean_windows/services/process_utils.dart';
import 'package:clean_windows/services/scan_service.dart';
import 'package:clean_windows/state/app_state.dart';
import 'package:clean_windows/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Scan extends ScanService {
  final gate = Completer<void>.sync();
  final records = <CleanCategory, ScanCategory>{};
  void Function(ScanCategory)? emit;
  void Function(ScanProgress)? progress;
  @override
  Future<Map<CleanCategory, ScanCategory>> scanAll({
    Set<CleanCategory>? categories,
    void Function(ScanProgress)? onProgress,
    void Function(ScanCategory)? onCategoryDone,
  }) async {
    emit = onCategoryDone;
    progress = onProgress;
    onProgress?.call(
      const ScanProgress(
        totalCategories: 13,
        currentPath: r'C:\TestCache',
        message: '检查缓存中',
      ),
    );
    await gate.future;
    return records;
  }

  void completeCategory(CleanCategory category) {
    final result = ScanCategory(
      category: category,
      scanDuration: Duration.zero,
      items: [
        CleanItem(
          id: category.name,
          name: 'Private cache snapshot',
          path: r'C:\TestCache\cache.bin',
          sizeBytes: 48 * 1024 * 1024,
          category: category,
          selected: true,
        ),
      ],
    );
    records[category] = result;
    emit?.call(result);
    progress?.call(
      ScanProgress(
        totalCategories: 13,
        completedCategories: records.length,
        currentPath: r'C:\NextCache',
        message: '检查缓存中',
      ),
    );
  }
}

class _State extends AppState {
  _State(
    _Scan scan,
    ModuleCache cache,
    ModuleCache preferences, {
    CleanService? cleaner,
  }) : super(
         scanService: scan,
         scanCache: cache,
         preferencesCache: preferences,
         cleanService: cleaner,
       );
  @override
  Future<({int total, int free})?> diskSpace(String letter) async =>
      (total: 100 * 1024 * 1024 * 1024, free: 50 * 1024 * 1024 * 1024);
}

class _CaptureCleaner extends CleanService {
  final received = <CleanItem>[];
  @override
  Future<CleanReport> cleanItems(
    List<CleanItem> items, {
    void Function(CleanItem, String, int, int)? onItem,
    CleanCancellation? cancellation,
    bool recycle = false,
  }) async {
    received.addAll(items);
    return CleanReport(
      freedBytes: items.fold(0, (sum, item) => sum + item.sizeBytes),
      deletedCount: items.length,
      skippedCount: 0,
      failedCount: 0,
      completedItemIds: items.map((item) => item.id).toSet(),
    );
  }
}

class _TestCache extends ModuleCache {
  _TestCache(String directory)
    : super(storageDirectory: directory, namespace: 'scan');
  @override
  Future<void> setAsync(String key, Object? value) async => set(key, value);
}

void main() {
  late Directory fixture;
  late _Scan scan;
  late _State state;
  late ModuleCache cache, preferences;
  setUp(() {
    AppState.debugSkipProcess = true;
    ProcessUtils.debugSkip = true;
    fixture = Directory('.dart_tool').createTempSync('clean_workspace_');
    scan = _Scan();
    cache = ModuleCache(namespace: 'scan', storageDirectory: fixture.path);
    preferences = ModuleCache(
      namespace: 'prefs',
      storageDirectory: fixture.path,
    );
    state = _State(scan, cache, preferences);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('clean_windows/window'),
          (call) async => false,
        );
  });
  tearDown(() {
    state.dispose();
    fixture.deleteSync(recursive: true);
    AppState.debugSkipProcess = false;
    ProcessUtils.debugSkip = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('clean_windows/window'),
          null,
        );
  });
  Widget app({bool reduced = false}) => ChangeNotifierProvider<AppState>.value(
    value: state,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: const Scaffold(body: CleanPage()),
      ),
    ),
  );

  testWidgets('idle shows disk overview without any result controls', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('扫描结果'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('智能清理'), findsNothing);
    expect(find.byKey(const ValueKey('clean-disk-overview')), findsOneWidget);
    expect(find.text('50.0 GB 可用'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'categories enter progressively, stay folded, and unlock after scanning',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始扫描'));
      await tester.pump();
      expect(find.byKey(const ValueKey('scan-current-path')), findsOneWidget);
      expect(find.text('扫描结果'), findsNothing);
      scan.completeCategory(CleanCategory.systemCache);
      await tester.pump();
      await tester.pump();
      expect(find.text('扫描结果'), findsOneWidget);
      expect(find.text('Private cache snapshot'), findsNothing);
      final entrance = find.byKey(const ValueKey('1_systemCache'));
      final fade = find
          .descendant(of: entrance, matching: find.byType(Opacity))
          .first;
      expect(tester.widget<Opacity>(fade).opacity, 0);
      await tester.pump(const Duration(milliseconds: 160));
      expect(tester.widget<Opacity>(fade).opacity, greaterThan(0));
      expect(tester.widget<Opacity>(fade).opacity, lessThan(1));
      expect(
        tester
            .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '智能清理'))
            .onPressed,
        isNull,
      );
      scan.gate.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<Opacity>(fade).opacity, 1);
      expect(
        tester
            .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '智能清理'))
            .onPressed,
        isNotNull,
      );
      await tester.ensureVisible(find.text('系统缓存'));
      await tester.tap(find.text('系统缓存'));
      await tester.pumpAndSettle();
      expect(find.text('Private cache snapshot'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('restored cache is hidden until this session scans', (
    tester,
  ) async {
    final task = state.scan(force: true);
    scan.completeCategory(CleanCategory.systemCache);
    scan.gate.complete();
    await tester.pump();
    await task;
    state.dispose();
    AppState.debugSkipProcess = false;
    scan = _Scan();
    state = _State(scan, cache, preferences);
    expect(state.hasResults, true);
    expect(state.scanGeneration, 0);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('扫描结果'), findsNothing);
    expect(find.text('48.0 MB'), findsNothing);
    expect(find.text('开始扫描'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('orbit click reveals its category and expands file details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final task = state.scan(force: true);
    scan.completeCategory(CleanCategory.systemCache);
    scan.completeCategory(CleanCategory.browserCache);
    scan.gate.complete();
    await tester.pump();
    await task;
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('orbit-systemCache')));
    await tester.pumpAndSettle();
    expect(find.text('全部星域'), findsOneWidget);
    expect(find.text('Private cache snapshot'), findsOneWidget);
    expect(find.text('浏览器缓存'), findsNothing);
    await tester.tap(find.text('全部星域'));
    await tester.pumpAndSettle();
    expect(find.text('系统缓存'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'smart cleanup excludes selected downloads and celebrates after dismissal',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      state.dispose();
      final cleaner = _CaptureCleaner();
      state = _State(
        scan,
        _TestCache(fixture.path),
        preferences,
        cleaner: cleaner,
      );
      final task = state.scan(force: true);
      scan.completeCategory(CleanCategory.systemCache);
      scan.completeCategory(CleanCategory.downloads);
      scan.gate.complete();
      await tester.pump();
      await task;
      state.toggleDownloadSelection(CleanCategory.downloads.name);
      expect(state.results[CleanCategory.downloads]!.selectedCount, 1);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, '智能清理'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认清理'));
      await tester.pumpAndSettle();
      expect(cleaner.received.map((item) => item.category), [
        CleanCategory.systemCache,
      ]);
      expect(state.results[CleanCategory.downloads]!.items, hasLength(1));
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(find.textContaining('为电脑释放了'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('reduced motion presents results without an entrance delay', (
    tester,
  ) async {
    await tester.pumpWidget(app(reduced: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始扫描'));
    await tester.pump();
    scan.completeCategory(CleanCategory.systemCache);
    scan.gate.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看结果'));
    await tester.pumpAndSettle();
    final fade = find
        .descendant(
          of: find.byKey(const ValueKey('1_systemCache')),
          matching: find.byType(Opacity),
        )
        .first;
    expect(tester.widget<Opacity>(fade).opacity, 1);
    expect(find.text('48.0 MB'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });
}
