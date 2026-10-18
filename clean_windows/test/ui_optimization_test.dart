import 'dart:io';
import 'dart:ui' as ui;

import 'package:clean_windows/app.dart';
import 'package:clean_windows/models/clean_models.dart';
import 'package:clean_windows/pages/clean_page.dart';
import 'package:clean_windows/pages/disk_pages.dart';
import 'package:clean_windows/pages/downloads_page.dart';
import 'package:clean_windows/pages/performance_page.dart';
import 'package:clean_windows/pages/settings_page.dart';
import 'package:clean_windows/pages/startup_registry_pages.dart';
import 'package:clean_windows/pages/uninstall_page.dart';
import 'package:clean_windows/pages/whitelist_page.dart';
import 'package:clean_windows/services/clean_service.dart';
import 'package:clean_windows/services/module_cache.dart';
import 'package:clean_windows/services/process_utils.dart';
import 'package:clean_windows/services/scan_service.dart';
import 'package:clean_windows/services/whitelist_service.dart';
import 'package:clean_windows/state/app_state.dart';
import 'package:clean_windows/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Scan extends ScanService {
  @override
  Future<Map<CleanCategory, ScanCategory>> scanAll({
    Set<CleanCategory>? categories,
    void Function(ScanProgress)? onProgress,
    void Function(ScanCategory)? onCategoryDone,
  }) async => {
    for (final category in [CleanCategory.systemCache, CleanCategory.downloads])
      category: ScanCategory(
        category: category,
        scanDuration: Duration.zero,
        items: [
          CleanItem(
            id: category.name,
            name: category == CleanCategory.downloads
                ? 'Installer.zip'
                : 'Windows 临时缓存',
            path: 'C:\\Example\\${category.name}',
            sizeBytes: 48 * 1024 * 1024,
            category: category,
          ),
        ],
      ),
  };
}

class _Cleaner extends CleanService {
  List<CleanItem> received = [];
  @override
  Future<CleanReport> cleanItems(
    List<CleanItem> items, {
    void Function(CleanItem, String, int, int)? onItem,
    CleanCancellation? cancellation,
    bool recycle = false,
  }) async {
    received = items;
    return CleanReport.empty();
  }
}

void main() {
  late Directory fixture;
  late AppState state;
  late _Cleaner cleaner;
  setUpAll(() async {
    if (!const bool.fromEnvironment('UI_PREVIEWS')) return;
    final textFont = FontLoader('Segoe UI')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File(r'C:\Windows\Fonts\msyh.ttc').readAsBytesSync(),
          ),
        ),
      );
    await textFont.load();
    final iconFont = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconFont.load();
  });
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('clean_windows/window'),
          (call) async =>
              call.method == 'isMaximized' || call.method == 'isElevated'
              ? false
              : null,
        );
    AppState.debugSkipProcess = true;
    ProcessUtils.debugSkip = true;
    fixture = Directory('.dart_tool').createTempSync('ui_test_');
    cleaner = _Cleaner();
    state = AppState(
      scanService: _Scan(),
      cleanService: cleaner,
      whitelistService: WhitelistService(storageDirectory: fixture.path),
      scanCache: ModuleCache(namespace: 'scan', storageDirectory: fixture.path),
      preferencesCache: ModuleCache(
        namespace: 'preferences',
        storageDirectory: fixture.path,
      ),
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('clean_windows/window'),
          null,
        );
    state.dispose();
    fixture.deleteSync(recursive: true);
    AppState.debugSkipProcess = false;
    ProcessUtils.debugSkip = false;
  });

  Widget page(Widget child) => ChangeNotifierProvider<AppState>.value(
    value: state,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: child),
    ),
  );

  testWidgets('merged workspace hides shortcuts and results before scanning', (
    tester,
  ) async {
    await tester.pumpWidget(page(const CleanPage()));
    await tester.pumpAndSettle();
    expect(find.text('概览与清理'), findsOneWidget);
    expect(find.text('快捷功能'), findsNothing);
    expect(find.text('扫描结果'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('清理所选'), findsNothing);
    expect(find.text('开始扫描'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'download cleanup does not include selections in other modules',
    () async {
      await state.scan(force: true);
      state.toggleDownloadSelection(CleanCategory.downloads.name);
      expect(state.totalSelectedCount, 2);
      await state.cleanSelected(categories: {CleanCategory.downloads});
      expect(cleaner.received.map((item) => item.category), [
        CleanCategory.downloads,
      ]);
      expect(
        state.results[CleanCategory.systemCache]!.items.single.selected,
        true,
      );
    },
  );

  testWidgets('all module layouts fit a narrow content area', (tester) async {
    tester.view.physicalSize = const Size(560, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final child in const [
      CleanPage(),
      DiskAnalysisPage(active: false),
      LargeFilesPage(),
      DownloadsPage(),
      PerformancePage(active: false),
      UninstallPage(active: false),
      StartupPage(),
      RegistryCleanPage(),
      WhitelistPage(),
      SettingsPage(),
    ]) {
      await tester.pumpWidget(page(child));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: '${child.runtimeType} should fit',
      );
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'download search clears and confirmation shows only download size',
    (tester) async {
      await state.scan(force: true);
      state.toggleDownloadSelection(CleanCategory.downloads.name);
      await tester.pumpWidget(page(const DownloadsPage()));
      await tester.ensureVisible(find.byTooltip('搜索'));
      await tester.tap(find.byTooltip('搜索'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.enterText(find.byType(TextField), 'missing');
      await tester.pumpAndSettle();
      expect(find.text('没有匹配的下载文件'), findsOneWidget);
      await tester.tap(find.byTooltip('清空搜索'));
      await tester.pumpAndSettle();
      expect(find.text('Installer.zip'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, '删除 48.0 MB'));
      await tester.pumpAndSettle();
      expect(find.textContaining('共 48.0 MB'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(cleaner.received, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('clean category filter preserves the underlying selections', (
    tester,
  ) async {
    await state.scan(force: true);
    await tester.pumpWidget(page(const CleanPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看结果'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('搜索'));
    await tester.tap(find.byTooltip('搜索'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(find.byType(TextField), '不存在');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的分类'), findsOneWidget);
    expect(state.totalSelectedCount, 1);
    await tester.tap(find.byTooltip('清空搜索'));
    await tester.pumpAndSettle();
    expect(find.text('系统缓存'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  if (const bool.fromEnvironment('UI_PREVIEWS')) {
    testWidgets('export merged workspace before and after scanning', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final index in [0, 1]) {
        if (index == 1) await state.scan(force: true);
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: ChangeNotifierProvider<AppState>.value(
              value: state,
              child: CleanWindowsApp(key: ValueKey(index), initialIndex: index),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final output = File(
            '.dart_tool/ui_previews/${index == 0 ? 'clean-idle' : 'clean-results'}.png',
          );
          output.parent.createSync(recursive: true);
          output.writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
