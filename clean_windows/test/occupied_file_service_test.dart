import 'dart:io';

import 'package:clean_windows/services/occupied_file_service.dart';
import 'package:clean_windows/theme/app_theme.dart';
import 'package:clean_windows/widgets/clean_progress_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('occupied app prompt never offers unsafe process shutdown', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<Set<int>>(
              context: context,
              builder: (_) => const OccupiedAppsDialog(
                applications: [
                  OccupiedApplication(
                    pid: 4,
                    name: 'System',
                    restartable: false,
                    safeToClose: false,
                  ),
                ],
                fileCount: 2,
                forCleanup: true,
                canCloseAndRestore: false,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('System'), findsOneWidget);
    expect(find.text('关闭并清理'), findsNothing);
    expect(find.text('不关闭，跳过占用文件'), findsOneWidget);
  });

  testWidgets('occupied app list supports selected and all safe applications', (
    tester,
  ) async {
    Set<int>? result;
    const apps = [
      OccupiedApplication(
        pid: 101,
        name: 'Editor',
        restartable: true,
        safeToClose: true,
      ),
      OccupiedApplication(
        pid: 202,
        name: 'Browser',
        restartable: true,
        safeToClose: true,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<Set<int>>(
                context: context,
                builder: (_) => const OccupiedAppsDialog(
                  applications: apps,
                  fileCount: 3,
                  forCleanup: false,
                  canCloseAndRestore: true,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Editor'), findsOneWidget);
    expect(find.text('Browser'), findsOneWidget);
    expect(find.text('一键全部关闭'), findsOneWidget);
    await tester.tap(find.text('Editor'));
    await tester.pump();
    await tester.tap(find.text('关闭所选并重扫'));
    await tester.pumpAndSettle();
    expect(result, {101});

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('一键全部关闭'));
    await tester.pumpAndSettle();
    expect(result, {101, 202});
  });

  test(
    'Restart Manager inspection recognizes a file locked by this process',
    () async {
      final fixture = Directory.systemTemp.createTempSync(
        'cleanwin-occupied-test-',
      );
      final file = File('${fixture.path}\\busy.cache')
        ..writeAsStringSync('busy');
      final lock = file.openSync(mode: FileMode.write);
      try {
        final session = await const WindowsOccupiedFileCoordinator().open([
          file.path,
        ]);
        expect(session, isNotNull);
        expect(session!.fileCount, 1);
        expect(session.applications, isNotEmpty);
        expect(session.canCloseAndRestore, isFalse);
        await session.dispose();
      } finally {
        lock.closeSync();
        fixture.deleteSync(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );
}
