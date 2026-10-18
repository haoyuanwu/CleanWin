import 'dart:async';
import 'dart:io';

import 'package:clean_windows/app.dart';
import 'package:clean_windows/models/clean_models.dart';
import 'package:clean_windows/models/scan_options.dart';
import 'package:clean_windows/pages/settings_page.dart';
import 'package:clean_windows/services/module_cache.dart';
import 'package:clean_windows/services/process_utils.dart';
import 'package:clean_windows/services/scan_service.dart';
import 'package:clean_windows/state/app_state.dart';
import 'package:clean_windows/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Scan extends ScanService {
  int calls = 0;
  bool fail = false;

  Completer<void>? pending;
  @override
  Future<Map<CleanCategory, ScanCategory>> scanAll({
    Set<CleanCategory>? categories,
    void Function(ScanProgress)? onProgress,
    void Function(ScanCategory)? onCategoryDone,
  }) async {
    calls++;
    onProgress?.call(
      const ScanProgress(
        totalCategories: 1,
        message: '自动扫描测试中',
        currentPath: r'C:\TestCache',
      ),
    );
    if (pending != null) await pending!.future;
    if (fail) throw StateError('test scan failed');
    return {
      CleanCategory.systemCache: ScanCategory(
        category: CleanCategory.systemCache,
        scanDuration: Duration.zero,
        items: [
          CleanItem(
            id: 'cache',
            name: 'Cache',
            path: r'C:\TestCache',
            sizeBytes: 2048,
            category: CleanCategory.systemCache,
          ),
        ],
      ),
    };
  }
}

class _Preferences extends ModuleCache {
  Completer<void>? pendingSave;
  @override
  Future<void> setDurableAsync(String key, Object? value) async {
    if (pendingSave != null) await pendingSave!.future;
    setDurable(key, value);
  }
  _Preferences(String path)
    : super(
        namespace: 'prefs',
        storageDirectory: path,
        ttl: const Duration(days: 3650),
      );
  bool fail = false;
  @override
  void setDurable(String key, Object? value) {
    if (fail) throw const FileSystemException('test denied');
    super.setDurable(key, value);
  }
}

class _State extends AppState {
  _State(
    _Scan scan,
    ModuleCache preferences,
    ModuleCache cache, {
    bool force = false,
  }) : super(
         scanService: scan,
         preferencesCache: preferences,
         scanCache: cache,
         scanOnStart: force,
       );
  @override
  Future<({int total, int free})?> diskSpace(String letter) async => null;
}

void main() {
  late Directory fixture;
  late _Preferences preferences;
  late ModuleCache cache;
  late _Scan scan;
  final states = <_State>[];
  _State create({bool force = false}) {
    final state = _State(scan, preferences, cache, force: force);
    states.add(state);
    return state;
  }

  setUp(() {
    AppState.debugSkipProcess = true;
    ProcessUtils.debugSkip = true;
    fixture = Directory('.dart_tool').createTempSync('settings_test_');
    preferences = _Preferences(fixture.path);
    cache = ModuleCache(namespace: 'scan', storageDirectory: fixture.path);
    scan = _Scan();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('clean_windows/window'),
          (call) async =>
              call.method == 'isMaximized' || call.method == 'isElevated'
              ? false
              : null,
        );
  });
  tearDown(() {
    for (final state in states) {
      state.dispose();
    }
    states.clear();
    fixture.deleteSync(recursive: true);
    AppState.debugSkipProcess = false;
    ProcessUtils.debugSkip = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('clean_windows/window'),
          null,
        );
  });
  Widget settings(AppState state) => ChangeNotifierProvider<AppState>.value(
    value: state,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: SettingsPage()),
    ),
  );

  testWidgets('range switches repaint before saving and roll back on failure', (
    tester,
  ) async {
    final state = create();
    await state.scan(force: true);
    preferences.pendingSave = Completer<void>();
    preferences.fail = true;
    await tester.pumpWidget(settings(state));
    await tester.ensureVisible(find.text('扫描浏览器缓存'));
    await tester.tap(find.text('扫描浏览器缓存'));
    await tester.pump(const Duration(milliseconds: 180));
    expect(state.savingOptions, isTrue);
    expect(state.options.cleanBrowserCache, isFalse);
    expect(find.text('正在保存…'), findsOneWidget);
    expect(state.hasResults, isTrue);
    expect(tester.takeException(), isNull);
    // A pending save must not permit scanning against uncommitted rules.
    await state.scan(force: true);
    expect(scan.calls, 1);
    preferences.pendingSave!.complete();
    await tester.pumpAndSettle();
    expect(state.savingOptions, isFalse);
    expect(state.options.cleanBrowserCache, isTrue);
    expect(state.hasResults, isTrue);
    expect(find.text('保存失败'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'behavior changes persist across fresh instances and keep scan results',
    () async {
      final state = create();
      await state.scan(force: true);
      expect(
        await state.updateOptions(
          state.options.copyWith(
            autoScanOnStart: true,
            confirmBeforeClean: false,
          ),
        ),
        true,
      );
      expect(state.hasResults, true);
      final fresh = _Preferences(fixture.path);
      expect(
        ScanOptions.fromJson(fresh.getMap('scan_options')!).autoScanOnStart,
        true,
      );
      expect(
        ScanOptions.fromJson(fresh.getMap('scan_options')!).confirmBeforeClean,
        false,
      );
      expect(
        await state.updateOptions(state.options.copyWith(cleanGpuCache: false)),
        true,
      );
      expect(state.hasResults, false);
    },
  );

  test(
    'failed saving keeps the previous switch values and saved preferences',
    () async {
      final state = create();
      await state.updateOptions(state.options.copyWith(autoScanOnStart: true));
      preferences.fail = true;
      expect(
        await state.updateOptions(
          state.options.copyWith(autoScanOnStart: false),
        ),
        false,
      );
      expect(state.options.autoScanOnStart, true);
      expect(state.optionsSaveError, isNotNull);
      expect(
        _Preferences(fixture.path).getMap('scan_options')!['autoScanOnStart'],
        true,
      );
    },
  );

  test(
    'startup requests are consumed once and enabling later waits until restart',
    () async {
      AppState.debugSkipProcess = false;
      final state = create();
      expect(state.consumeStartupScanRequest(), false);
      await state.updateOptions(state.options.copyWith(autoScanOnStart: true));
      expect(state.consumeStartupScanRequest(), false);
      final restarted = create();
      expect(restarted.consumeStartupScanRequest(), true);
      expect(restarted.consumeStartupScanRequest(), false);
      preferences.setDurable('scan_options', const ScanOptions().toJson());
      expect(create(force: true).consumeStartupScanRequest(), true);
    },
  );

  testWidgets('saved auto scan opens the progress page and scans only once', (
    tester,
  ) async {
    preferences.setDurable(
      'scan_options',
      const ScanOptions(autoScanOnStart: true).toJson(),
    );
    AppState.debugSkipProcess = false;
    scan.pending = Completer<void>();
    final state = create();
    Widget app() => ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const CleanWindowsApp(),
    );
    await tester.pumpWidget(app());
    await tester.pump();
    expect(scan.calls, 1);
    expect(find.byKey(const ValueKey('scan-current-path')), findsOneWidget);
    expect(find.text(r'C:\TestCache'), findsOneWidget);
    await tester.pumpWidget(app());
    await tester.pump();
    expect(scan.calls, 1);
    scan.pending!.complete();
    await tester.pumpAndSettle();
    expect(state.hasResults, true);
    expect(state.scanning, false);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('startup scan failure gives a visible retry message', (
    tester,
  ) async {
    preferences.setDurable(
      'scan_options',
      const ScanOptions(autoScanOnStart: true).toJson(),
    );
    AppState.debugSkipProcess = false;
    scan.fail = true;
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: create(),
        child: const CleanWindowsApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('自动扫描未完成，请点击「重新扫描」重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('settings rows toggle, show save feedback and retain results', (
    tester,
  ) async {
    final state = create();
    await state.scan(force: true);
    await tester.pumpWidget(settings(state));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('启动时自动扫描'));
    await tester.tap(find.text('启动时自动扫描'));
    await tester.pumpAndSettle();
    expect(state.options.autoScanOnStart, true);
    expect(state.hasResults, true);
    expect(find.text('已保存：下次启动软件自动进入一键清理并扫描'), findsOneWidget);
    preferences.fail = true;
    await tester.tap(find.text('启动时自动扫描'));
    await tester.pumpAndSettle();
    expect(state.options.autoScanOnStart, true);
    expect(find.text('保存失败'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'scan rules lock during a task while behavior changes remain available',
    (tester) async {
      scan.pending = Completer<void>();
      final state = create();
      final task = state.scan(force: true);
      await tester.pumpWidget(settings(state));
      await tester.pump();
      final tiles = tester
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .toList();
      expect(tiles.where((tile) => tile.onChanged == null), hasLength(2));
      expect(tiles.where((tile) => tile.onChanged != null), hasLength(2));
      await tester.ensureVisible(find.text('启动时自动扫描'));
      await tester.tap(find.text('启动时自动扫描'));
      await tester.pump();
      expect(state.options.autoScanOnStart, true);
      expect(state.scanning, true);
      scan.pending!.complete();
      await task;
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
