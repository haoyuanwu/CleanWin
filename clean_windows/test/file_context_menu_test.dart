import 'dart:io';

import 'package:clean_windows/services/file_actions.dart';
import 'package:clean_windows/services/process_utils.dart';
import 'package:clean_windows/widgets/file_actions_button.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'startup path extraction never treats a full command as a file path',
    () {
      expect(
        FileActions.executablePath(r'"C:\Program Files\App\app.exe" --silent'),
        r'C:\Program Files\App\app.exe',
      );
      expect(
        FileActions.executablePath(r'C:\Program Files\App\app.exe --silent'),
        r'C:\Program Files\App\app.exe',
      );
      expect(
        FileActions.executablePath(r'C:\App\icon.exe,0'),
        r'C:\App\icon.exe',
      );
      expect(FileActions.executablePath('app.exe --silent'), isNull);
      expect(FileActions.executablePath('https://example.com/app.exe'), isNull);
      expect(
        FileActions.executablePath('powershell -Command something'),
        isNull,
      );
    },
  );

  test('Explorer selects files, opens directories, and falls back to an existing parent', () async {
    final fixture = Directory.systemTemp.createTempSync('file_menu_').absolute;
    try {
      final file = File(p.join(fixture.path, 'setup.exe'))
        ..writeAsStringSync('fixture');
      expect(await FileActions.explorerArguments(file.path), [
        '/select,',
        file.path,
      ]);
      expect(await FileActions.explorerArguments(fixture.path), [fixture.path]);
      expect(
        await FileActions.explorerArguments(p.join(fixture.path, 'gone.exe')),
        [fixture.path],
      );
      await expectLater(
        FileActions.explorerArguments('HKCU\\Software\\App'),
        throwsA(isA<FileSystemException>()),
      );
    } finally {
      expect(
        p.isWithin(Directory.systemTemp.absolute.path, fixture.path),
        true,
      );
      fixture.deleteSync(recursive: true);
    }
  });

  testWidgets(
    'row right click exposes read-only navigation and module actions',
    (tester) async {
      var leftClicks = 0, selections = 0;
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String?;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileActionsButton.contextMenu(
              path: r'C:\Files\setup.exe',
              allowMove: false,
              actions: [
                FileMenuAction(
                  '勾选此项',
                  icon: Icons.check_box_outlined,
                  onSelected: () {
                    selections++;
                  },
                ),
                const FileMenuAction(
                  '删除所选',
                  icon: Icons.delete_outline_rounded,
                  onSelected: null,
                ),
              ],
              child: ListTile(
                title: const Text('fixture file'),
                onTap: () {
                  leftClicks++;
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(
        find.text('fixture file'),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(leftClicks, 0);
      expect(find.text('打开所在位置'), findsOneWidget);
      expect(find.text('复制路径'), findsOneWidget);
      expect(find.text('移动到其他目录'), findsNothing);
      final disabled = find.ancestor(
        of: find.text('删除所选'),
        matching: find.byType(PopupMenuItem<String>),
      );
      expect(tester.widget<PopupMenuItem<String>>(disabled).enabled, false);
      await tester.tap(find.text('复制路径'));
      await tester.pumpAndSettle();
      expect(copied, r'C:\Files\setup.exe');
      await tester.tap(
        find.text('fixture file'),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('勾选此项'));
      await tester.pumpAndSettle();
      expect(selections, 1);
      expect(leftClicks, 0);
      await tester.tap(find.text('fixture file'));
      expect(leftClicks, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'busy rows have no context menu and unknown paths have no navigation',
    (tester) async {
      ProcessUtils.debugSkip = true;
      addTearDown(() => ProcessUtils.debugSkip = false);
      Widget page(bool enabled) => MaterialApp(
        home: Scaffold(
          body: FileActionsButton.contextMenu(
            path: '',
            enabled: enabled,
            allowMove: false,
            actions: [
              FileMenuAction(
                '查看详情',
                icon: Icons.info_outline,
                onSelected: () {},
              ),
            ],
            child: const ListTile(title: Text('unknown location')),
          ),
        ),
      );
      await tester.pumpWidget(page(false));
      await tester.tap(
        find.text('unknown location'),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('查看详情'), findsNothing);
      await tester.pumpWidget(page(true));
      await tester.tap(
        find.text('unknown location'),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('查看详情'), findsOneWidget);
      expect(find.text('打开所在位置'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
