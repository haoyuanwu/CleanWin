import 'dart:convert';
import 'dart:io';

import 'package:clean_windows/services/module_cache.dart';
import 'package:clean_windows/services/process_utils.dart';
import 'package:clean_windows/services/startup_scan_script.dart';
import 'package:clean_windows/services/startup_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory fixture;
  late ModuleCache cache;
  setUp(() {
    fixture = Directory('.dart_tool').createTempSync('startup_test_');
    cache = ModuleCache(storageDirectory: fixture.path);
  });
  tearDown(() => fixture.deleteSync(recursive: true));

  Map<String, dynamic> row({
    String key = 'Run',
    String view = 'Registry64',
    String name = 'Same app',
    bool disabled = false,
  }) => {
    'Name': name,
    'Command': r'C:\App\app.exe',
    'Location': 'Registry',
    'Group': 'registry',
    'Enabled': !disabled,
    'Disabled': disabled,
    'CanToggle': true,
    'StateKnown': true,
    'Hive': 'CurrentUser',
    'View': view,
    'Key': 'Software\\Microsoft\\Windows\\CurrentVersion\\$key',
    'ValueName': name,
  };
  PsResult output(
    List<Map<String, dynamic>> items, {
    List<String> warnings = const [],
  }) => PsResult(
    exitCode: 0,
    stdout: jsonEncode({'Items': items, 'Warnings': warnings}),
    stderr: '',
  );

  test(
    'same names in different keys and registry views remain distinct',
    () async {
      final first = row();
      final service = StartupService(
        cache: cache,
        powerShellRunner: (_, _) async => output([
          first,
          first,
          row(key: 'RunOnce'),
          row(view: 'Registry32'),
          row(disabled: true),
          {
            'Name': 'Same app',
            'Location': 'ScheduledTask',
            'Group': 'task',
            'SourceFile': r'\Folder\Task',
            'Enabled': true,
          },
        ]),
      );
      final items = await service.list(force: true);
      expect(items, hasLength(5));
      expect(items.map((item) => item.id).toSet(), hasLength(5));
    },
  );

  test(
    'partial sources are preserved with warnings and versioned cache',
    () async {
      var calls = 0;
      final service = StartupService(
        cache: cache,
        powerShellRunner: (_, _) async {
          calls++;
          return output([row()], warnings: ['Tasks/Restricted']);
        },
      );
      expect(await service.list(force: true), hasLength(1));
      expect(service.warnings, ['Tasks/Restricted']);
      expect(await service.list(), hasLength(1));
      expect(calls, 1);
    },
  );

  test('failed refresh does not overwrite the last valid cache', () async {
    var fail = false;
    final service = StartupService(
      cache: cache,
      powerShellRunner: (_, _) async => fail
          ? PsResult(exitCode: 1, stdout: '', stderr: 'denied')
          : output([row()]),
    );
    await service.list(force: true);
    fail = true;
    await expectLater(service.list(force: true), throwsException);
    expect(await service.list(), hasLength(1));
  });

  test(
    'invalid output is an error rather than an empty successful scan',
    () async {
      final service = StartupService(
        cache: cache,
        powerShellRunner: (_, _) async =>
            PsResult(exitCode: 0, stdout: 'invalid', stderr: ''),
      );
      await expectLater(service.list(force: true), throwsFormatException);
    },
  );

  test(
    'read-only sources and invalid registry targets never launch mutations',
    () async {
      var calls = 0;
      final service = StartupService(
        cache: cache,
        powerShellRunner: (_, _) async {
          calls++;
          return output([]);
        },
      );
      final readOnly = StartupItem.fromJson({
        ...row(),
        'Group': 'task',
        'Location': 'ScheduledTask',
        'CanToggle': false,
      });
      expect(await service.setEnabled(readOnly, false), false);
      expect(await service.removeFile(readOnly), false);
      expect(
        await service.setEnabled(
          StartupItem.fromJson({...row(), 'Key': r'SYSTEM\Critical'}),
          false,
        ),
        false,
      );
      expect(calls, 0);
    },
  );

  test(
    'toggle uses exact RunOnce identity and safely encodes special names',
    () async {
      String? script;
      final service = StartupService(
        cache: cache,
        powerShellRunner: (value, _) async {
          script = value;
          return PsResult(exitCode: 0, stdout: '', stderr: '');
        },
      );
      final item = StartupItem.fromJson(
        row(key: 'RunOnce', name: "O'Brien \$()"),
      );
      expect(await service.setEnabled(item, false), true);
      expect(script, isNot(contains(item.name)));
      final encoded = RegExp("FromBase64String\\('([^']+)'\\)")
          .firstMatch(script!)!
          .group(1)!;
      final data = jsonDecode(utf8.decode(base64Decode(encoded))) as Map;
      expect(data['Key'], endsWith(r'\RunOnce'));
      expect(data['ValueName'], item.name);
      expect(script, contains('CleanWinDisabled'));
      expect(script, contains('DoNotExpandEnvironmentNames'));
      expect(
        script!.indexOf('SetValue'),
        lessThan(script!.indexOf('DeleteValue')),
      );
    },
  );

  test('discovery and mutation scripts parse without executing changes', () async {
    if (!Platform.isWindows) return;
    String mutation = '';
    final service = StartupService(
      cache: cache,
      powerShellRunner: (value, _) async {
        mutation = value;
        return PsResult(exitCode: 0, stdout: '', stderr: '');
      },
    );
    await service.setEnabled(StartupItem.fromJson(row()), false);
    final input = File('${fixture.path}/scripts.json').absolute;
    input.writeAsStringSync(jsonEncode([startupScanScript, mutation]));
    final inputPath = input.path.replaceAll("'", "''");
    final check =
        "\$scripts = Get-Content -LiteralPath '$inputPath' -Encoding UTF8 -Raw | ConvertFrom-Json\n"
        r'''
foreach ($script in $scripts) {
  $tokens = $null; $errors = $null
  [void][Management.Automation.Language.Parser]::ParseInput($script,[ref]$tokens,[ref]$errors)
  if ($errors.Count) { $errors | ForEach-Object {$_.Message}; exit 1 }
}
exit 0
''';
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-EncodedCommand',
      base64Encode(
        check.codeUnits.expand((unit) => [unit & 255, unit >> 8]).toList(),
      ),
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
}
