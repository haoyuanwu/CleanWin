import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:clean_windows/pages/disk_pages.dart';
import 'package:clean_windows/services/activity_service.dart';
import 'package:clean_windows/services/disk_services.dart';
import 'package:clean_windows/theme/app_theme.dart';
import 'package:clean_windows/theme/module_theme.dart';
import 'package:clean_windows/widgets/disk_treemap.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Disk extends DiskAnalysisService {
  final opened = <String>[];
  @override
  List<String> availableDrives() => ['C', 'D'];
  @override
  void invalidate(String path) {}
  @override
  bool isCached(String path) => false;
  @override
  Future<DirUsage> analyzeDirectory(
    String path, {
    int maxConcurrent = 8,
    void Function(DirUsage partial)? onProgress,
    CancelToken? cancel,
  }) async {
    opened.add(path);
    return DirUsage(
      path: path,
      name: path,
      sizeBytes: 1024,
      children: [
        DirUsage(path: '${path}Example', name: 'Example', sizeBytes: 1024),
      ],
    );
  }
}

class _Large extends LargeFileService {
  @override
  List<FileEntry> loadCached(String root, int minBytes) => [
    FileEntry(
      path: '${root}archive.zip',
      name: 'archive.zip',
      sizeBytes: 8 * 1024 * 1024 * 1024,
      modified: DateTime(2026),
    ),
  ];
}

class _PendingDisk extends _Disk {
  final childResult = Completer<DirUsage>();
  CancelToken? childCancellation;

  @override
  Future<DirUsage> analyzeDirectory(
    String path, {
    int maxConcurrent = 8,
    void Function(DirUsage partial)? onProgress,
    CancelToken? cancel,
  }) {
    if (path == r'C:\Example') {
      opened.add(path);
      childCancellation = cancel;
      return childResult.future;
    }
    return super.analyzeDirectory(path, cancel: cancel, onProgress: onProgress);
  }
}

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('UI_PREVIEWS')) return;
    final textFont = FontLoader('Segoe UI')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File(r'C:\Windows\Fonts\msyh.ttc').readAsBytesSync(),
          ),
        ),
      );
    await textFont.load();
    await (FontLoader('Consolas')..addFont(
          Future.value(
            ByteData.sublistView(
              File(r'C:\Windows\Fonts\consola.ttf').readAsBytesSync(),
            ),
          ),
        ))
        .load();
    final iconFont = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconFont.load();
  });
  Widget app(Widget child) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    scrollBehavior: const CleanScrollBehavior(),
    home: Scaffold(
      backgroundColor: AppColors.bg,
      body: ModuleSurface(index: child is LargeFilesPage ? 3 : 2, child: child),
    ),
  );

  testWidgets(
    'disk dropdown, single view toggle and rightmost back work together',
    (tester) async {
      final service = _Disk();
      await tester.pumpWidget(app(DiskAnalysisPage(service: service)));
      await tester.pumpAndSettle();
      expect(find.text('磁盘分析'), findsNothing);
      expect(find.byType(SegmentedButton<bool>), findsNothing);
      expect(find.byType(DiskTreemap), findsOneWidget);
      expect(service.opened, [r'C:\']);
      final back = find.byKey(const ValueKey('disk-back'));
      expect(tester.widget<IconButton>(back).onPressed, isNull);
      expect(
        tester.getTopLeft(back).dx,
        greaterThan(tester.getTopLeft(find.byTooltip('刷新分析')).dx),
      );
      await tester.tap(find.byTooltip('切换为列表'));
      await tester.pumpAndSettle();
      expect(find.byType(DiskTreemap), findsNothing);
      await tester.tap(find.widgetWithText(ListTile, 'Example'));
      await tester.pumpAndSettle();
      expect(service.opened.last, r'C:\Example');
      expect(tester.widget<IconButton>(back).onPressed, isNotNull);
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(service.opened, [r'C:\', r'C:\Example']);
      expect(find.widgetWithText(ListTile, 'Example'), findsOneWidget);
      await tester.tap(find.byTooltip('切换磁盘'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('磁盘 D:').last);
      await tester.pumpAndSettle();
      expect(service.opened.last, r'D:\');
      expect(tester.widget<IconButton>(back).onPressed, isNull);
      await tester.tap(find.byTooltip('切换为地图'));
      await tester.pumpAndSettle();
      expect(find.byType(DiskTreemap), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'back and drive navigation keep directory scans running and reuse completed results',
    (tester) async {
      final service = _PendingDisk();
      var active = true;
      late StateSetter changeModule;
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (context, setState) {
              changeModule = setState;
              return IndexedStack(
                index: active ? 0 : 1,
                children: [
                  DiskAnalysisPage(active: active, service: service),
                  const Center(child: Text('其他模块')),
                ],
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('切换为列表'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Example'));
      await tester.pump(const Duration(milliseconds: 200));
      final back = find.byKey(const ValueKey('disk-back'));
      expect(tester.widget<IconButton>(back).onPressed, isNotNull);
      expect(find.text('正在分析目录…'), findsOneWidget);
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(service.childCancellation!.cancelled, isFalse);
      expect(find.widgetWithText(ListTile, 'Example'), findsOneWidget);
      // Re-enter the running task without starting another traversal.
      await tester.tap(find.widgetWithText(ListTile, 'Example'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        service.opened.where((path) => path == r'C:\Example'),
        hasLength(1),
      );
      await tester.tap(find.byTooltip('切换磁盘'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text('磁盘 D:').last);
      await tester.pumpAndSettle();
      expect(
        TaskBoard.instance.tasks.values.any(
          (task) => task.detail.contains(r'C:\Example'),
        ),
        isTrue,
      );
      changeModule(() => active = false);
      await tester.pumpAndSettle();
      expect(find.text('其他模块'), findsOneWidget);
      expect(service.childCancellation!.cancelled, isFalse);
      service.childResult.complete(
        DirUsage(
          path: r'C:\Example',
          name: 'Example',
          sizeBytes: 8192,
          fileCount: 1,
          children: [
            DirUsage(
              path: r'C:\Example\finished.bin',
              name: 'finished.bin',
              sizeBytes: 8192,
              isDirectory: false,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'finished.bin'), findsNothing);
      expect(service.childCancellation!.cancelled, isFalse);
      expect(
        TaskBoard.instance.tasks.values.any(
          (task) => task.detail.contains(r'C:\Example'),
        ),
        isFalse,
      );
      changeModule(() => active = true);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('切换磁盘'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('磁盘 C:').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Example'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'finished.bin'), findsOneWidget);
      expect(find.text('正在分析目录…'), findsNothing);
      expect(
        service.opened.where((path) => path == r'C:\Example'),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'large file actions stay grouped and selection lives in the footer',
    (tester) async {
      tester.view.physicalSize = const Size(560, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app(LargeFilesPage(service: _Large())));
      await tester.pumpAndSettle();
      expect(find.text('大文件'), findsNothing);
      expect(find.text(r'C:\archive.zip'), findsNothing);
      expect(find.byTooltip('文件操作'), findsNothing);
      await tester.tap(
        find.text('archive.zip'),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('打开所在位置'), findsOneWidget);
      expect(find.text('复制路径'), findsOneWidget);
      expect(find.text('移动到其他目录'), findsOneWidget);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final remove = find.widgetWithText(ElevatedButton, '删除所选');
      expect(tester.widget<ElevatedButton>(remove).onPressed, isNull);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(tester.widget<ElevatedButton>(remove).onPressed, isNotNull);
      await tester.tap(find.byKey(const ValueKey('insight-影音')));
      await tester.pumpAndSettle();
      expect(find.text('archive.zip'), findsNothing);
      expect(tester.widget<ElevatedButton>(remove).onPressed, isNotNull);
      await tester.tap(find.byKey(const ValueKey('insight-显示全部')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue,
      );
      expect(
        tester.getTopLeft(remove).dy,
        greaterThan(tester.getTopLeft(find.byType(CheckboxListTile)).dy),
      );
      await tester.tap(find.byTooltip('文件大小阈值'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('大于 1 GB').last);
      await tester.pumpAndSettle();
      expect(tester.widget<ElevatedButton>(remove).onPressed, isNull);
      await tester.tap(find.byTooltip('搜索'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'missing');
      await tester.pumpAndSettle();
      expect(find.text('archive.zip'), findsNothing);
      expect(find.text('已选 0 项 · 0 B'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  if (const bool.fromEnvironment('UI_PREVIEWS')) {
    testWidgets('export disk page toolbars', (tester) async {
      tester.view.physicalSize = const Size(1000, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final entry in <String, Widget>{
        'disk-toolbar': DiskAnalysisPage(service: _Disk()),
        'large-files-toolbar': LargeFilesPage(service: _Large()),
      }.entries) {
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(key: key, child: app(entry.value)),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('.dart_tool/ui_previews/${entry.key}.png');
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
