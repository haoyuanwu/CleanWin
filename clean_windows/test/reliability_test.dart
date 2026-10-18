import 'dart:convert';
import 'dart:io';

import 'package:clean_windows/models/clean_models.dart';
import 'package:clean_windows/models/installed_app.dart';
import 'package:clean_windows/services/clean_service.dart';
import 'package:clean_windows/services/disk_services.dart';
import 'package:clean_windows/services/module_cache.dart';
import 'package:clean_windows/services/process_utils.dart';
import 'package:clean_windows/services/uninstall_service.dart';
import 'package:clean_windows/services/whitelist_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory fixture;
  setUp(
    () =>
        fixture = Directory('.dart_tool')
            .createTempSync('reliability_')
            .absolute,
  );
  tearDown(() {
    expect(
      p.isWithin(Directory('.dart_tool').absolute.path, fixture.path),
      isTrue,
    );
    fixture.deleteSync(recursive: true);
  });
  test(
    'whitelist failed writes retain the durable protection and visible error',
    () async {
      var fail = false;
      final service = WhitelistService(
        storageDirectory: fixture.path,
        writeSnapshot: (file, data) {
          if (fail) throw const FileSystemException('denied');
          file.writeAsStringSync(data, flush: true);
        },
      );
      await service.add(r'C:\Protected');
      fail = true;
      await expectLater(service.clear(), throwsA(isA<FileSystemException>()));
      expect(service.isWhitelisted(r'C:\Protected\data'), isTrue);
      expect(service.lastError, isNotNull);
      expect(WhitelistService(storageDirectory: fixture.path).length, 1);
    },
  );
  test('unreadable whitelist blocks cleanup without modifying files', () async {
    File(p.join(fixture.path, 'whitelist.json')).writeAsStringSync('{broken');
    final whitelist = WhitelistService(storageDirectory: fixture.path);
    expect(whitelist.readable, isFalse);
    final file = File(p.join(fixture.path, 'keep.tmp'))
      ..writeAsStringSync('keep');
    final cleaner = CleanService()..whitelist = whitelist;
    await expectLater(
      cleaner.cleanItems([
        CleanItem(
          id: file.path,
          name: 'keep',
          path: file.path,
          sizeBytes: 4,
          category: CleanCategory.downloads,
          scannedFiles: [file.path],
        ),
      ]),
      throwsStateError,
    );
    expect(file.readAsStringSync(), 'keep');
  });
  test(
    'reviewed personal files use recycler and reject changes and whitelist',
    () async {
      final file = File(p.join(fixture.path, 'personal.bin'))
        ..writeAsStringSync('keep');
      final snapshot = FileEntry(
        path: file.path,
        name: 'personal.bin',
        sizeBytes: 4,
        modified: file.statSync().modified,
      );
      var calls = 0;
      final cleaner = CleanService(
        recycler: (path) async {
          calls++;
          await File(path).rename(p.join(fixture.path, 'recycled.bin'));
          return true;
        },
      );
      final service = LargeFileService(cleaner: cleaner)
        ..whitelist = WhitelistService(storageDirectory: fixture.path);
      await service.whitelist!.add(file.path);
      expect(
        (await service.deleteReviewedFiles([snapshot])).completedItemIds,
        isEmpty,
      );
      await service.whitelist!.remove(file.path);
      file.writeAsStringSync('changed');
      expect(
        (await service.deleteReviewedFiles([snapshot])).completedItemIds,
        isEmpty,
      );
      expect(calls, 0);
      final current = FileEntry(
        path: file.path,
        name: 'personal.bin',
        sizeBytes: 7,
        modified: file.statSync().modified,
      );
      final report = await service.deleteReviewedFiles([current]);
      expect(report.freedBytes, 0);
      expect(report.recycledBytes, 7);
      expect(report.completedItemIds, {file.path});
    },
  );
  test('failed recycling never falls back to permanent deletion', () async {
    final file = File(p.join(fixture.path, 'keep.bin'))
      ..writeAsStringSync('keep');
    final result = await CleanService(recycler: (_) async => false).cleanItems([
      CleanItem(
        id: 'keep',
        name: 'keep',
        path: file.path,
        sizeBytes: 4,
        category: CleanCategory.downloads,
        scannedFiles: [file.path],
      ),
    ], recycle: true);
    expect(result.completedItemIds, isEmpty);
    expect(file.readAsStringSync(), 'keep');
  });
  test('uninstall keeps same-name identities and checks exit code and registration', () async {
    var response = jsonEncode({'Code': 0, 'Present': true});
    final scripts = <String>[];
    final service = UninstallService(
      cache: ModuleCache(storageDirectory: fixture.path),
      runner: (script, _) async {
        scripts.add(script);
        return PsResult(
          exitCode: 0,
          stdout: script.contains('Get-ItemProperty')
              ? jsonEncode([
                  {
                    'DisplayName': 'Same',
                    'RegistryKey': 'key1',
                    'UninstallString': 'app.exe',
                  },
                  {
                    'DisplayName': 'Same',
                    'RegistryKey': 'key2',
                    'UninstallString': 'app.exe',
                  },
                ])
              : response,
          stderr: '',
        );
      },
    );
    final apps = await service.listInstalled(force: true);
    expect(apps, hasLength(2));
    final app = InstalledApp(
      displayName: 'Example',
      registryKey: 'key1',
      uninstallString: '"C:\\App\\uninstall.exe" /remove',
    );
    expect((await service.uninstall(app)).success, isFalse);
    response = jsonEncode({'Code': 1602, 'Present': true});
    expect((await service.uninstall(app)).status, UninstallStatus.cancelled);
    response = jsonEncode({'Code': 3010, 'Present': false});
    final result = await service.uninstall(app);
    expect(result.success, isTrue);
    expect(result.status, UninstallStatus.restartRequired);
    expect(scripts.last, contains('-PassThru -Wait'));
    if (Platform.isWindows) {
      final input = File(p.join(fixture.path, 'uninstall-scripts.json'))
        ..writeAsStringSync(jsonEncode(scripts));
      final scriptPath = input.path.replaceAll("'", "''");
      final check =
          "\$scripts=Get-Content -LiteralPath '$scriptPath' -Raw -Encoding UTF8 | ConvertFrom-Json\n" r'''
foreach($script in $scripts) {
  $tokens=$null; $errors=$null
  [void][Management.Automation.Language.Parser]::ParseInput($script,[ref]$tokens,[ref]$errors)
  if($errors.Count){$errors | ForEach-Object {$_.Message};exit 1}
}
''';
      final parsed = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        check,
      ]);
      expect(parsed.exitCode, 0, reason: '${parsed.stdout}\n${parsed.stderr}');
    }
  });
}
