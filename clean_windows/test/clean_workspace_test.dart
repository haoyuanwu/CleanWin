import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:clean_windows/models/clean_models.dart';
import 'package:clean_windows/pages/clean_page.dart';
import 'package:clean_windows/services/module_cache.dart';
import 'package:clean_windows/services/clean_service.dart';
import 'package:clean_windows/services/process_utils.dart';
import 'package:clean_windows/services/scan_service.dart';
import 'package:clean_windows/state/app_state.dart';
import 'package:clean_windows/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  void completeCategory(
    CleanCategory category, {
    String? error,
    int blockedFileCount = 0,
  }) {
    final result = ScanCategory(
      category: category,
      scanDuration: Duration.zero,
      error: error,
      blockedFileCount: blockedFileCount,
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
      freedBytes: items
          .where((item) => item.category != CleanCategory.downloads)
          .fold(0, (sum, item) => sum + item.sizeBytes),
      recycledBytes: items
          .where((item) => item.category == CleanCategory.downloads)
          .fold(0, (sum, item) => sum + item.sizeBytes),
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
  Completer<void>? pending;
  @override
  Future<void> setAsync(String key, Object? value) async {
    set(key, value);
    if (pending != null) await pending!.future;
  }
}

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('UI_PREVIEWS')) return;
    await (FontLoader('Segoe UI')..addFont(
          Future.value(
            ByteData.sublistView(
              File(r'C:\Windows\Fonts\msyh.ttc').readAsBytesSync(),
            ),
          ),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  late Directory fixture;
  late _Scan scan;
  late _State state;
  late ModuleCache cache, preferences;
  setUp(() {
    AppState.debugSkipProcess = true;
    ProcessUtils.debugSkip = true;
    fixture = Directory('.dart_tool').createTempSync('clean_workspace_');
    scan = _Scan();
    cache = _TestCache(fixture.path);
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
  Widget app({bool reduced = false, ValueChanged<int>? onNavigate}) =>
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: Scaffold(body: CleanPage(onNavigate: onNavigate)),
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

  testWidgets('overview excludes downloads without changing their selections', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final task = state.scan(force: true);
    scan.completeCategory(CleanCategory.downloads);
    scan.completeCategory(CleanCategory.systemLogs);
    scan.completeCategory(CleanCategory.appCache);
    scan.gate.complete();
    await tester.pump();
    await task;
    state.toggleItem(state.results[CleanCategory.downloads]!.items.single);
    final selectedBefore = state.totalSelectedBytes;
    int? destination;
    await tester.pumpWidget(
      app(reduced: true, onNavigate: (index) => destination = index),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看结果'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('缓存与临时文件')).dy,
      lessThan(tester.getTopLeft(find.text('日志与痕迹')).dy),
    );
    expect(find.text('下载文件夹'), findsNothing);
    expect(find.text('管理下载'), findsNothing);
    expect(find.text('Private cache snapshot'), findsNothing);
    expect(destination, isNull);
    expect(state.totalSelectedBytes, selectedBefore);
    expect(
      state.results[CleanCategory.downloads]!.items.single.selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final width in [1000.0, 560.0]) {
    testWidgets(
      'cleanup-only exclusions stay readable and diagnostics copy at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String?;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        const message = '已统计但未加入清理：1 个候选文件\n正在占用（Windows 32）：C:\\Cache\\busy';
        final task = state.scan(force: true);
        scan.completeCategory(
          CleanCategory.appCache,
          error: message,
          blockedFileCount: 1,
        );
        scan.gate.complete();
        await tester.pump();
        await task;
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(key: boundaryKey, child: app(reduced: true)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('查看结果'));
        await tester.pumpAndSettle();
        expect(find.text('1 个文件暂不可清理'), findsOneWidget);
        expect(find.text('部分位置未读取'), findsNothing);
        await tester.tap(find.text('软件缓存'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byTooltip('复制扫描诊断'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('复制扫描诊断'));
        await tester.pump();
        expect(copied, message);
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('UI_PREVIEWS')) {
          await tester.runAsync(() async {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            final screenshot = await boundary.toImage();
            final bytes = await screenshot.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              '.dart_tool/access_previews/scan-diagnostic-${width.toInt()}.png',
            );
            file.parent.createSync(recursive: true);
            file.writeAsBytesSync(bytes!.buffer.asUint8List());
            screenshot.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

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
    'overview cleanup excludes selected downloads and preserves other workspaces',
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
      scan.completeCategory(CleanCategory.browserCache);
      scan.gate.complete();
      await tester.pump();
      await task;
      state.toggleCategory(state.results[CleanCategory.browserCache]!, false);
      state.toggleDownloadSelection(CleanCategory.downloads.name);
      expect(state.results[CleanCategory.downloads]!.selectedCount, 1);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('orbit-systemCache')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, '智能清理'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认清理'));
      await tester.pumpAndSettle();
      expect(cleaner.received.map((item) => item.category), [
        CleanCategory.systemCache,
      ]);
      expect(state.results[CleanCategory.downloads]!.items, hasLength(1));
      expect(state.results[CleanCategory.browserCache]!.items, hasLength(1));
      expect(state.results[CleanCategory.systemCache]!.items, isEmpty);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(find.textContaining('为电脑释放了'), findsOneWidget);
      await tester.tap(find.text('查看结果'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('systemCache-false')), findsNothing);
      expect(find.byKey(const ValueKey('downloads-false')), findsNothing);
      expect(find.byKey(const ValueKey('browserCache-false')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('downloads alone never enable overview cleanup', (tester) async {
    final task = state.scan(force: true);
    scan.completeCategory(CleanCategory.downloads);
    scan.gate.complete();
    await tester.pump();
    await task;
    state.toggleDownloadSelection(CleanCategory.downloads.name);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('智能清理'), findsNothing);
    expect(find.text('扫描结果'), findsNothing);
    expect(state.results[CleanCategory.downloads]!.selectedCount, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'home publishes cleared results before cache save and resets after a new scan',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      state.dispose();
      final pendingCache = _TestCache(fixture.path);
      state = _State(
        scan,
        pendingCache,
        preferences,
        cleaner: _CaptureCleaner(),
      );
      final scanTask = state.scan(force: true);
      scan.completeCategory(CleanCategory.systemCache);
      scan.gate.complete();
      await tester.pump();
      await scanTask;
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看结果'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('systemCache-false')), findsOneWidget);
      pendingCache.pending = Completer<void>.sync();
      final cleanup = state.cleanSelected(
        categories: {CleanCategory.systemCache},
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(state.cleaning, true);
      expect(state.results[CleanCategory.systemCache]!.items, isEmpty);
      expect(find.byKey(const ValueKey('systemCache-false')), findsNothing);
      expect(find.text('已选项目已处理，暂无剩余内容'), findsOneWidget);
      expect(state.totalSelectedBytes, 0);
      pendingCache.pending!.complete();
      await tester.pump();
      await cleanup;
      await tester.pumpAndSettle();
      pendingCache.pending = null;
      await tester.runAsync(() => state.scan(force: true));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('systemCache-false')), findsOneWidget);
      expect(find.text('已选项目已处理，暂无剩余内容'), findsNothing);
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
