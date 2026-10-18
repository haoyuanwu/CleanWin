import 'dart:convert';
import 'dart:io';

import 'package:clean_windows/services/module_cache.dart';
import 'package:clean_windows/services/process_utils.dart';
import 'package:clean_windows/services/registry_audit_script.dart';
import 'package:clean_windows/services/registry_scan_service.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> registryRow({
  String view = 'Registry64',
  String? name = '',
  String category = 'appPaths',
  bool delete = true,
}) => {
  'Title': 'Missing application',
  'Detail': '目标未找到',
  'Hive': 'HKCU',
  'View': view,
  'KeyPath': r'Software\Microsoft\Windows\CurrentVersion\App Paths\app.exe',
  'ValueName': name,
  'Category': category,
  'Data': r'C:\Missing\app.exe',
  'ValueKind': 'String',
  'Target': r'C:\Missing\app.exe',
  'CanDelete': delete,
  'Severity': 'warn',
};

void main() {
  late Directory fixture;
  late ModuleCache cache;
  setUp(() {
    fixture = Directory('.dart_tool').createTempSync('registry_audit_');
    cache = ModuleCache(storageDirectory: fixture.path);
  });
  tearDown(() => fixture.deleteSync(recursive: true));

  String result(List<Map<String, dynamic>> rows) => jsonEncode({
    'Issues': rows,
    'Coverage': [
      {
        'Hive': 'HKCU',
        'View': 'Registry64',
        'Path': r'Software\Classes',
        'Status': 'partial',
        'Keys': 10,
        'Checked': 20,
        'Unverified': 3,
      },
    ],
    'Warnings': ['HKCU/Restricted'],
  });

  test('native and 32-bit issue identities stay separate and exact duplicates merge', () async {
    final service = RegistryScanService(
      cache: cache,
      powerShellRunner: (_, _) async => PsResult(
        exitCode: 0,
        stdout: result([
          registryRow(),
          registryRow(),
          registryRow(view: 'Registry32'),
        ]),
        stderr: '',
      ),
    );
    final issues = await service.scan(force: true);
    expect(issues, hasLength(2));
    expect(issues.map((issue) => issue.id).toSet(), hasLength(2));
    expect(issues.every((issue) => issue.canDelete), true);
    expect(service.coverage.single.checked, 20);
    expect(service.coverage.single.unverified, 3);
    expect(service.warnings, ['HKCU/Restricted']);
  });

  test('failed or malformed scans do not replace the valid cache', () async {
    var response = result([registryRow()]);
    final service = RegistryScanService(
      cache: cache,
      powerShellRunner: (_, _) async =>
          PsResult(exitCode: 0, stdout: response, stderr: ''),
    );
    await service.scan(force: true);
    response = '{}';
    await expectLater(service.scan(force: true), throwsFormatException);
    expect(await service.scan(), hasLength(1));
    expect(service.warnings, ['HKCU/Restricted']);
  });

  test(
    'new scans bypass the audit cache and return only actionable values',
    () async {
      cache.set(
        'registry_audit_v3',
        jsonDecode(result([registryRow(category: 'com')])),
      );
      var calls = 0;
      final service = RegistryScanService(
        cache: cache,
        powerShellRunner: (_, _) async {
          calls++;
          return PsResult(
            exitCode: 0,
            stdout: result([
              registryRow(),
              registryRow(delete: false),
              registryRow(category: 'com'),
              {
                ...registryRow(view: 'Registry32'),
                'Target': r'C:\Missing\library.dll',
              },
            ]),
            stderr: '',
          );
        },
      );
      expect(await service.scan(), hasLength(1));
      expect(calls, 1);
      expect(await service.scan(), hasLength(1));
      expect(calls, 1);
    },
  );

  test('default value cleanup never becomes recursive key deletion', () async {
    String captured = '';
    final service = RegistryScanService(
      cache: cache,
      powerShellRunner: (script, _) async {
        captured = script;
        return PsResult(exitCode: 0, stdout: '', stderr: '');
      },
    );
    expect(
      await service.deleteValue(RegistryIssue.fromJson(registryRow())),
      true,
    );
    final encoded = RegExp("FromBase64String\\('([^']+)'\\)")
        .firstMatch(captured)!
        .group(1)!;
    final snapshot = jsonDecode(utf8.decode(base64Decode(encoded))) as Map;
    expect(snapshot['ValueName'], '');
    expect(captured, contains('DeleteValue'));
    expect(captured, isNot(contains('Remove-Item')));
    expect(captured, isNot(contains('DeleteSubKey')));
    expect(
      captured.indexOf('Set-Content'),
      lessThan(captured.indexOf('DeleteValue')),
    );
    expect(captured, contains('registry_backups'));
    expect(captured, contains('GetValueKind'));
    expect(captured, contains('DoNotExpandEnvironmentNames'));
  });

  test('readonly categories, null value names and arbitrary keys cannot be deleted', () async {
    var calls = 0;
    final service = RegistryScanService(
      cache: cache,
      powerShellRunner: (_, _) async {
        calls++;
        return PsResult(exitCode: 0, stdout: '', stderr: '');
      },
    );
    for (final row in [
      registryRow(category: 'com'),
      registryRow(category: 'uninstall'),
      registryRow(name: null),
      {...registryRow(), 'KeyPath': r'SYSTEM\Critical'},
      {
        ...registryRow(),
        'KeyPath': r'HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\app.exe',
      },
      {
        ...registryRow(),
        'KeyPath': r'Software\Microsoft\Windows\CurrentVersion\App Paths\app.exe\child',
      },
      registryRow(delete: false),
    ]) {
      expect(await service.deleteValue(RegistryIssue.fromJson(row)), false);
    }
    expect(calls, 0);
  });

  test(
    'MUI cleanup requires the value name to match the missing executable',
    () {
      final row = {
        ...registryRow(),
        'Category': 'mui',
        'KeyPath': r'Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache',
        'ValueName': r'C:\Missing\app.exe.FriendlyAppName',
        'Data': "O'Brien app",
      };
      expect(RegistryIssue.fromJson(row).canDelete, true);
      expect(
        RegistryIssue.fromJson({...row, 'Target': r'C:\Other\different.exe'})
            .canDelete,
        false,
      );
      expect(RegistryIssue.fromJson({...row, 'Hive': 'HKLM'}).canDelete, false);
    },
  );

  test('scripts parse and command parser preserves paths with spaces', () async {
    if (!Platform.isWindows) return;
    String mutation = '';
    final service = RegistryScanService(
      cache: cache,
      powerShellRunner: (script, _) async {
        mutation = script;
        return PsResult(exitCode: 0, stdout: '', stderr: '');
      },
    );
    await service.deleteValue(RegistryIssue.fromJson(registryRow()));
    final deletion = mutation;
    await service.restoreValue(RegistryIssue.fromJson(registryRow()));
    final input = File('${fixture.path}/scripts.json').absolute
      ..writeAsStringSync(
        jsonEncode([registryAuditScript, deletion, mutation]),
      );
    final path = input.path.replaceAll("'", "''");
    final check =
        "\$scripts=Get-Content -LiteralPath '$path' -Raw -Encoding UTF8 | ConvertFrom-Json\n"
        r'''
foreach($script in $scripts) {
  $tokens=$null; $errors=$null
  [void][Management.Automation.Language.Parser]::ParseInput($script,[ref]$tokens,[ref]$errors)
  if($errors.Count){$errors | ForEach-Object {$_.Message};exit 1}
}
# Load only pure helpers, excluding the discovery loops. No registry writes.
$helpers=$scripts[0].Substring(0,$scripts[0].IndexOf('$specs = @('))
Invoke-Expression $helpers
$start=$scripts[0].IndexOf('$specs = @(')
$end=$scripts[0].IndexOf('$views = ',$start)
Invoke-Expression ($scripts[0].Substring($start,$end-$start))
if($specs.Count -ne 5){exit 9}
if(@($specs | Where-Object {$_.Kind -notin @('startup','mui','appPaths')}).Count){exit 10}
if(@($specs | Where-Object {$_.Kind -eq 'mui' -and !$_.UserOnly}).Count){exit 11}
if((Target '"C:\Program Files\App\app.exe" --background' 'command') -cne 'C:\Program Files\App\app.exe'){exit 2}
if((Target 'C:\Program Files\App\app.exe --background' 'command') -cne 'C:\Program Files\App\app.exe'){exit 3}
if((Target 'msiexec.exe /X {GUID}' 'command') -cne ''){exit 4}
if((Target 'C:\Library\app.dll\1' 'typelib') -cne 'C:\Library\app.dll'){exit 5}
function Get-Item {
  [CmdletBinding()]param([string]$LiteralPath,[switch]$Force)
  if($LiteralPath -match 'missing'){throw [Management.Automation.ItemNotFoundException]::new('missing')}
  if($LiteralPath -match 'protected'){throw [UnauthorizedAccessException]::new('denied')}
  return 'exists'
}
if((File-State 'C:\protected.exe') -ne 'unknown'){exit 6}
if((File-State 'C:\missing.exe') -ne 'missing'){exit 7}
if((File-State 'C:\present.exe') -ne 'exists'){exit 8}
exit 0
''';
    final response = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-EncodedCommand',
      base64Encode(
        check.codeUnits.expand((unit) => [unit & 255, unit >> 8]).toList(),
      ),
    ]);
    expect(
      response.exitCode,
      0,
      reason: '${response.stdout}\n${response.stderr}',
    );
  });
}
