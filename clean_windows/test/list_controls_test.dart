import 'package:clean_windows/theme/app_theme.dart';
import 'package:clean_windows/theme/module_theme.dart';
import 'package:clean_windows/widgets/page_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    scrollBehavior: const CleanScrollBehavior(),
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(24), child: child),
    ),
  );

  testWidgets('search focuses, clears, and restores the full list on Escape', (
    tester,
  ) async {
    var query = '';
    await tester.pumpWidget(
      app(
        ListToolbar(
          title: '文件',
          actions: [
            ModuleSearchField(
              hint: '搜索文件',
              onChanged: (value) => query = value,
            ),
          ],
        ),
      ),
    );
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byTooltip('搜索'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasFocus, isTrue);
    await tester.enterText(find.byType(TextField), 'cache');
    expect(query, 'cache');
    await tester.pump();
    await tester.tap(find.byTooltip('清空搜索'));
    await tester.pump();
    expect(query, '');
    expect(field.focusNode!.hasFocus, isTrue);
    await tester.enterText(find.byType(TextField), 'temp');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(query, '');
    expect(find.byType(TextField), findsNothing);
    expect(find.byTooltip('搜索'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded search and filters fit a narrow toolbar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(
        ListToolbar(
          title: '扫描结果',
          actions: [
            ModuleSearchField(hint: '搜索', onChanged: (_) {}),
            ModuleSelect<int>(
              value: 0,
              items: const [ModuleSelectItem(value: 0, child: Text('全部类别'))],
              onChanged: (_) {},
            ),
            FilterChip(
              label: const Text('只看有结果'),
              selected: false,
              onSelected: (_) {},
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.byTooltip('搜索'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '内容');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('收起搜索'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets(
    'selector scrolls, selects, dismisses, and respects disabled state',
    (tester) async {
      var selected = 0;
      var enabled = true;
      late StateSetter update;
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Align(
                alignment: Alignment.topLeft,
                child: ModuleSelect<int>(
                  label: '选择类别',
                  value: selected,
                  items: [
                    for (var i = 0; i < 20; i++)
                      ModuleSelectItem(value: i, child: Text('类别 $i')),
                  ],
                  onChanged: enabled
                      ? (value) => setState(() => selected = value!)
                      : null,
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.byTooltip('选择类别'));
      await tester.pumpAndSettle();
      final firstEntry = find.byType(PopupMenuItem<int>).first;
      expect(
        Theme.of(tester.element(firstEntry)).highlightColor,
        Colors.transparent,
      );
      expect(find.byType(Scrollbar), findsWidgets);
      await tester.ensureVisible(find.text('类别 19').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('类别 19').last);
      await tester.pumpAndSettle();
      expect(selected, 19);
      expect(find.byType(PopupMenuItem<int>), findsNothing);
      await tester.tap(find.byTooltip('选择类别'));
      await tester.pumpAndSettle();
      expect(find.text('类别 19').last.hitTestable(), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(selected, 19);
      expect(find.byType(PopupMenuItem<int>), findsNothing);
      update(() => enabled = false);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ModuleSelect<int>));
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<int>), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
