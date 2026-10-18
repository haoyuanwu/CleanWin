import 'dart:async';
import 'dart:io';

import 'package:clean_windows/pages/startup_registry_pages.dart';
import 'package:clean_windows/services/module_cache.dart';
import 'package:clean_windows/services/registry_scan_service.dart';
import 'package:clean_windows/state/app_state.dart';
import 'package:clean_windows/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Service extends RegistryScanService {
  _Service() {
    coverage = [
      RegistryCoverage.fromJson({
        'Hive': 'HKCU',
        'View': 'Registry32',
        'Path': r'Software\Classes',
        'Status': 'partial',
        'Checked': 12,
        'Keys': 8,
      }),
    ];
    warnings = ['HKCU/Restricted'];
  }
  Completer<List<RegistryIssue>>? pending;
  final deleted = <RegistryIssue>[];
  final records = [
    for (final view in ['Registry64', 'Registry32'])
      RegistryIssue(
        title: '$view missing path',
        detail: '目标未找到',
        hive: 'HKCU',
        view: view,
        keyPath: r'Software\Microsoft\Windows\CurrentVersion\App Paths\app.exe',
        valueName: '',
        severity: 'warn',
        category: 'appPaths',
        data: r'C:\Missing\app.exe',
        target: r'C:\Missing\app.exe',
        valueKind: 'String',
        deletable: true,
      ),
    RegistryIssue(
      title: 'MUI missing application',
      detail: '目标未找到',
      hive: 'HKCU',
      keyPath: r'Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache',
      valueName: r'C:\Missing\mui.exe.FriendlyAppName',
      severity: 'warn',
      category: 'mui',
      data: 'Missing application',
      target: r'C:\Missing\mui.exe',
      valueKind: 'String',
      deletable: true,
    ),
    RegistryIssue(
      title: 'COM review',
      detail: '需核对',
      hive: 'HKLM',
      keyPath: r'Software\Classes\CLSID\{id}\InprocServer32',
      valueName: '',
      severity: 'info',
      category: 'com',
    ),
  ];
  @override
  Future<List<RegistryIssue>> scan({bool force = false}) async =>
      pending != null ? pending!.future : List.of(records);
  @override
  Future<bool> deleteValue(RegistryIssue issue) async {
    deleted.add(issue);
    return true;
  }
}

void main() {
  late Directory fixture;
  late _Service service;
  late AppState state;
  setUp(() {
    AppState.debugSkipProcess = true;
    fixture = Directory('.dart_tool').createTempSync('registry_page_');
    service = _Service();
    state = AppState(
      registryService: service,
      scanCache: ModuleCache(namespace: 'scan', storageDirectory: fixture.path),
      preferencesCache: ModuleCache(
        namespace: 'prefs',
        storageDirectory: fixture.path,
      ),
    );
  });
  tearDown(() {
    state.dispose();
    fixture.deleteSync(recursive: true);
    AppState.debugSkipProcess = false;
  });
  Widget app() => ChangeNotifierProvider<AppState>.value(
    value: state,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: RegistryCleanPage()),
    ),
  );

  testWidgets(
    'categories start collapsed, omit readonly records and retain coverage details',
    (tester) async {
      await state.scanRegistry(force: true);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('COM review'), findsNothing);
      expect(find.widgetWithText(ExpansionTile, '程序路径'), findsOneWidget);
      expect(find.widgetWithText(ExpansionTile, 'MUI 缓存'), findsOneWidget);
      expect(find.text('Registry64 missing path'), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      await tester.tap(find.widgetWithText(ExpansionTile, '程序路径'));
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNWidgets(2));
      await tester.tap(find.byTooltip('查看扫描范围'));
      await tester.pumpAndSettle();
      expect(find.text(r'HKCU\Software\Classes'), findsOneWidget);
      expect(find.textContaining('12 次值检查'), findsOneWidget);
      expect(find.textContaining('HKCU/Restricted'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('same-key selections use the exact registry view', (
    tester,
  ) async {
    await state.scanRegistry(force: true);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ExpansionTile, '程序路径'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registry32 missing path'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清理所选（1）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();
    expect(service.deleted.single.view, 'Registry32');
    expect(
      state.registryIssues
          .where((issue) => issue.category == 'appPaths')
          .single
          .view,
      'Registry64',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('registry refresh retains existing rows on a narrow page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(560, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await state.scanRegistry(force: true);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ExpansionTile, '程序路径'));
    await tester.pumpAndSettle();
    service.pending = Completer<List<RegistryIssue>>();
    await tester.tap(find.text('开始扫描'));
    await tester.pump();
    expect(find.widgetWithText(ExpansionTile, '程序路径'), findsOneWidget);
    expect(find.text('Registry64 missing path'), findsNothing);
    expect(
      tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .every((box) => box.onChanged == null),
      isTrue,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
    service.pending!.complete(service.records);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'folded categories select together and searches preserve selections',
    (tester) async {
      await state.scanRegistry(force: true);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final categoryCheckbox = find.descendant(
        of: find.ancestor(
          of: find.text('程序路径'),
          matching: find.byType(ExpansionTile),
        ),
        matching: find.byType(Checkbox),
      );
      await tester.tap(categoryCheckbox);
      await tester.pumpAndSettle();
      expect(find.text('清理所选（2）'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);
      await tester.tap(find.byTooltip('搜索'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'no match');
      await tester.pumpAndSettle();
      expect(find.text('没有匹配的记录'), findsOneWidget);
      await tester.tap(find.byTooltip('清空搜索'));
      await tester.pumpAndSettle();
      expect(find.text('清理所选（2）'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);
      await tester.tap(categoryCheckbox);
      await tester.pumpAndSettle();
      expect(find.text('清理所选（0）'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
