import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:clean_windows/models/clean_models.dart';
import 'package:clean_windows/models/scan_options.dart';
import 'package:clean_windows/services/clean_service.dart';
import 'package:clean_windows/services/module_cache.dart';
import 'package:clean_windows/services/process_utils.dart';
import 'package:clean_windows/services/scan_service.dart';
import 'package:clean_windows/services/whitelist_service.dart';
import 'package:clean_windows/state/app_state.dart';
import 'package:clean_windows/theme/app_theme.dart';
import 'package:clean_windows/widgets/space_cleanup_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:clean_windows/pages/clean_page.dart';
import 'package:clean_windows/services/health_check_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

class _Scan extends ScanService {
  Set<CleanCategory>? requested;
  Completer<Map<CleanCategory, ScanCategory>>? pending;
  Map<CleanCategory, ScanCategory> rows = {};
  void Function(ScanCategory)? report;
  @override
  Future<Map<CleanCategory, ScanCategory>> scanAll({
    Set<CleanCategory>? categories,
    void Function(ScanProgress)? onProgress,
    void Function(ScanCategory)? onCategoryDone,
  }) async {
    requested = categories;
    report = onCategoryDone;
    if (pending != null) return pending!.future;
    for (final row in rows.values) {
      onCategoryDone?.call(row);
    }
    return rows;
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
  late Map<String, String> env;
  File put(String root, String relative, {int days = 10, int bytes = 7}) {
    final f = File(p.joinAll([root, ...relative.split('/')]))
      ..parent.createSync(recursive: true);
    f.writeAsBytesSync(List.filled(bytes, 1));
    f.setLastModifiedSync(DateTime.now().subtract(Duration(days: days)));
    return f;
  }

  ScanService scanner() => ScanService(
    environment: env,
    driveRoots: [],
    powerShellRunner: (s, t) async =>
        PsResult(exitCode: 0, stdout: '', stderr: ''),
    operabilityProbe: (paths) async => paths.toSet(),
  );
  AppState state(_Scan scan, {HealthCheckController? health}) => AppState(
    healthChecks: health,
    scanService: scan,
    whitelistService: WhitelistService(
      storageDirectory: p.join(fixture.path, 'settings'),
    ),
    scanCache: ModuleCache(namespace: 'scan', storageDirectory: fixture.path),
    preferencesCache: ModuleCache(
      namespace: 'prefs',
      storageDirectory: fixture.path,
    ),
  );
  ScanCategory category(CleanCategory c, String id, int bytes) => ScanCategory(
    category: c,
    items: [
      CleanItem(
        id: id,
        name: id,
        path: p.join(fixture.path, id),
        sizeBytes: bytes,
        category: c,
        selected: false,
      ),
    ],
    scanDuration: Duration.zero,
  );
  setUp(() {
    AppState.debugSkipProcess = true;
    ProcessUtils.debugSkip = true;
    fixture = Directory.systemTemp.createTempSync('merged_clean_').absolute;
    env = {
      'USERPROFILE': fixture.path,
      'LOCALAPPDATA': p.join(fixture.path, 'Local'),
      'APPDATA': p.join(fixture.path, 'Roaming'),
      'ProgramData': p.join(fixture.path, 'ProgramData'),
      'SystemRoot': p.join(fixture.path, 'Windows'),
      'SystemDrive': fixture.path,
      'DOWNLOADS': p.join(fixture.path, 'Downloads'),
      'USER_SID': 'S-1-5-21-100',
    };
  });
  tearDown(() {
    expect(
      p.isWithin(Directory.systemTemp.absolute.path, fixture.path),
      isTrue,
    );
    fixture.deleteSync(recursive: true);
    AppState.debugSkipProcess = false;
    ProcessUtils.debugSkip = false;
  });

  test('merged narrow rules never widen into sibling files, even during deep discovery', () async {
    const widgetRoot =
        'Packages/MicrosoftWindows.Client.WebExperience_cw5n1h2txyewy/LocalState/EBWebView/Default';
    final local = env['LOCALAPPDATA']!;
    final selected = [
      put(local, 'Microsoft/Windows/Explorer/ThumbCacheToDelete/thm1.tmp'),
      put(local, 'Microsoft/Windows/Explorer/IconCacheToDelete/icn1.tmp'),
      put(local, 'Microsoft/Terminal Server Client/Cache/tile.bmc'),
      put(local, 'Microsoft/clr_v4.0/debug.log'),
      put(local, 'Microsoft/clr_v4.0_32/debug.log'),
      put(local, '$widgetRoot/Cache/Cache_Data/f_123'),
      put(local, '$widgetRoot/Cache/Cache_Data/data_0'),
      put(local, '$widgetRoot/Cache/Cache_Data/index'),
      put(local, '$widgetRoot/Code Cache/js/script_0'),
      put(local, 'Microsoft/Windows/WebCache.old/backup.edb'),
    ];
    final protected = [
      put(local, 'Microsoft/Windows/Explorer/ThumbCacheToDelete/keep.tmp'),
      put(
        local,
        'Microsoft/Windows/Explorer/ThumbCacheToDelete/nested/thm2.tmp',
      ),
      put(local, 'Microsoft/Windows/Explorer/IconCacheToDelete/icn1.txt'),
      put(local, 'Microsoft/Windows/Explorer/iconcache_personal.txt'),
      put(local, 'Microsoft/Terminal Server Client/Cache/session.rdp'),
      put(local, 'Microsoft/clr_v4.0/debug.dll'),
      put(local, 'Microsoft/clr_v4.0/new.log', days: 0),
      put(local, '$widgetRoot/Cache/Cache_Data/keep.user'),
      put(local, '$widgetRoot/Code Cache/js/not_script_1'),
      put(local, '$widgetRoot/Session Storage/personal'),
      put(local, 'Microsoft/Windows/WebCache/current.edb'),
      put(local, 'Microsoft/Windows/WebCache.old/recent.edb', days: 0),
    ];
    final scan = scanner()..options = const ScanOptions(deepScan: true);
    final result = await scan.scanAll(
      categories: {
        CleanCategory.systemCache,
        CleanCategory.systemLogs,
        CleanCategory.appCache,
      },
    );
    final found = result.values.expand((s) => s.items).toList();
    final files = found
        .expand((i) => i.scannedFiles ?? const <String>[])
        .toList();
    expect(files, unorderedEquals(selected.map((f) => f.path)));
    expect(files.toSet().length, files.length);
    expect(found.every((i) => i.selected), isTrue);
    for (final item in found) {
      item.selected = true;
    }
    final report = await CleanService().cleanItems(found);
    expect(report.failedCount, 0);
    expect(report.freedBytes, selected.length * 7);
    for (final f in protected) {
      expect(f.existsSync(), isTrue, reason: f.path);
    }
    for (final f in selected) {
      expect(f.existsSync(), isFalse, reason: f.path);
    }
  });

  test('extended review stays bounded, retains recent diagnostics and only recommends old temporary files', () async {
    final local = env['LOCALAPPDATA']!, windows = env['SystemRoot']!;
    final temp = put(local, 'Temp/old.tmp');
    final kept = [
      put(local, 'Temp/personal.zip'),
      put(local, 'Temp/new.tmp', days: 0),
      put(local, 'Microsoft/Windows/WER/Settings/keep.cfg'),
      put(local, 'Microsoft/Windows/WER/ReportQueue/new.wer', days: 0),
      put(local, 'CrashDumps/new.dmp', days: 0),
      put(windows, 'MEMORY.DMP', days: 0),
      put(windows, 'SoftwareDistribution/DataStore/DataStore.edb'),
      put(windows, 'SoftwareDistribution/Download/pending.cab'),
      put(env['APPDATA']!, 'UnknownSoftware/one/two/three/Cache/resource'),
    ];
    final dump = put(local, 'CrashDumps/old.dmp');
    final wer = put(local, 'Microsoft/Windows/WER/ReportQueue/old.wer');
    final log = put(windows, 'Logs/CBS/old.log');
    final recent = put(env['APPDATA']!, 'Microsoft/Windows/Recent/item.lnk');
    final result = await scanner().scanAll(
      categories: spaceCleanupScanCategories,
    );
    final items = result.values.expand((s) => s.items).toList();
    final paths = items
        .expand((i) => i.scannedFiles ?? const <String>[])
        .toList();
    expect(
      paths,
      unorderedEquals([temp.path, wer.path, log.path, recent.path]),
    );
    expect(
      items.where((i) => i.selected).expand((i) => i.scannedFiles!),
      unorderedEquals([temp.path, wer.path, log.path, recent.path]),
    );
    expect(dump.existsSync(), isTrue);
    expect(paths.toSet().length, paths.length);
    for (final f in kept) {
      expect(paths, isNot(contains(f.path)));
    }
    expect(oneClickScanCategories, isNot(contains(CleanCategory.systemLogs)));
    expect(
      spaceCleanupScanCategories,
      isNot(contains(CleanCategory.windowsUpdate)),
    );
  });

  test('narrow rules keep whitelist and operability checks', () async {
    final local = env['LOCALAPPDATA']!;
    final denied = put(
      local,
      'Microsoft/Windows/Explorer/ThumbCacheToDelete/thm_denied.tmp',
    );
    final allowed = put(
      local,
      'Microsoft/Windows/Explorer/ThumbCacheToDelete/thm_ok.tmp',
    );
    final protected = put(
      local,
      'Microsoft/Terminal Server Client/Cache/personal.bmc',
    );
    final whitelist = WhitelistService(
      storageDirectory: p.join(fixture.path, 'white'),
    );
    await whitelist.add(protected.path);
    final scan = ScanService(
      environment: env,
      driveRoots: [],
      powerShellRunner: (s, t) async =>
          PsResult(exitCode: 0, stdout: '', stderr: ''),
      operabilityProbe: (paths) async =>
          paths.where((s) => s != denied.path).toSet(),
    )..whitelist = whitelist;
    final results = await scan.scanAll(categories: {CleanCategory.systemCache});
    final paths = results.values
        .expand((s) => s.items)
        .expand((i) => i.scannedFiles!)
        .toList();
    expect(paths, [allowed.path]);
    expect(protected.existsSync(), isTrue);
  });

  test('full rescan retains visible results until replaced; cancelled categories remain reviewable', () async {
    final scan = _Scan()
      ..rows = {
        CleanCategory.systemCache: category(
          CleanCategory.systemCache,
          'old',
          123,
        ),
      };
    final app = state(scan);
    await app.scan();
    scan.pending = Completer();
    final pending = app.scan(force: true);
    expect(app.totalFoundBytes, 123);
    expect(app.categories.single.items.single.id, 'old');
    app.cancelScan();
    scan.pending!.complete({});
    await pending;
    expect(app.totalFoundBytes, 123);
    expect(app.scanError, contains('取消'));
    scan.pending = null;
    scan.rows = {
      CleanCategory.systemCache: ScanCategory(
        category: CleanCategory.systemCache,
        items: [],
        scanDuration: Duration.zero,
      ),
    };
    await app.scan(force: true);
    expect(app.totalFoundBytes, 0);
    app.dispose();
  });

  testWidgets(
    'space panel shares scope, selection totals and post-clean results',
    (tester) async {
      final scan = _Scan()
        ..rows = {
          CleanCategory.systemCache: category(
            CleanCategory.systemCache,
            'review',
            2048,
          ),
        };
      final app = state(scan);
      var views = 0;
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: app,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: SpaceCleanupPanel(onViewResults: () => views++),
            ),
          ),
        ),
      );
      expect(find.text('可审查 2.0 KB'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('scan-space-cleanup')));
      await tester.pumpAndSettle();
      expect(scan.requested, spaceCleanupScanCategories);
      expect(find.textContaining('已选 0 B'), findsOneWidget);
      app.toggleItem(app.categories.single.items.single);
      await tester.pumpAndSettle();
      expect(find.textContaining('已选 2.0 KB'), findsOneWidget);
      await tester.tap(find.text('查看与清理'));
      expect(views, 1);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  test(
    'cleanup never starts system inspection and cancel stays scoped',
    () async {
      var healthCalls = 0;
      final health = HealthCheckController(
        service: HealthCheckService(
          runner: (script, timeout) async {
            healthCalls++;
            return PsResult(exitCode: 0, stdout: '[]', stderr: '');
          },
        ),
      );
      final scan = _Scan()..pending = Completer();
      final app = state(scan, health: health);
      final future = app.scanOverview();
      expect(scan.requested, spaceCleanupScanCategories);
      expect(scan.requested, isNot(contains(CleanCategory.downloads)));
      expect(healthCalls, 0);
      app.cancelScan();
      expect(health.cancelled, isFalse);
      expect(scan.cancellation!.requested, isTrue);
      scan.pending!.complete({});
      await future;
      expect(app.scanning, isFalse);
      expect(healthCalls, 0);
      app.dispose();
    },
  );

  testWidgets(
    'overview lists cleanup content without unrelated system checks',
    (tester) async {
      var healthCalls = 0;
      final health = HealthCheckController(
        service: HealthCheckService(
          runner: (script, timeout) async => PsResult(
            exitCode: 0,
            stderr: '',
            stdout: jsonEncode([
              {
                'id': 'row_${healthCalls++}',
                'label': '只读检查',
                'value': '已读取',
                'status': 'info',
              },
            ]),
          ),
        ),
      );
      final scan = _Scan()
        ..rows = {
          CleanCategory.systemLogs: ScanCategory(
            category: CleanCategory.systemLogs,
            scanDuration: Duration.zero,
            items: [
              CleanItem(
                id: 'log',
                name: '旧诊断日志',
                path: p.join(fixture.path, 'old.log'),
                category: CleanCategory.systemLogs,
                sizeBytes: 1024,
                fileCount: 3,
                selected: false,
              ),
            ],
          ),
          CleanCategory.memoryDumps: category(
            CleanCategory.memoryDumps,
            '崩溃转储',
            4096,
          ),
        };
      final app = state(scan, health: health);
      await tester.runAsync(() => app.scanOverview());
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: app,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CleanPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(healthCalls, 0);
      expect(find.byKey(const ValueKey('home-space-cleanup')), findsNothing);
      expect(find.text('开始体检'), findsNothing);
      await tester.tap(find.text('查看结果'));
      await tester.pumpAndSettle();
      expect(find.text('电脑体检'), findsNothing);
      expect(find.text('硬件概况'), findsNothing);
      expect(find.text('系统日志'), findsOneWidget);
      expect(find.textContaining('3 个文件'), findsOneWidget);
      await tester.ensureVisible(find.text('系统日志'));
      await tester.tap(find.text('系统日志'));
      await tester.pumpAndSettle();
      expect(find.text('旧诊断日志'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  for (final width in [1000.0, 560.0]) {
    testWidgets('merged space review preview at $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final scan = _Scan()
        ..rows = {
          CleanCategory.systemCache: category(
            CleanCategory.systemCache,
            '临时文件',
            204800,
          ),
          CleanCategory.memoryDumps: category(
            CleanCategory.memoryDumps,
            '崩溃转储',
            51200000,
          ),
          CleanCategory.downloads: category(
            CleanCategory.downloads,
            '安装包',
            104857600,
          ),
        };
      final controller = HealthCheckController(
        service: HealthCheckService(
          runner: (s, t) async => PsResult(
            exitCode: 0,
            stdout:
                '[{"id":"demo","label":"只读检查","value":"已读取","status":"info"}]',
            stderr: '',
          ),
        ),
      );
      final app = state(scan, health: controller);
      final key = GlobalKey();
      await tester.runAsync(() => app.scanOverview());
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: app,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            theme: AppTheme.light(),
            home: RepaintBoundary(
              key: key,
              child: Scaffold(
                backgroundColor: const Color(0xFFF0F3F4),
                body: const CleanPage(),
              ),
            ),
          ),
        ),
      );
      Future<void> capture(String phase) async {
        if (app.scanning) {
          await tester.pump(const Duration(milliseconds: 500));
        } else {
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final img = await boundary.toImage();
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '.dart_tool/health_previews/overview-merged-${width.toInt()}-$phase.png',
          );
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(bytes!.buffer.asUint8List());
          img.dispose();
        });
      }

      await tester.pumpAndSettle();
      await tester.tap(find.text('查看结果'));
      await tester.pumpAndSettle();
      await capture('results');
      scan.pending = Completer();
      late Future<void> future;
      await tester.runAsync(() async {
        future = app.scanOverview();
      });
      await capture('scanning');
      await tester.runAsync(() async {
        app.cancelScan();
        scan.pending!.complete({});
        await future;
      });
      await capture('cancelled');
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    }, skip: !const bool.fromEnvironment('UI_PREVIEWS'));
  }
}
