import 'package:clean_windows/app.dart';
import 'package:clean_windows/services/process_utils.dart';
import 'package:clean_windows/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

void main() {
  setUp(() {
    AppState.debugSkipProcess = true;
    ProcessUtils.debugSkip = true;
  });

  tearDown(() {
    AppState.debugSkipProcess = false;
    ProcessUtils.debugSkip = false;
  });

  testWidgets('App builds with all nav sections', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: const CleanWindowsApp(),
      ),
    );

    expect(find.text('CleanWin'), findsWidgets);
    expect(find.text('概览与清理'), findsWidgets);
    expect(find.byKey(const ValueKey('nav-1')), findsNothing);
    expect(find.text('文件管理'), findsWidgets);
    expect(find.text('系统监控'), findsWidgets);
    expect(find.text('应用管理'), findsWidgets);
    expect(find.text('系统维护'), findsWidgets);
    expect(find.byKey(const ValueKey('nav-3')), findsNothing);
    expect(find.byKey(const ValueKey('nav-6')), findsNothing);
    expect(find.byKey(const ValueKey('nav-8')), findsNothing);
    expect(find.text('白名单'), findsWidgets);
    expect(find.text('设置'), findsWidgets);
    expect(find.text('为你的电脑\n释放一片星空'), findsOneWidget);
  });

  testWidgets(
    'whole top drags the window without changing controls or body gestures',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final methods = <String>[];
      const channel = MethodChannel('clean_windows/window');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        methods.add(call.method);
        return call.method == 'isMaximized' || call.method == 'isElevated'
            ? false
            : null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppState(),
          child: const CleanWindowsApp(),
        ),
      );
      await tester.pumpAndSettle();
      for (final start in const [
        Offset(500, 20),
        Offset(700, 40),
        Offset(1100, 55),
        Offset(80, 40),
      ]) {
        methods.clear();
        await tester.dragFrom(start, const Offset(60, 20));
        await tester.pump();
        expect(
          methods.where((method) => method == 'startDrag'),
          hasLength(1),
          reason: 'Top position $start should drag',
        );
      }
      methods.clear();
      await tester.tap(find.byTooltip('最小化'));
      await tester.pumpAndSettle();
      expect(methods, contains('minimize'));
      expect(methods, isNot(contains('startDrag')));
      methods.clear();
      await tester.dragFrom(const Offset(600, 400), const Offset(0, -90));
      await tester.pumpAndSettle();
      expect(methods, isNot(contains('startDrag')));
      await tester.tap(find.byKey(const ValueKey('nav-2')));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.tap(find.text('大文件'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
      methods.clear();
      await tester.tap(find.byTooltip('切换磁盘'));
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<String>), findsWidgets);
      expect(methods, isNot(contains('startDrag')));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
