import 'dart:async';
import 'dart:io';

import 'package:clean_windows/models/clean_models.dart';
import 'package:clean_windows/services/clean_service.dart';
import 'package:clean_windows/services/module_cache.dart';
import 'package:clean_windows/services/whitelist_service.dart';
import 'package:clean_windows/state/app_state.dart';
import 'package:clean_windows/theme/app_theme.dart';
import 'package:clean_windows/widgets/clean_progress_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Cache extends ModuleCache {
  _Cache(String directory)
    : super(storageDirectory: directory, namespace: 'scan');
  @override
  Future<void> setAsync(String key, Object? value) async => set(key, value);
}

class _Cleaner extends CleanService {
  late Completer<CleanReport> gate;
  void Function(CleanItem, String, int, int)? progress;
  CleanCancellation? token;
  @override
  Future<CleanReport> cleanItems(
    List<CleanItem> items, {
    void Function(CleanItem, String, int, int)? onItem,
    CleanCancellation? cancellation,
    bool recycle = false,
  }) {
    progress = onItem;
    token = cancellation;
    gate = Completer<CleanReport>.sync();
    return gate.future;
  }
}

void main() {
  late Directory fixture;
  late _Cleaner cleaner;
  late AppState state;
  setUp(() {
    AppState.debugSkipProcess = true;
    fixture = Directory('.dart_tool').createTempSync('clean_dialog_').absolute;
    cleaner = _Cleaner();
    state = AppState(
      cleanService: cleaner,
      scanCache: _Cache(fixture.path),
      preferencesCache: ModuleCache(
        storageDirectory: fixture.path,
        namespace: 'prefs',
      ),
      whitelistService: WhitelistService(storageDirectory: fixture.path),
    );
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
  });
  Widget app() => ChangeNotifierProvider<AppState>.value(
    value: state,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showCleanProgress(
              context,
              categories: {CleanCategory.downloads},
            ),
            child: const Text('删除'),
          ),
        ),
      ),
    ),
  );

  testWidgets('download cleanup keeps progress moving within one folder', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('删除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final item = CleanItem(
      id: 'download',
      name: '下载包',
      path: r'C:\Downloads\bundle',
      sizeBytes: 1,
      category: CleanCategory.downloads,
    );
    cleaner.progress!(item, '正在清理 下载包（5 / 100 个文件）\ncache.bin', 0, 1);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('5 / 100'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      isNull,
    );
    cleaner.gate.complete(CleanReport.empty());
    await tester.pumpAndSettle();
    expect(state.cleaning, isFalse);
    expect(find.text('完成'), findsOneWidget);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('正在清理'), findsNothing);
  });

  testWidgets('unexpected deletion errors release the dialog and busy state', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('删除'));
    await tester.pump();
    cleaner.gate.completeError(StateError('failed'));
    await tester.pumpAndSettle();
    expect(state.cleaning, isFalse);
    expect(find.text('清理未完成'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('清理未完成'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cancel requests a safe stop and shows partial results before closing',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.tap(find.text('删除'));
      await tester.pump();
      await tester.tap(find.text('取消清理'));
      await tester.pump();
      expect(cleaner.token!.requested, isTrue);
      expect(state.cleaning, isTrue);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      expect(find.textContaining('当前操作结束后停止'), findsOneWidget);
      cleaner.gate.complete(
        CleanReport(
          freedBytes: 1024,
          deletedCount: 1,
          skippedCount: 0,
          failedCount: 0,
          cancelled: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(state.cleaning, isFalse);
      expect(find.text('已取消清理'), findsOneWidget);
      expect(find.text('1.0 KB'), findsOneWidget);
      expect(find.text('清理完成'), findsNothing);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pump();
      expect(cleaner.token!.requested, isFalse);
      cleaner.gate.complete(CleanReport.empty());
      await tester.pumpAndSettle();
    },
  );
}
