import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:clean_windows/pages/health_check_page.dart';
import 'package:clean_windows/services/health_check_service.dart';
import 'package:clean_windows/services/process_utils.dart';
import 'package:clean_windows/theme/app_theme.dart';
import 'package:clean_windows/theme/module_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'health_check_test.dart' show data;

void main() {
  const render = bool.fromEnvironment('UI_PREVIEWS');
  setUpAll(() async {
    if (!render) return;
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
  for (final width in [1000.0, 560.0]) {
    testWidgets('health previews at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var calls = 0;
      Completer<PsResult>? pending;
      var fail = false;
      final c = HealthCheckController(
        service: HealthCheckService(
          runner: (script, timeout) async {
            if (pending != null) return pending.future;
            if (fail) {
              return PsResult(exitCode: 1, stdout: '', stderr: 'denied');
            }
            return data(calls++);
          },
        ),
      );
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          scrollBehavior: const CleanScrollBehavior(),
          home: Scaffold(
            body: RepaintBoundary(
              key: key,
              child: ModuleSurface(
                index: 11,
                child: HealthCheckPage(
                  controller: c,
                  onNavigate: (_) {},
                  onScanTraces: () async => true,
                ),
              ),
            ),
          ),
        ),
      );
      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final output = File(
            '.dart_tool/health_previews/health-${width.toInt()}-$name.png',
          );
          output.parent.createSync(recursive: true);
          output.writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('empty');
      await c.scan();
      await tester.pumpAndSettle();
      await capture('results');
      await tester.tap(find.text('网络诊断'));
      await capture('network');
      await tester.tap(find.text('网络诊断'));
      await tester.pumpAndSettle();
      pending = Completer();
      final scanning = c.scan();
      await capture('scanning');
      c.cancel();
      pending.complete(data(0));
      await scanning;
      pending = null;
      await capture('cancelled');
      fail = true;
      await c.scan();
      await capture('unavailable');
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }, skip: !render);
  }
}
