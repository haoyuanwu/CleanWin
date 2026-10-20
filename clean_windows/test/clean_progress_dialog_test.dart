import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

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
  Widget app({bool dark = false}) => ChangeNotifierProvider<AppState>.value(
    value: state,
    child: MaterialApp(
      theme: dark
          ? AppTheme.light().copyWith(
              brightness: Brightness.dark,
              colorScheme: const ColorScheme.dark(),
              textTheme: AppTheme.light().textTheme.apply(
                bodyColor: Colors.white,
                displayColor: Colors.white,
              ),
            )
          : AppTheme.light(),
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

  setUpAll(() async {
    if (!const bool.fromEnvironment('CLEAN_DIALOG_PREVIEW')) return;
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

  testWidgets(
    'cancel buttons stay readable with inherited light styles in both themes',
    (tester) async {
      double contrast(Color a, Color b) {
        final first = a.computeLuminance(), second = b.computeLuminance();
        return first > second
            ? (first + .05) / (second + .05)
            : (second + .05) / (first + .05);
      }

      for (final dark in [false, true]) {
        await tester.pumpWidget(app(dark: dark));
        await tester.tap(find.text('删除'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final button = find.widgetWithText(OutlinedButton, '取消清理');
        final style = Theme.of(tester.element(button))
            .outlinedButtonTheme
            .style!;
        expect(
          contrast(
            style.foregroundColor!.resolve({})!,
            style.backgroundColor!.resolve({})!,
          ),
          greaterThanOrEqualTo(4.5),
        );
        expect(style.side!.resolve({})!.width, greaterThanOrEqualTo(1.5));
        await tester.tap(button);
        await tester.pump();
        final disabled = {WidgetState.disabled};
        expect(
          contrast(
            style.foregroundColor!.resolve(disabled)!,
            style.backgroundColor!.resolve(disabled)!,
          ),
          greaterThanOrEqualTo(4.5),
        );
        cleaner.gate.complete(CleanReport.empty());
        await tester.pumpAndSettle();
        await tester.tap(find.text('完成'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('successful cleanup automatically shows the success panel', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 760);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('dialog-preview'),
        child: app(dark: true),
      ),
    );
    await tester.tap(find.text('删除'));
    await tester.pump();
    expect(find.byKey(const ValueKey('cleanup-progress')), findsOneWidget);
    cleaner.gate.complete(
      CleanReport(
        freedBytes: 64 * 1024 * 1024,
        deletedCount: 2,
        skippedCount: 0,
        failedCount: 0,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('清理成功'), findsOneWidget);
    expect(find.text('64.0 MB'), findsOneWidget);
    expect(find.text('成功 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('cleanup-progress')), findsNothing);
    expect(find.text('取消清理'), findsNothing);
    expect(state.cleaning, isFalse);
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('CLEAN_DIALOG_PREVIEW')) {
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('dialog-preview')),
        );
        final preview = await boundary.toImage(pixelRatio: 1);
        final data = await preview.toByteData(format: ui.ImageByteFormat.png);
        File('.dart_tool/clean-success-preview.png')
            .writeAsBytesSync(data!.buffer.asUint8List());
        preview.dispose();
      });
    }
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('清理成功'), findsNothing);
  });

  testWidgets(
    'partial failure does not claim success and exposes failure details',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.tap(find.text('删除'));
      await tester.pump();
      cleaner.gate.complete(
        CleanReport(
          freedBytes: 1024,
          deletedCount: 1,
          skippedCount: 1,
          failedCount: 1,
          failures: ['文件正在使用，已跳过'],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('清理成功'), findsNothing);
      expect(find.text('部分清理完成'), findsOneWidget);
      expect(find.text('跳过 1'), findsOneWidget);
      await tester.tap(find.text('查看未处理项目'));
      await tester.pumpAndSettle();
      expect(find.text('文件正在使用，已跳过'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('完成'));
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'recycled downloads show moved capacity rather than released zero and fit a small window',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 540);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app());
      await tester.tap(find.text('删除'));
      await tester.pump();
      cleaner.gate.complete(
        CleanReport(
          freedBytes: 0,
          recycledBytes: 1024 * 1024,
          deletedCount: 1,
          skippedCount: 0,
          failedCount: 0,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('清理成功'), findsOneWidget);
      expect(find.text('0 B'), findsNothing);
      expect(find.text('已释放空间'), findsNothing);
      expect(find.text('已移入回收站'), findsOneWidget);
      expect(find.text('1.0 MB'), findsOneWidget);
      expect(find.textContaining('已移到回收站 1.0 MB'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('完成'));
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('mixed cleanup separates released space from recycled capacity', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('删除'));
    await tester.pump();
    cleaner.gate.complete(
      CleanReport(
        freedBytes: 64 * 1024 * 1024,
        recycledBytes: 32 * 1024 * 1024,
        deletedCount: 2,
        skippedCount: 0,
        failedCount: 0,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('已释放空间'), findsOneWidget);
    expect(find.text('64.0 MB'), findsOneWidget);
    expect(find.textContaining('已移到回收站 32.0 MB'), findsOneWidget);
    expect(find.text('96.0 MB'), findsNothing);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
  });

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
