import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'state/app_state.dart';

void main(List<String> arguments) {
  final adminScan = arguments.any(
    (value) => value.startsWith('--cleanwin-admin-scan='),
  );
  // 保证 binding 与 runApp 在同一 Zone，避免 Zone mismatch
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        _logError('FlutterError', details.exceptionAsString(), details.stack);
      };

      runApp(
        ChangeNotifierProvider(
          create: (_) => AppState(scanOnStart: adminScan),
          child: CleanWindowsApp(initialIndex: adminScan ? 1 : 0),
        ),
      );
    },
    (error, stack) {
      _logError('ZoneError', error.toString(), stack);
    },
  );
}

void _logError(String type, String message, StackTrace? stack) {
  try {
    final local =
        Platform.environment['LOCALAPPDATA'] ??
        '${Platform.environment['USERPROFILE']}\\AppData\\Local';
    final dir = Directory('$local\\CleanWin');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File('${dir.path}\\error.log');
    final ts = DateTime.now().toIso8601String();
    file.writeAsStringSync(
      '[$ts] $type: $message\n${stack ?? ''}\n\n',
      mode: FileMode.append,
    );
  } on Exception catch (_) {}
}
