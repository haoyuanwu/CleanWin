import 'dart:io';
import 'dart:ui' as ui;

import 'package:clean_windows/models/clean_models.dart';
import 'package:clean_windows/services/activity_service.dart';
import 'package:clean_windows/services/disk_services.dart';
import 'package:clean_windows/services/duplicate_service.dart';
import 'package:clean_windows/services/module_cache.dart';
import 'package:clean_windows/services/process_utils.dart';
import 'package:clean_windows/services/registry_backups.dart';
import 'package:clean_windows/services/whitelist_service.dart';
import 'package:clean_windows/state/app_state.dart';
import 'package:clean_windows/theme/app_theme.dart';
import 'package:clean_windows/theme/module_theme.dart';
import 'package:clean_windows/widgets/registry_backups_dialog.dart';
import 'package:clean_windows/widgets/duplicate_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

class _Backups extends RegistryBackups {
  @override
  Future<List<RegistryBackup>> list() async => [];
}

class _Duplicates extends DuplicateService {
  _Duplicates(WhitelistService whitelist) : super(whitelist: whitelist);
  final group = DuplicateGroup('checked-content', [
    for (final name in ['original.zip', 'copy.zip'])
      FileEntry(
        path: 'C:\\Example\\$name',
        name: name,
        sizeBytes: 80 * 1024 * 1024,
        modified: DateTime(2026),
      ),
  ]);
  int recycled = 0;
  @override
  Future<List<DuplicateGroup>> scan(
    String root, {
    int minBytes = 1024 * 1024,
    CleanCancellation? cancellation,
    void Function(String)? onProgress,
  }) async => [group];
  @override
  Future<CleanReport> recycleSelected(
    List<DuplicateGroup> groups,
    CleanCancellation cancellation,
  ) async {
    final selected = groups
        .expand((group) => group.files)
        .where((file) => file.selected)
        .toList();
    recycled += selected.length;
    return CleanReport(
      freedBytes: 0,
      deletedCount: selected.length,
      skippedCount: 0,
      failedCount: 0,
      recycledBytes: selected.fold(0, (sum, file) => sum + file.sizeBytes),
      completedItemIds: selected.map((file) => file.path).toSet(),
    );
  }
}

void main() {
  late Directory fixture;
  late AppState state;
  late ActivityJournal journal;
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
    fixture = Directory('.dart_tool').createTempSync('product_ui_').absolute;
    journal = ActivityJournal(
      cache: ModuleCache(namespace: 'activity', storageDirectory: fixture.path),
    );
    state = AppState(
      journal: journal,
      whitelistService: WhitelistService(storageDirectory: fixture.path),
      scanCache: ModuleCache(namespace: 'scan', storageDirectory: fixture.path),
      preferencesCache: ModuleCache(
        namespace: 'prefs',
        storageDirectory: fixture.path,
      ),
    );
    journal.record(
      '下载管理',
      CleanReport(
        freedBytes: 0,
        deletedCount: 2,
        skippedCount: 0,
        failedCount: 0,
        recycledBytes: 100 * 1024 * 1024,
      ),
      names: ['安装包.zip', '视频副本.mp4'],
    );
  });
  tearDown(() {
    for (final id in TaskBoard.instance.tasks.keys.toList()) {
      TaskBoard.instance.finish(id);
    }
    state.dispose();
    expect(
      p.isWithin(Directory('.dart_tool').absolute.path, fixture.path),
      isTrue,
    );
    fixture.deleteSync(recursive: true);
    AppState.debugSkipProcess = false;
    ProcessUtils.debugSkip = false;
  });
  Widget app(Widget dialog) => ChangeNotifierProvider<AppState>.value(
    value: state,
    child: MaterialApp(
      theme: AppTheme.light(),
      scrollBehavior: const CleanScrollBehavior(),
      home: Scaffold(body: ModuleSurface(index: 3, child: dialog)),
    ),
  );

  testWidgets(
    'registry recovery is independent of removed task and history pages',
    (tester) async {
      await tester.pumpWidget(app(RegistryBackupsDialog(backups: _Backups())));
      await tester.pumpAndSettle();
      expect(find.text('注册表备份'), findsOneWidget);
      expect(find.text('任务与记录'), findsNothing);
      expect(find.text('清理记录'), findsNothing);
    },
  );

  testWidgets(
    'duplicate results require manual selection and preserve a locked copy',
    (tester) async {
      final service = _Duplicates(state.whitelist);
      await tester.pumpWidget(
        app(DuplicateDialog(root: r'C:\Example', service: service)),
      );
      await tester.tap(find.text('内容校验'));
      await tester.pumpAndSettle();
      expect(service.group.files.every((file) => !file.selected), isTrue);
      await tester.tap(find.textContaining('2 个副本'));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.text('所选副本移到回收站'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(service.recycled, 0);
      await tester.tap(find.text('所选副本移到回收站'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(service.recycled, 1);
      expect(service.group.files.single.name, 'original.zip');
    },
  );

  testWidgets('new dialogs fit narrow windows', (tester) async {
    tester.view.physicalSize = const Size(560, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(RegistryBackupsDialog(backups: _Backups())));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final service = _Duplicates(state.whitelist);
    await tester.pumpWidget(
      app(DuplicateDialog(root: r'C:\Example', service: service)),
    );
    await tester.tap(find.text('内容校验'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('2 个副本'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  if (const bool.fromEnvironment('UI_PREVIEWS')) {
    testWidgets('export activity and duplicate dialogs', (tester) async {
      tester.view.physicalSize = const Size(1000, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final name in ['backups', 'duplicates']) {
        final key = GlobalKey();
        final dialog = name == 'backups'
            ? RegistryBackupsDialog(backups: _Backups())
            : DuplicateDialog(
                root: r'C:\Example',
                service: _Duplicates(state.whitelist),
              );
        await tester.pumpWidget(RepaintBoundary(key: key, child: app(dialog)));
        await tester.pumpAndSettle();
        if (name == 'duplicates') {
          await tester.tap(find.text('内容校验'));
          await tester.pumpAndSettle();
          await tester.tap(find.textContaining('2 个副本'));
          await tester.pumpAndSettle();
        }
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('.dart_tool/ui_previews/$name.png');
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}
