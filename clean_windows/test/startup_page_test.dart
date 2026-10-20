import 'dart:async';

import 'package:clean_windows/pages/startup_registry_pages.dart';
import 'package:clean_windows/services/startup_service.dart';
import 'package:clean_windows/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Service extends StartupService {
  Completer<List<StartupItem>>? pending;
  final records = [
    StartupItem(
      name: 'Registry app',
      command: 'registry.exe',
      location: 'Registry',
      enabled: true,
      group: 'registry',
      canToggle: true,
      hive: 'CurrentUser',
      view: 'Registry64',
      key: r'Software\Microsoft\Windows\CurrentVersion\Run',
      valueName: 'Registry app',
    ),
    StartupItem(
      name: 'Logon task',
      command: 'task.exe',
      location: 'ScheduledTask',
      enabled: true,
      group: 'task',
      sourceFile: r'\Task',
    ),
    StartupItem(
      name: 'Store declaration',
      command: 'store.exe',
      location: 'PackagedApp',
      enabled: false,
      group: 'package',
      stateKnown: false,
      sourceFile: 'package/task',
    ),
  ];
  @override
  Future<List<StartupItem>> list({bool force = false}) async =>
      pending != null ? pending!.future : records;
}

void main() {
  Widget app(_Service service) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: StartupPage(service: service)),
  );

  testWidgets('only manageable rows and relevant source filters are visible', (
    tester,
  ) async {
    final service = _Service();
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    expect(find.text('Registry app'), findsOneWidget);
    expect(find.text('Logon task'), findsNothing);
    expect(find.text('Store declaration'), findsNothing);
    expect(find.byType(Switch), findsOneWidget);
    expect(find.text('状态未知'), findsNothing);
    await tester.tap(find.byTooltip('启动项来源'));
    await tester.pumpAndSettle();
    expect(find.text('全部来源（1）'), findsWidgets);
    expect(find.textContaining('计划任务'), findsNothing);
    expect(find.textContaining('自动服务'), findsNothing);
    await tester.tap(find.text('启动文件夹（0）').last);
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的启动项'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unknown package state is not counted as disabled', (
    tester,
  ) async {
    await tester.pumpWidget(app(_Service()));
    await tester.pumpAndSettle();
    expect(find.text('状态由 Windows 管理'), findsNothing);
    expect(find.text('状态未知'), findsNothing);
    await tester.tap(find.text('已禁用'));
    await tester.pumpAndSettle();
    expect(find.text('Store declaration'), findsNothing);
    expect(find.text('没有匹配的启动项'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('refresh keeps rows visible and reports incomplete sources', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(560, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _Service()..warnings = ['Registry/Restricted'];
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    expect(find.textContaining('未能完整读取'), findsOneWidget);
    await tester.tap(find.textContaining('未能完整读取'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Registry/Restricted'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    service.pending = Completer<List<StartupItem>>();
    await tester.tap(find.byTooltip('刷新'));
    await tester.pump();
    expect(find.text('Registry app'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
    service.pending!.complete(service.records);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
}
