import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:clean_windows/app.dart';
import 'package:clean_windows/models/clean_models.dart';
import 'package:clean_windows/models/workspace_structure.dart';
import 'package:clean_windows/pages/health_check_page.dart';
import 'package:clean_windows/services/health_check_service.dart';
import 'package:clean_windows/services/module_cache.dart';
import 'package:clean_windows/services/process_utils.dart';
import 'package:clean_windows/services/whitelist_service.dart';
import 'package:clean_windows/state/app_state.dart';
import 'package:clean_windows/theme/app_theme.dart';
import 'package:clean_windows/widgets/workspace_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const rows =
    '[{"id":"fixture","label":"检查信息","value":"本地只读快照","status":"info"}]';
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
  test('all cleanup and system checks have a single destination', () {
    for (final category in CleanCategory.values) {
      final destination = cleanupOwner(category);
      if (category == CleanCategory.memoryDumps) {
        expect(destination, -1);
        continue;
      }
      expect(
        workspaceNavigation.expand((group) => group.items),
        contains(workspaceRoute(destination)),
      );
    }
    expect(cleanupOwner(CleanCategory.downloads), 8);
    expect(cleanupOwner(CleanCategory.appLeftovers), 14);
    expect(inspectionOwners['hardware'], 12);
    expect(inspectionOwners['network'], 13);
    expect(
      spaceCleanupScanCategories,
      isNot(contains(CleanCategory.downloads)),
    );
    expect(
      spaceCleanupScanCategories,
      isNot(contains(CleanCategory.registryJunk)),
    );
  });

  test('scoped inspections execute only requested scripts and retain other results', () async {
    final scripts = <String>[];
    final controller = HealthCheckController(
      service: HealthCheckService(
        runner: (script, timeout) async {
          scripts.add(script);
          return PsResult(exitCode: 0, stdout: rows, stderr: '');
        },
      ),
    );
    await controller.scan(phaseIds: {'network'});
    expect(scripts, hasLength(1));
    expect(scripts.single, contains('Get-NetConnectionProfile'));
    expect(scripts.single, isNot(contains('Win32_Processor')));
    expect(scripts.single, isNot(contains('startupScanScript')));
    await controller.scan(phaseIds: {'hardware'});
    expect(controller.sections.map((section) => section.id), [
      'network',
      'hardware',
    ]);
    expect(controller.isFresh('network'), isTrue);
    expect(controller.isFresh('hardware'), isTrue);
    controller.dispose();
  });

  test('startup snapshot runs once, remains local and does not scan storage or apps', () async {
    final scripts = <String>[];
    final gate = Completer<PsResult>();
    final controller = HealthCheckController(
      service: HealthCheckService(
        runner: (script, timeout) async {
          scripts.add(script);
          if (scripts.length == 1) return gate.future;
          return PsResult(exitCode: 0, stdout: rows, stderr: '');
        },
      ),
    );
    final first = controller.readOnStartup();
    final second = controller.readOnStartup();
    expect(identical(first, second), isTrue);
    expect(controller.startupReading, isTrue);
    gate.complete(PsResult(exitCode: 0, stdout: rows, stderr: ''));
    await first;
    expect(controller.sections.map((section) => section.id).toSet(), {
      'hardware',
      'network',
    });
    expect(scripts, hasLength(2));
    expect(scripts.join(), isNot(contains('SendPingAsync')));
    expect(scripts.join(), isNot(contains('GetHostAddressesAsync')));
    expect(scripts.join(), isNot(contains('flushdns')));
    expect(controller.startupReading, isFalse);
    await controller.readOnStartup();
    expect(scripts, hasLength(2));
    controller.dispose();
  });

  testWidgets(
    'automatic system reading stays quiet and shows results when ready',
    (tester) async {
      final gate = Completer<PsResult>();
      final controller = HealthCheckController(
        service: HealthCheckService(runner: (script, timeout) => gate.future),
      );
      final task = controller.readOnStartup();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: HealthCheckPage(
              controller: controller,
              sectionIds: const {'network'},
              title: '网络诊断',
              onNavigate: (_) {},
              onScanTraces: () async => false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('取消检查'), findsNothing);
      expect(find.text('正在后台读取本机信息'), findsOneWidget);
      gate.complete(PsResult(exitCode: 0, stdout: rows, stderr: ''));
      await task;
      await tester.pumpAndSettle();
      expect(find.text('本地只读快照'), findsOneWidget);
      expect(find.text('刷新'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('workspace lazily mounts pages and preserves input across tabs', (
    tester,
  ) async {
    var index = 0;
    var active = false;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return WorkspaceTabs(
                active: active,
                index: index,
                onChanged: (i) => setState(() => index = i),
                tabs: const [
                  (label: '第一项', icon: Icons.folder),
                  (label: '第二项', icon: Icons.hub),
                ],
                builder: (i, selected) => TextField(key: ValueKey('input-$i')),
              );
            },
          ),
        ),
      ),
    );
    expect(find.byType(TextField, skipOffstage: false), findsNothing);
    update(() => active = true);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '保留我的筛选');
    await tester.tap(find.text('第二项'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField, skipOffstage: false), findsNWidgets(2));
    await tester.tap(find.text('第一项'));
    await tester.pumpAndSettle();
    expect(find.text('保留我的筛选'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [1000.0, 560.0]) {
    testWidgets('network detail isolated, persistent, fits $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gate = Completer<PsResult>();
      var calls = 0;
      final controller = HealthCheckController(
        service: HealthCheckService(
          runner: (script, timeout) {
            calls++;
            if (calls > 1) {
              return Future.value(
                PsResult(
                  exitCode: -1,
                  stdout: '',
                  stderr: 'fixture unavailable',
                ),
              );
            }
            return gate.future;
          },
        ),
      );
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: RepaintBoundary(
            key: boundary,
            child: Scaffold(
              backgroundColor: const Color(0xFFF0F3F4),
              body: HealthCheckPage(
                title: '网络诊断',
                sectionIds: const {'network'},
                controller: controller,
                onNavigate: (_) {},
                onScanTraces: () async => false,
              ),
            ),
          ),
        ),
      );
      expect(calls, 0);
      expect(find.text('外网探测'), findsOneWidget);
      expect(find.text('刷新 DNS'), findsOneWidget);
      final tools = find.byKey(const ValueKey('network-top-actions'));
      expect(
        tester.getRect(tools).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(ListView).first).top),
      );
      Future<void> capture(String phase) async {
        expect(tester.takeException(), isNull);
        if (!const bool.fromEnvironment('UI_PREVIEWS')) return;
        await tester.runAsync(() async {
          final img =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          final output = File(
            '.dart_tool/workspace_previews/network-${width.toInt()}-$phase.png',
          );
          output.parent.createSync(recursive: true);
          output.writeAsBytesSync(bytes!.buffer.asUint8List());
          img.dispose();
        });
      }

      await tester.pumpAndSettle();
      await capture('idle');
      await tester.tap(find.text('读取信息'));
      await tester.pump(const Duration(milliseconds: 300));
      await capture('busy');
      gate.complete(PsResult(exitCode: 0, stdout: rows, stderr: ''));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('本地只读快照'), findsOneWidget);
      expect(find.text('硬件概况'), findsNothing);
      expect(find.text('外网探测'), findsOneWidget);
      expect(
        find.descendant(of: tools, matching: find.text('刷新 DNS')),
        findsOneWidget,
      );
      await capture('results');
      await tester.tap(find.text('刷新'));
      await tester.pumpAndSettle();
      expect(find.text('检查未完成'), findsOneWidget);
      await capture('error');
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }

  testWidgets(
    'startup reads local system once and workspace navigation reuses results',
    (tester) async {
      AppState.debugSkipProcess = true;
      ProcessUtils.debugSkip = true;
      final fixture = Directory('.dart_tool')
          .createTempSync('workspace_product_');
      var systemCalls = 0;
      final state = AppState(
        scanCache: ModuleCache(
          namespace: 'scan',
          storageDirectory: fixture.path,
        ),
        preferencesCache: ModuleCache(
          namespace: 'prefs',
          storageDirectory: fixture.path,
        ),
        whitelistService: WhitelistService(storageDirectory: fixture.path),
        healthChecks: HealthCheckController(
          service: HealthCheckService(
            runner: (s, t) async {
              systemCalls++;
              return PsResult(exitCode: 0, stdout: rows, stderr: '');
            },
          ),
        ),
      );
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('clean_windows/window'),
            (call) async => false,
          );
      final shellKey = GlobalKey();
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: RepaintBoundary(
            key: shellKey,
            child: const CleanWindowsApp(initialIndex: 8),
          ),
        ),
      );
      Future<void> captureShell(String name) async {
        if (!const bool.fromEnvironment('UI_PREVIEWS')) return;
        for (final width in [1280.0, 840.0]) {
          tester.view.physicalSize = Size(width, 900);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.runAsync(() async {
            final img =
                await (shellKey.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final data = await img.toByteData(format: ui.ImageByteFormat.png);
            final output = File(
              '.dart_tool/workspace_previews/$name-${width.toInt()}.png',
            );
            output.parent.createSync(recursive: true);
            output.writeAsBytesSync(data!.buffer.asUint8List());
            img.dispose();
          });
        }
        tester.view.physicalSize = const Size(1280, 900);
        await tester.pumpAndSettle();
      }

      await tester.pumpAndSettle();
      expect(find.text('文件管理'), findsOneWidget);
      expect(find.text('下载审查'), findsOneWidget);
      expect(find.text('下载管理'), findsOneWidget);
      await captureShell('files');
      expect(systemCalls, 2);
      expect(find.byKey(const ValueKey('nav-8')), findsNothing);
      expect(find.byKey(const ValueKey('nav-6')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('nav-4')));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('网络诊断'));
      await tester.pumpAndSettle();
      expect(systemCalls, 2);
      await tester.tap(find.text('刷新'));
      await tester.pumpAndSettle();
      expect(systemCalls, 3);
      await tester.tap(find.byKey(const ValueKey('nav-2')));
      await tester.pumpAndSettle();
      expect(find.text('下载管理'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nav-4')));
      await tester.pumpAndSettle();
      expect(find.text('本地只读快照'), findsOneWidget);
      expect(systemCalls, 3);
      await captureShell('system-network');
      await tester.tap(find.byKey(const ValueKey('nav-5')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('应用残留'));
      await tester.pumpAndSettle();
      await captureShell('apps-leftovers');
      await tester.tap(find.byKey(const ValueKey('nav-7')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Windows 设置'));
      await tester.pumpAndSettle();
      await captureShell('maintenance');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
      fixture.deleteSync(recursive: true);
      AppState.debugSkipProcess = false;
      ProcessUtils.debugSkip = false;
    },
  );
}
