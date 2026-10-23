import 'dart:async';

import 'package:clean_windows/models/installed_app.dart';
import 'package:clean_windows/pages/uninstall_page.dart';
import 'package:clean_windows/services/process_utils.dart';
import 'package:clean_windows/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _State extends AppState {
  int calls = 0;
  bool loading = false;
  bool fail = false;
  final forces = <bool>[];
  Completer<void>? pending;
  final records = <InstalledApp>[];
  bool loaded = false;
  @override
  bool get hasInstalledAppsSnapshot => loaded || records.isNotEmpty;
  @override
  bool get loadingApps => loading;
  @override
  List<InstalledApp> get installedApps => records
      .where(
        (app) =>
            app.displayName.toLowerCase().contains(appFilter.toLowerCase()),
      )
      .toList();
  @override
  Future<void> loadInstalledApps({bool force = false}) async {
    if (loading) return;
    calls++;
    forces.add(force);
    loading = true;
    notifyListeners();
    try {
      if (pending != null) await pending!.future;
      if (fail) throw StateError('failed');
      loaded = true;
      records
        ..clear()
        ..add(
          InstalledApp(
            displayName: 'Test Application',
            publisher: 'Test Publisher',
            uninstallString: 'test.exe',
          ),
        );
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}

void main() {
  setUp(() {
    AppState.debugSkipProcess = true;
    ProcessUtils.debugSkip = true;
  });
  tearDown(() {
    AppState.debugSkipProcess = false;
    ProcessUtils.debugSkip = false;
  });
  Widget app(_State state, {bool active = true}) =>
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          home: Scaffold(body: UninstallPage(active: active)),
        ),
      );

  testWidgets(
    'entering automatically loads results and scans again on re-entry',
    (tester) async {
      final state = _State()..pending = Completer<void>();
      await tester.pumpWidget(app(state, active: false));
      expect(state.calls, 0);
      await tester.pumpWidget(app(state));
      await tester.pump();
      expect(state.calls, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      state.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Test Application'), findsOneWidget);
      expect(state.forces, [false]);
      await tester.pumpWidget(app(state));
      expect(state.calls, 1);
      await tester.pumpWidget(app(state, active: false));
      await tester.pumpWidget(app(state));
      await tester.pumpAndSettle();
      expect(state.calls, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  testWidgets('refresh keeps the old list until new results are ready', (
    tester,
  ) async {
    final state = _State()
      ..records.add(InstalledApp(displayName: 'Previous Application'));
    state.pending = Completer<void>();
    await tester.pumpWidget(app(state));
    await tester.pump();
    expect(find.text('Previous Application'), findsOneWidget);
    expect(find.byKey(const ValueKey('apps-refresh-progress')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    state.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Previous Application'), findsNothing);
    expect(find.text('Test Application'), findsOneWidget);
    expect(find.byKey(const ValueKey('apps-refresh-progress')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets('re-entry refresh failure retains the successful previous list', (
    tester,
  ) async {
    final state = _State();
    await tester.pumpWidget(app(state));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(state, active: false));
    state.pending = Completer<void>();
    state.fail = true;
    await tester.pumpWidget(app(state));
    await tester.pump();
    expect(find.text('Test Application'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    state.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Test Application'), findsOneWidget);
    expect(find.textContaining('当前保留上次列表'), findsOneWidget);
    expect(state.calls, 2);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets(
    'refresh does not replace a filtered empty state with a spinner',
    (tester) async {
      final state = _State();
      await tester.pumpWidget(app(state));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('搜索'));
      await tester.tap(find.byTooltip('搜索'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.enterText(find.byType(TextField), 'does not exist');
      await tester.pumpAndSettle();
      state.pending = Completer<void>();
      await tester.tap(find.byTooltip('刷新列表'));
      await tester.pump();
      expect(find.text('没有匹配的软件'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      state.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('没有匹配的软件'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  testWidgets('automatic load failure offers a retry', (tester) async {
    final state = _State()..fail = true;
    await tester.pumpWidget(app(state));
    await tester.pumpAndSettle();
    expect(find.text('加载软件列表失败'), findsOneWidget);
    state.fail = false;
    await tester.tap(find.text('重新扫描'));
    await tester.pumpAndSettle();
    expect(find.text('Test Application'), findsOneWidget);
    expect(state.calls, 2);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets('table headers toggle name and size sort', (tester) async {
    final state = _State();
    state
      ..loaded = true
      ..records.addAll([
        InstalledApp(
          displayName: 'Beta Tool',
          estimatedSizeKb: 1024,
          uninstallString: 'b.exe',
        ),
        InstalledApp(
          displayName: 'Alpha Tool',
          estimatedSizeKb: 4096,
          uninstallString: 'a.exe',
        ),
        InstalledApp(
          displayName: 'Gamma Tool',
          estimatedSizeKb: 2048,
          uninstallString: 'g.exe',
        ),
      ]);
    await tester.pumpWidget(app(state, active: false));
    await tester.pumpAndSettle();

    List<String> rowNames() {
      const names = ['Alpha Tool', 'Beta Tool', 'Gamma Tool'];
      final found = <(String, double)>[];
      for (final name in names) {
        final f = find.text(name);
        if (f.evaluate().isNotEmpty) {
          found.add((name, tester.getTopLeft(f).dy));
        }
      }
      found.sort((a, b) => a.$2.compareTo(b.$2));
      return found.map((e) => e.$1).toList();
    }

    // 默认按名称 A→Z
    expect(rowNames(), ['Alpha Tool', 'Beta Tool', 'Gamma Tool']);

    // 点击「软件」表头 → Z→A
    await tester.tap(find.text('软件'));
    await tester.pumpAndSettle();
    expect(rowNames(), ['Gamma Tool', 'Beta Tool', 'Alpha Tool']);

    // 点击「大小」表头 → 默认大→小
    await tester.tap(find.text('大小'));
    await tester.pumpAndSettle();
    expect(rowNames(), ['Alpha Tool', 'Gamma Tool', 'Beta Tool']);

    // 再点「大小」→ 小→大
    await tester.tap(find.text('大小'));
    await tester.pumpAndSettle();
    expect(rowNames(), ['Beta Tool', 'Gamma Tool', 'Alpha Tool']);

    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets('measured sizes display with estimate marker', (tester) async {
    final state = _State();
    final measured = InstalledApp(
      displayName: 'Measured App',
      uninstallString: 'm.exe',
    )..measuredSizeBytes = 3 * 1024 * 1024;
    final unknown = InstalledApp(
      displayName: 'Unknown App',
      uninstallString: 'u.exe',
    );
    final registry = InstalledApp(
      displayName: 'Registry App',
      estimatedSizeKb: 2048,
      uninstallString: 'r.exe',
    );
    state
      ..loaded = true
      ..records.addAll([measured, unknown, registry]);
    await tester.pumpWidget(app(state, active: false));
    await tester.pumpAndSettle();

    expect(find.text('2.0 MB'), findsOneWidget); // 注册表
    expect(find.text('~3.0 MB'), findsOneWidget); // 目录估算
    expect(find.text('目录估算'), findsOneWidget);
    // 未知大小的软件显示 —；发布者为空的行也会显示 —
    expect(find.text('—'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets('unknown sizes stay last when sorting by size', (tester) async {
    final state = _State();
    state
      ..loaded = true
      ..records.addAll([
        InstalledApp(displayName: 'No Size App', uninstallString: 'n.exe'),
        InstalledApp(
          displayName: 'Small App',
          estimatedSizeKb: 10,
          uninstallString: 's.exe',
        ),
        InstalledApp(
          displayName: 'Large App',
          estimatedSizeKb: 10 * 1024,
          uninstallString: 'l.exe',
        ),
      ]);
    await tester.pumpWidget(app(state, active: false));
    await tester.pumpAndSettle();

    List<String> rowNames() {
      const names = ['No Size App', 'Small App', 'Large App'];
      final found = <(String, double)>[];
      for (final name in names) {
        final f = find.text(name);
        if (f.evaluate().isNotEmpty) {
          found.add((name, tester.getTopLeft(f).dy));
        }
      }
      found.sort((a, b) => a.$2.compareTo(b.$2));
      return found.map((e) => e.$1).toList();
    }

    await tester.tap(find.text('大小'));
    await tester.pumpAndSettle();
    expect(rowNames(), ['Large App', 'Small App', 'No Size App']);

    await tester.tap(find.text('大小'));
    await tester.pumpAndSettle();
    expect(rowNames(), ['Small App', 'Large App', 'No Size App']);

    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}
