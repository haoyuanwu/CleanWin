import 'dart:io';
import 'dart:ui' as ui;

import 'package:clean_windows/models/clean_models.dart';
import 'package:clean_windows/models/installed_app.dart';
import 'package:clean_windows/pages/downloads_page.dart';
import 'package:clean_windows/pages/performance_page.dart';
import 'package:clean_windows/pages/settings_page.dart';
import 'package:clean_windows/pages/startup_registry_pages.dart';
import 'package:clean_windows/pages/uninstall_page.dart';
import 'package:clean_windows/pages/whitelist_page.dart';
import 'package:clean_windows/services/module_cache.dart';
import 'package:clean_windows/services/performance_service.dart';
import 'package:clean_windows/services/process_utils.dart';
import 'package:clean_windows/services/registry_scan_service.dart';
import 'package:clean_windows/services/scan_service.dart';
import 'package:clean_windows/services/startup_service.dart';
import 'package:clean_windows/services/whitelist_service.dart';
import 'package:clean_windows/state/app_state.dart';
import 'package:clean_windows/theme/app_theme.dart';
import 'package:clean_windows/theme/module_theme.dart';
import 'package:clean_windows/widgets/trend_graph.dart';
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
    CleanCategory.downloads: ScanCategory(
      category: CleanCategory.downloads,
      scanDuration: Duration.zero,
      items: [
        for (final (name, mb) in [
          ('Windows.iso', 5400),
          ('Vacation.mp4', 2400),
          ('Editor.msi', 180),
          ('Archive.zip', 720),
        ])
          CleanItem(
            id: name,
            name: name,
            path: 'C:\\Users\\Demo\\Downloads\\$name',
            sizeBytes: mb * 1024 * 1024,
            category: CleanCategory.downloads,
            selected: false,
          ),
      ],
    ),
  };
}

class _State extends AppState {
  _State(String directory)
    : super(
        scanService: _Scan(),
        whitelistService: WhitelistService(storageDirectory: directory),
        scanCache: ModuleCache(namespace: 'scan', storageDirectory: directory),
        preferencesCache: ModuleCache(
          namespace: 'preferences',
          storageDirectory: directory,
        ),
      );
  final demoApps = [
    InstalledApp(
      displayName: 'Visual Studio Code',
      publisher: 'Microsoft',
      estimatedSizeKb: 512000,
      uninstallString: 'demo',
    ),
    InstalledApp(
      displayName: 'Blender',
      publisher: 'Blender Foundation',
      estimatedSizeKb: 1024000,
      uninstallString: 'demo',
    ),
    InstalledApp(
      displayName: 'OBS Studio',
      publisher: 'OBS Project',
      uninstallString: 'demo',
    ),
  ];
  @override
  List<InstalledApp> get installedApps => demoApps
      .where(
        (app) =>
            app.displayName.toLowerCase().contains(appFilter.toLowerCase()),
      )
      .toList();
  @override
  bool get hasInstalledAppsSnapshot => true;
  @override
  Future<void> loadInstalledApps({bool force = false}) async {}
  @override
  List<RegistryIssue> get registryIssues => [
    for (final (category, count) in [
      ('appPaths', 4),
      ('mui', 7),
      ('startup', 2),
    ])
      for (var i = 0; i < count; i++)
        RegistryIssue(
          title: '失效记录 $category $i',
          detail: '程序目标不存在',
          hive: 'HKCU',
          keyPath: switch (category) {
            'appPaths' =>
              'Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\app$i.exe',
            'mui' => r'Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache',
            _ => r'Software\Microsoft\Windows\CurrentVersion\Run',
          },
          valueName: switch (category) {
            'appPaths' => '',
            'mui' => 'C:\\Missing\\app$i.exe.FriendlyAppName',
            _ => '$i',
          },
          category: category,
          severity: 'warn',
          deletable: true,
          target: 'C:\\Missing\\app$i.exe',
          valueKind: 'String',
          data: 'C:\\Missing\\app$i.exe',
        ),
  ];
}

class _Startup extends StartupService {
  @override
  Future<List<StartupItem>> list({bool force = false}) async => [
    StartupItem(
      name: 'Microsoft OneDrive',
      command: 'OneDrive.exe',
      location: 'Registry',
      group: 'registry',
      enabled: true,
      canToggle: true,
      hive: 'CurrentUser',
      view: 'Registry64',
      key: r'Software\Microsoft\Windows\CurrentVersion\Run',
      valueName: 'demo1',
    ),
    StartupItem(
      name: 'Game Launcher',
      command: 'Launcher.exe',
      location: 'Registry',
      group: 'registry',
      enabled: false,
      canToggle: true,
      hive: 'CurrentUser',
      view: 'Registry64',
      key: r'Software\Microsoft\Windows\CurrentVersion\Run',
      valueName: 'demo2',
    ),
    StartupItem(
      name: 'Store App',
      command: 'App.exe',
      location: 'PackagedApp',
      group: 'package',
      enabled: false,
      stateKnown: false,
    ),
  ];
}

class _Performance extends PerformanceService {
  int calls = 0;
  @override
  Future<RuntimeSnapshot> sample() async {
    calls++;
    return RuntimeSnapshot(
      cpuPercent: 15 + calls % 9 * 4,
      memoryUsedPercent: 48 + calls % 7,
      cpuTempC: null,
      totalMemoryMb: 32768,
      usedMemoryMb: 16384,
      collectedAt: DateTime(2026, 10, 17, 15, 0, calls),
      topProcesses: const [
        ProcUsage(name: 'Browser', pid: 1001, cpu: 0, memoryMb: 1540),
        ProcUsage(name: 'Code Editor', pid: 1002, cpu: 0, memoryMb: 820),
        ProcUsage(name: 'File Explorer', pid: 1003, cpu: 0, memoryMb: 160),
      ],
    );
  }
}

void main() {
  late Directory fixture;
  late _State state;
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
  setUp(() {
    AppState.debugSkipProcess = true;
    ProcessUtils.debugSkip = true;
    fixture = Directory('.dart_tool')
        .createTempSync('visual_modules_')
        .absolute;
    state = _State(fixture.path);
  });
  tearDown(() {
    state.dispose();
    expect(
      fixture.path.startsWith(
        '${Directory('.dart_tool').absolute.path}${Platform.pathSeparator}',
      ),
      isTrue,
    );
    fixture.deleteSync(recursive: true);
    AppState.debugSkipProcess = false;
    ProcessUtils.debugSkip = false;
  });
  Widget page(Widget child) => ChangeNotifierProvider<AppState>.value(
    value: state,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      scrollBehavior: const CleanScrollBehavior(),
      home: Scaffold(
        backgroundColor: AppColors.bg,
        body: ModuleSurface(
          index: switch (child) {
            DownloadsPage() => 8,
            UninstallPage() => 5,
            StartupPage() => 6,
            RegistryCleanPage() => 7,
            WhitelistPage() => 9,
            SettingsPage() => 10,
            _ => 4,
          },
          child: child,
        ),
      ),
    ),
  );

  testWidgets(
    'download type charts filter without changing hidden selections',
    (tester) async {
      await tester.runAsync(() => state.scan(force: true));
      await tester.pumpWidget(page(const DownloadsPage()));
      await tester.pumpAndSettle();
      expect(state.selectedDownloadIds, isEmpty);
      await tester.tap(find.text('Vacation.mp4'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('insight-安装包')));
      await tester.pumpAndSettle();
      expect(find.text('Vacation.mp4'), findsNothing);
      expect(find.text('Editor.msi'), findsOneWidget);
      expect(state.selectedDownloadIds, {'Vacation.mp4'});
      await tester.tap(find.byKey(const ValueKey('insight-其他')));
      await tester.pumpAndSettle();
      expect(find.text('没有匹配的下载文件'), findsOneWidget);
      expect(find.textContaining('已选 1 项'), findsOneWidget);
      expect(state.selectedDownloadIds, {'Vacation.mp4'});
      await tester.tap(find.byKey(const ValueKey('insight-显示全部')));
      await tester.pumpAndSettle();
      expect(find.text('Vacation.mp4'), findsOneWidget);
      expect(state.selectedDownloadIds, {'Vacation.mp4'});
    },
  );

  testWidgets(
    'software size charts retain unknown-size programs and reset filters',
    (tester) async {
      await tester.pumpWidget(page(const UninstallPage(active: false)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('insight-未知大小')));
      await tester.pumpAndSettle();
      expect(find.text('OBS Studio'), findsOneWidget);
      expect(find.text('Blender'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('insight-按占用排列')));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Blender')).dy,
        lessThan(tester.getTopLeft(find.text('Visual Studio Code')).dy),
      );
      expect(find.text('OBS Studio'), findsOneWidget);
    },
  );

  testWidgets(
    'startup charts contain manageable states and registry filters keep groups folded',
    (tester) async {
      await tester.pumpWidget(page(StartupPage(service: _Startup())));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('insight-状态未知')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('insight-已禁用')));
      await tester.pumpAndSettle();
      expect(find.text('Store App'), findsNothing);
      expect(find.text('Game Launcher'), findsOneWidget);
      expect(find.text('Microsoft OneDrive'), findsNothing);
      await tester.pumpWidget(page(const RegistryCleanPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('insight-MUI 缓存')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ExpansionTile, 'MUI 缓存'), findsOneWidget);
      expect(find.widgetWithText(ExpansionTile, '程序路径'), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.text('清理所选（0）'), findsOneWidget);
    },
  );

  testWidgets(
    'whitelist chart filters paths and copy feedback preserves protection',
    (tester) async {
      await tester.runAsync(() async {
        await state.addManualWhitelist(r'C:\Protected\Work');
        await state.addManualWhitelist(r'D:\Protected\Photos');
      });
      MethodCall? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') copied = call;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(page(const WhitelistPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('insight-D:')));
      await tester.pumpAndSettle();
      expect(find.text('Work'), findsNothing);
      await tester.tap(find.byTooltip('复制路径'));
      await tester.pumpAndSettle();
      expect(copied?.arguments, {'text': r'D:\Protected\Photos'});
      expect(find.text('路径已复制'), findsOneWidget);
      expect(state.whitelist.length, 2);
    },
  );

  testWidgets(
    'performance history is bounded, missing temperatures stay absent and pause freezes it',
    (tester) async {
      final service = _Performance();
      await tester.pumpWidget(page(PerformancePage(service: service)));
      await tester.pump();
      for (var i = 0; i < 65; i++) {
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
      }
      final graphs = tester
          .widgetList<TrendGraph>(find.byType(TrendGraph))
          .toList();
      expect(graphs, hasLength(3));
      expect(graphs.first.values, hasLength(60));
      expect(graphs.last.values.every((value) => value == null), isTrue);
      await tester.tap(find.text('暂停刷新'));
      await tester.pump();
      final calls = service.calls;
      await tester.pump(const Duration(seconds: 5));
      expect(service.calls, calls);
      await tester.pumpWidget(const SizedBox());
    },
  );

  if (const bool.fromEnvironment('UI_PREVIEWS')) {
    testWidgets('export each populated module at desktop and narrow widths', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() => state.scan(force: true));
      await tester.runAsync(() async {
        await state.addManualWhitelist(r'C:\Projects\Workspace');
        await state.addManualWhitelist(r'D:\Photos\Originals');
      });
      await tester.runAsync(() => state.scan(force: true));
      for (final width in [1000.0, 560.0]) {
        tester.view.physicalSize = Size(width, 720);
        for (final name in [
          'downloads',
          'uninstall',
          'startup',
          'registry',
          'whitelist',
          'settings',
          'performance',
        ]) {
          final Widget child = switch (name) {
            'downloads' => const DownloadsPage(),
            'uninstall' => const UninstallPage(active: false),
            'startup' => StartupPage(service: _Startup()),
            'registry' => const RegistryCleanPage(),
            'whitelist' => const WhitelistPage(),
            'settings' => const SettingsPage(),
            _ => PerformancePage(service: _Performance()),
          };
          final key = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(key: key, child: page(child)),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          if (name == 'performance') {
            for (var i = 0; i < 12; i++) {
              await tester.pump(const Duration(seconds: 1));
              await tester.pump();
            }
          }
          expect(tester.takeException(), isNull, reason: '$name at $width');
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final output = File(
              '.dart_tool/ui_previews/$name-${width.toInt()}.png',
            );
            output.parent.createSync(recursive: true);
            output.writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
          if (name == 'startup' && width == 1000) {
            // Render the real soft menu shadow; the test default substitutes
            // a solid black outline when shadows are disabled.
            final disabledShadows = debugDisableShadows;
            debugDisableShadows = false;
            await tester.tap(find.byTooltip('启动项来源'));
            await tester.pumpAndSettle();
            expect(find.byType(Scrollbar), findsNothing);
            await tester.runAsync(() async {
              final boundary =
                  key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              File('.dart_tool/ui_previews/startup-menu.png')
                  .writeAsBytesSync(bytes!.buffer.asUint8List());
              image.dispose();
            });
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            debugDisableShadows = disabledShadows;
          }
          await tester.pumpWidget(const SizedBox());
        }
      }
    });
  }
}
