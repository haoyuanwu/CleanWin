import 'package:clean_windows/theme/app_theme.dart';
import 'package:clean_windows/theme/module_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'module colors cover button states without changing action semantics',
    (tester) async {
      final schemes = <Color>{};
      for (var index = 2; index <= 10; index++) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light().copyWith(platform: TargetPlatform.windows),
            home: ModuleSurface(
              index: index,
              child: Builder(
                builder: (context) {
                  final theme = Theme.of(context);
                  final color = ModulePalette.forIndex(index).accent;
                  schemes.add(theme.colorScheme.primary);
                  final style = theme.elevatedButtonTheme.style!;
                  expect(style.backgroundColor!.resolve({}), color);
                  expect(
                    style.elevation!.resolve({WidgetState.hovered}),
                    greaterThan(style.elevation!.resolve({})!),
                  );
                  expect(
                    style.elevation!.resolve({
                      WidgetState.hovered,
                      WidgetState.disabled,
                    }),
                    0,
                  );
                  expect(
                    style.backgroundColor!.resolve({WidgetState.disabled}),
                    isNot(color),
                  );
                  expect(
                    theme.outlinedButtonTheme.style!.foregroundColor!.resolve(
                      {},
                    ),
                    color,
                  );
                  return Center(
                    child: ElevatedButton(
                      onPressed: null,
                      child: const Text('执行'),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
          isNull,
        );
      }
      expect(schemes.length, 9);
    },
  );

  testWidgets('desktop lists and menus retain scrolling without scrollbars', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light().copyWith(platform: TargetPlatform.windows),
        scrollBehavior: const CleanScrollBehavior(),
        home: Scaffold(
          body: ListView.builder(
            itemExtent: 48,
            itemCount: 100,
            itemBuilder: (_, index) => Text('第 $index 项'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Scrollbar), findsNothing);
    expect(find.text('第 0 项').hitTestable(), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('第 0 项').hitTestable(), findsNothing);
    expect(find.byType(Scrollbar), findsNothing);
  });

  testWidgets('reduced motion disables decorative button transitions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: ModuleSurface(
            index: 4,
            child: Builder(
              builder: (context) {
                expect(
                  Theme.of(context)
                      .elevatedButtonTheme
                      .style!
                      .animationDuration,
                  Duration.zero,
                );
                expect(
                  Theme.of(context).iconButtonTheme.style!.animationDuration,
                  Duration.zero,
                );
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
  });
}
