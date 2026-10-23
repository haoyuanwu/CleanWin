import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:clean_windows/services/system_cleanup_service.dart';
import 'package:clean_windows/services/activity_service.dart';
import 'package:clean_windows/services/module_cache.dart';
import 'package:clean_windows/services/process_utils.dart';
import 'package:clean_windows/state/app_state.dart';
import 'package:clean_windows/theme/app_theme.dart';
import 'package:clean_windows/widgets/system_cleanup_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const report = '''
[==========================100.0%==========================]
Actual Size of Component Store : 12.8 GB
Number of Reclaimable Packages : 4
Component Store Cleanup Recommended : Yes
The operation completed successfully.
''';

class Runner implements MaintenanceRunner {
  final jobs = <MaintenanceJob>[];
  MaintenanceResult result = const MaintenanceResult(0, report);
  Completer<MaintenanceResult>? pending;
  void Function(String)? emit;
  bool cancelled = false;
  @override
  Future<MaintenanceResult> run(
    MaintenanceJob job,
    void Function(String) onOutput,
  ) async {
    jobs.add(job);
    emit = onOutput;
    return pending == null ? result : pending!.future;
  }

  @override
  void cancelAnalysis() {
    cancelled = true;
    pending?.complete(const MaintenanceResult(1, 'cancelled'));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  test(
    'maintenance never runs before analysis; only supported switches',
    () async {
      final runner = Runner();
      final task = SystemCleanupController(runner: runner);
      addTearDown(task.dispose);
      await task.clean();
      expect(runner.jobs, isEmpty);
      for (final job in MaintenanceJob.values) {
        final args = WindowsMaintenanceRunner.arguments(job);
        expect(args, contains('/NoRestart'));
        expect(args, isNot(contains('/ResetBase')));
        expect(args, isNot(contains('/SPSuperseded')));
      }
      await task.analyze();
      expect(task.canClean, isTrue);
      expect(task.report!.packages, 4);
      await task.clean();
      expect(task.phase, SystemCleanupPhase.completed);
      expect(task.report, isNull);
      expect(task.canClean, isFalse);
      expect(runner.jobs, [MaintenanceJob.analyze, MaintenanceJob.cleanup]);
    },
  );

  test(
    'unknown, failed and not recommended analysis cannot enable cleaning',
    () async {
      for (final result in [
        const MaintenanceResult(0, 'unknown output'),
        const MaintenanceResult(5, report),
        MaintenanceResult(
          0,
          report.replaceAll('Recommended : Yes', 'Recommended : No'),
        ),
        MaintenanceResult(0, report.replaceAll('Packages : 4', 'Packages : 0')),
      ]) {
        final runner = Runner()..result = result;
        final task = SystemCleanupController(runner: runner);
        await task.analyze();
        expect(task.canClean, isFalse);
        await task.clean();
        expect(runner.jobs, [MaintenanceJob.analyze]);
        task.dispose();
      }
    },
  );

  test(
    'analysis expires; failed cleanup is not successful; 3010 requires restart',
    () async {
      final runner = Runner();
      final task = SystemCleanupController(runner: runner);
      addTearDown(task.dispose);
      await task.analyze();
      task.analyzedAt = DateTime.now().subtract(const Duration(minutes: 31));
      await task.clean();
      expect(runner.jobs.length, 1);
      await task.analyze();
      runner.result = const MaintenanceResult(87, 'invalid parameter');
      await task.clean();
      expect(task.phase, SystemCleanupPhase.failed);
      expect(task.error, contains('87'));
      runner.result = const MaintenanceResult(0, report);
      await task.analyze();
      runner.result = const MaintenanceResult(3010, 'restart required');
      await task.clean();
      expect(task.phase, SystemCleanupPhase.completed);
      expect(task.restartRequired, isTrue);
    },
  );

  test(
    'analysis cancellation and duplicate requests do not launch cleanup',
    () async {
      final runner = Runner()..pending = Completer<MaintenanceResult>();
      final task = SystemCleanupController(runner: runner);
      addTearDown(task.dispose);
      final analysis = task.analyze();
      await task.analyze();
      await task.clean();
      runner.emit!('[ 42.0% ]');
      expect(task.progress, .42);
      task.cancelAnalysis();
      await analysis;
      expect(runner.cancelled, isTrue);
      expect(task.phase, SystemCleanupPhase.idle);
      expect(runner.jobs.length, 1);
    },
  );

  for (final width in [560.0, 1000.0]) {
    testWidgets('in-app confirmation and background state at $width', (
      tester,
    ) async {
      AppState.debugSkipProcess = true;
      ProcessUtils.debugSkip = true;
      final fixture = Directory.systemTemp.createTempSync(
        'system-cleanup-test',
      );
      final runner = Runner();
      final task = SystemCleanupController(runner: runner);
      final state = AppState(
        systemCleanup: task,
        scanCache: ModuleCache(
          namespace: 'scan',
          storageDirectory: fixture.path,
        ),
        preferencesCache: ModuleCache(
          namespace: 'prefs',
          storageDirectory: fixture.path,
        ),
      );
      addTearDown(() {
        state.dispose();
        fixture.deleteSync(recursive: true);
        AppState.debugSkipProcess = false;
        ProcessUtils.debugSkip = false;
      });
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              RepaintBoundary(key: boundary, child: child!),
          theme: AppTheme.light().copyWith(
            textTheme: AppTheme.light().textTheme.apply(
              bodyColor: Colors.white,
              displayColor: Colors.white,
            ),
            brightness: Brightness.dark,
            iconTheme: const IconThemeData(color: Color(0xFF9BE4DF)),
            colorScheme: const ColorScheme.dark(primary: Color(0xFF9BE4DF)),
          ),
          home: RepaintBoundary(
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: SystemCleanupPanel(state: state),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('system-cleanup-panel')),
        findsOneWidget,
      );
      expect(find.text('深度清理'), findsNothing);
      expect(runner.jobs, isEmpty);
      await tester.tap(find.text('分析组件'));
      await tester.pumpAndSettle();
      expect(find.text('4 个组件包可清理'), findsOneWidget);
      expect(find.textContaining('12.8 GB'), findsNothing);
      await tester.ensureVisible(find.text('清理组件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清理组件'));
      await tester.pumpAndSettle();
      expect(runner.jobs, [MaintenanceJob.analyze]);
      expect(find.text('确认清理'), findsOneWidget);
      if (const bool.fromEnvironment('UI_PREVIEWS')) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '.dart_tool/system-cleanup-previews/confirm-${width.toInt()}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      runner.pending = Completer<MaintenanceResult>();
      await tester.ensureVisible(find.text('确认清理'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认清理'));
      await tester.pump();
      expect(task.phase, SystemCleanupPhase.cleaning);
      expect(find.text('正在清理系统组件'), findsOneWidget);
      expect(TaskBoard.instance.tasks['system-cleanup']?.cancel, isNull);
      await state.scanOverview();
      expect(state.scanning, isFalse);
      expect(runner.jobs.length, 2);
      runner.pending!.complete(const MaintenanceResult(0, 'success'));
      await tester.pumpAndSettle();
      expect(find.text('系统组件清理成功'), findsOneWidget);
      expect(TaskBoard.instance.tasks.containsKey('system-cleanup'), isFalse);
      expect(find.textContaining('已释放 0'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
