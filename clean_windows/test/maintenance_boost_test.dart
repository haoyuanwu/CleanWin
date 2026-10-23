import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:clean_windows/models/clean_models.dart';
import 'package:clean_windows/services/memory_boost_service.dart';
import 'package:clean_windows/services/scan_service.dart';
import 'package:clean_windows/services/module_cache.dart';
import 'package:clean_windows/services/process_utils.dart';
import 'package:clean_windows/services/registry_scan_service.dart';
import 'package:clean_windows/state/app_state.dart';
import 'package:clean_windows/widgets/quick_boost_dialog.dart';
import 'package:clean_windows/pages/windows_settings_page.dart';
import 'package:clean_windows/theme/app_theme.dart';
import 'package:clean_windows/theme/module_theme.dart';
import 'package:clean_windows/widgets/monitor_surface.dart';
import 'package:clean_windows/services/clean_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _Cleaner extends CleanService {
  List<CleanItem> received = [];
  @override
  Future<CleanReport> cleanItems(
    List<CleanItem> items, {
    void Function(CleanItem, String, int, int)? onItem,
    bool recycle = false,
    CleanCancellation? cancellation,
  }) async {
    received = items;
    return CleanReport(
      freedBytes: 0,
      deletedCount: items.length,
      skippedCount: 0,
      failedCount: 0,
      completedItemIds: items.map((i) => i.id).toSet(),
    );
  }
}

void main() {
  const render = bool.fromEnvironment('UI_PREVIEWS');
  setUpAll(() async {
    if (!render) return;
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
  late Directory root;
  setUp(
    () => root = Directory.systemTemp.createTempSync('cleanwin-maintenance'),
  );
  tearDown(() => root.deleteSync(recursive: true));
  File put(String path, {int days = 10, int bytes = 8}) {
    final f = File(p.joinAll([root.path, ...path.split('/')]))
      ..parent.createSync(recursive: true);
    f.writeAsBytesSync(List.filled(bytes, 1));
    f.setLastModifiedSync(DateTime.now().subtract(Duration(days: days)));
    return f;
  }

  Map<String, String> env() => {
    'USERPROFILE': root.path,
    'LOCALAPPDATA': p.join(root.path, 'Local'),
    'APPDATA': p.join(root.path, 'Roaming'),
    'SystemRoot': p.join(root.path, 'Windows'),
    'ProgramData': p.join(root.path, 'ProgramData'),
  };
  test(
    'occupied browser cache stays measurable and is never selected for cleanup',
    () async {
      final busy = put(
        'Local/Google/Chrome/User Data/Default/Cache/Cache_Data/data_0',
      );
      final lock = await busy.open();
      final scanner = ScanService(environment: env(), driveRoots: []);
      try {
        final result = (await scanner.scanAll(
          categories: {CleanCategory.browserCache},
        ))[CleanCategory.browserCache]!;
        expect(result.totalSizeBytes, 8);
        expect(result.selectedSizeBytes, 0);
        expect(result.blockedFileCount, 1);
        final item = result.items.single;
        expect(item.blockedSizeBytes, 8);
        expect(item.scannedFiles, isEmpty);
        expect(item.hasCleanableFiles, isFalse);
        result.selectAll(true);
        expect(result.selectedCount, 0);
        expect(busy.existsSync(), isTrue);
      } finally {
        await lock.close();
      }
      final unlocked = (await scanner.scanAll(
        categories: {CleanCategory.browserCache},
      ))[CleanCategory.browserCache]!;
      expect(unlocked.totalSizeBytes, 8);
      expect(unlocked.items.single.sizeBytes, 8);
      expect(unlocked.blockedFileCount, 0);
    },
    skip: !Platform.isWindows,
  );
  test('temporary acceleration scanner excludes fresh files, other caches and documents', () async {
    final old = put('Local/Temp/old.tmp');
    final windows = put('Windows/Temp/old.temp');
    final doc = put('Local/Temp/report.docx');
    final fresh = put('Windows/Temp/fresh.tmp', days: 1);
    final dll = put('Windows/Temp/installer.dll');
    final scanner = ScanService(
      environment: env(),
      driveRoots: [],
      operabilityProbe: (paths) async => paths.toSet(),
    )..temporaryOnly = true;
    final result = await scanner.scanAll(
      categories: {CleanCategory.systemCache},
    );
    final files = result.values
        .expand((c) => c.items)
        .expand((i) => i.scannedFiles ?? <String>[])
        .toSet();
    expect(files, {old.path, windows.path});
    expect(files, isNot(contains(doc.path)));
    expect(fresh.existsSync(), isTrue);
    expect(dll.existsSync(), isTrue);
  });
  test('temporary cleanup preserves other cache choices and cleans only explicit IDs', () async {
    put('Local/Temp/old.tmp');
    put('Windows/Temp/old.temp');
    put('Local/Microsoft/Windows/Explorer/thumbcache_test.db');
    final cleaner = _Cleaner();
    AppState.debugSkipProcess = true;
    final state = AppState(
      scanService: ScanService(
        environment: env(),
        driveRoots: [],
        operabilityProbe: (paths) async => paths.toSet(),
      ),
      cleanService: cleaner,
      scanCache: ModuleCache(namespace: 'scan2', storageDirectory: root.path),
      preferencesCache: ModuleCache(
        namespace: 'prefs2',
        storageDirectory: root.path,
      ),
    );
    try {
      await state.scanOverview();
      final thumbnail = state.categories
          .expand((c) => c.items)
          .firstWhere((i) => i.id == 'thumbnails');
      state.toggleItem(thumbnail);
      await state.scanTemporaryFiles();
      expect(
        state.categories
            .expand((c) => c.items)
            .firstWhere((i) => i.id == 'thumbnails')
            .selected,
        isFalse,
      );
      final temps = state.categories
          .expand((c) => c.items)
          .where((i) => {'user_temp', 'windows_temp'}.contains(i.id))
          .toList();
      for (final item in temps) {
        item.selected = true;
      }
      await state.cleanSelected(
        categories: {CleanCategory.systemCache},
        itemIds: temps.map((i) => i.id).toSet(),
      );
      expect(cleaner.received.map((i) => i.id).toSet(), {
        'user_temp',
        'windows_temp',
      });
      expect(
        state.categories
            .expand((c) => c.items)
            .any((i) => i.id == 'thumbnails'),
        isTrue,
      );
    } finally {
      state.dispose();
      AppState.debugSkipProcess = false;
    }
  });

  test('registry additions restrict types, roots, individual values and reference counts', () {
    RegistryIssue issue(
      String category,
      String key,
      String name,
      Object data,
      String target,
      String kind,
    ) => RegistryIssue(
      title: '失效记录',
      detail: '缺失',
      hive: 'HKLM',
      keyPath: key,
      valueName: name,
      severity: 'warn',
      category: category,
      data: data,
      target: target,
      valueKind: kind,
      deletable: true,
    );
    expect(
      issue(
        'sharedDll',
        r'Software\Microsoft\Windows\CurrentVersion\SharedDLLs',
        r'C:\Gone\lib.dll',
        0,
        r'C:\Gone\lib.dll',
        'DWord',
      ).canDelete,
      isTrue,
    );
    expect(
      issue(
        'sharedDll',
        r'Software\Microsoft\Windows\CurrentVersion\SharedDLLs',
        r'C:\Gone\lib.dll',
        1,
        r'C:\Gone\lib.dll',
        'DWord',
      ).canDelete,
      isFalse,
    );
    expect(
      issue(
        'fonts',
        r'Software\Microsoft\Windows NT\CurrentVersion\Fonts',
        'Example',
        'missing.ttf',
        r'C:\Windows\Fonts\missing.ttf',
        'String',
      ).canDelete,
      isTrue,
    );
    expect(
      issue(
        'applications',
        r'Software\Classes\Applications\gone.exe\shell\open\command',
        '',
        r'"C:\Gone\gone.exe" "%1"',
        r'C:\Gone\gone.exe',
        'String',
      ).canDelete,
      isTrue,
    );
    expect(
      issue(
        'contextMenu',
        r'Software\Classes\Directory\shell\Gone\command',
        '',
        r'C:\Gone\gone.exe',
        r'C:\Gone\gone.exe',
        'String',
      ).canDelete,
      isTrue,
    );
    expect(
      issue(
        'contextMenu',
        r'Software\Classes\CLSID\{abc}\command',
        '',
        r'C:\Gone\gone.exe',
        r'C:\Gone\gone.exe',
        'String',
      ).canDelete,
      isFalse,
    );
  });
  test('memory inspect is read-only; optimization requires explicit invocation and bad data fails', () async {
    final scripts = <String>[];
    final service = MemoryBoostService(
      runner: (script, _) async {
        scripts.add(script);
        return PsResult(
          exitCode: 0,
          stdout: jsonEncode({
            'Candidates': 3,
            'Trimmed': script.contains(r'::Run($true') ? 2 : 0,
            'BeforeAvailable': 1000,
            'AfterAvailable': 900,
          }),
          stderr: '',
        );
      },
    );
    expect((await service.inspect()).trimmed, 0);
    expect(scripts.single, contains(r'::Run($false'));
    expect((await service.optimize()).trimmed, 2);
    expect((await service.optimize()).availableChange, -100);
    expect(MemoryBoostService.script, isNot(contains('Stop-Process')));
    expect(MemoryBoostService.script, contains('owner.User.Value!=sid'));
    expect(
      MemoryBoostService.script,
      contains('MainWindowHandle!=IntPtr.Zero'),
    );
    final bad = MemoryBoostService(
      runner: (_, _) async => PsResult(exitCode: 0, stdout: '{}', stderr: ''),
    );
    await expectLater(bad.inspect(), throwsFormatException);
  });
  for (final width in [560.0, 1000.0]) {
    testWidgets('maintenance tools and confirmed acceleration fit $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: RepaintBoundary(
            key: key,
            child: const Scaffold(
              body: ModuleSurface(index: 7, child: WindowsSettingsPage()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('默认应用'), findsOneWidget);
      expect(find.text('通知'), findsOneWidget);
      expect(find.text('设置建议'), findsNothing);
      Future<void> capture(String name) async {
        if (!render) return;
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '.dart_tool/maintenance-previews/$name-${width.toInt()}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('settings');
      put('Local/Temp/old.tmp');
      AppState.debugSkipProcess = true;
      final state = AppState(
        scanService: ScanService(
          environment: env(),
          driveRoots: [],
          operabilityProbe: (paths) async => paths.toSet(),
        ),
        scanCache: ModuleCache(namespace: 'scan', storageDirectory: root.path),
        preferencesCache: ModuleCache(
          namespace: 'prefs',
          storageDirectory: root.path,
        ),
      );
      var operations = 0;
      final memory = MemoryBoostService(
        runner: (script, _) async {
          if (script.contains(r'::Run($true')) operations++;
          return PsResult(
            exitCode: 0,
            stdout: jsonEncode({
              'Candidates': 2,
              'Trimmed': operations,
              'BeforeAvailable': 1000,
              'AfterAvailable': 2000,
            }),
            stderr: '',
          );
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: RepaintBoundary(
            key: key,
            child: Scaffold(
              body: MonitorSurface(
                child: QuickBoostDialog(state: state, service: memory),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('清理旧临时文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('分析加速项'));
      await tester.pumpAndSettle();
      expect(operations, 0);
      expect(find.text('可整理后台进程 2 个'), findsOneWidget);
      await capture('boost-confirm');
      await tester.tap(find.text('确认加速'));
      await tester.pumpAndSettle();
      expect(operations, 1);
      expect(find.text('加速处理完成'), findsOneWidget);
      expect(find.textContaining('可用内存增加'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture('boost-result');
      await tester.pumpWidget(const SizedBox());
      state.dispose();
      AppState.debugSkipProcess = false;
    });
  }
}
