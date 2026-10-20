import 'dart:convert';
import 'dart:io';

import 'package:clean_windows/models/clean_models.dart';
import 'package:clean_windows/services/download_discovery.dart';
import 'package:clean_windows/services/clean_service.dart';
import 'package:clean_windows/services/process_utils.dart';
import 'package:clean_windows/services/scan_service.dart';
import 'package:clean_windows/services/whitelist_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory fixture;
  late Map<String, String> env;
  late String volume;
  late WhitelistService whitelist;
  const sid = 'S-1-5-21-100';
  File put(String relative, {int bytes = 5}) {
    final file = File(p.joinAll([fixture.path, ...relative.split('/')]));
    file.parent.createSync(recursive: true);
    final handle = file.openSync(mode: FileMode.write);
    handle.truncateSync(bytes);
    handle.closeSync();
    return file;
  }

  setUp(() {
    fixture = Directory.systemTemp.createTempSync('download_scan_').absolute;
    volume = p.join(fixture.path, 'Volume');
    env = {
      'USERPROFILE': p.join(fixture.path, 'User'),
      'DOWNLOADS': p.join(fixture.path, 'MovedDownloads'),
      'LOCALAPPDATA': p.join(fixture.path, 'User', 'AppData', 'Local'),
      'APPDATA': p.join(fixture.path, 'User', 'AppData', 'Roaming'),
      'SystemRoot': p.join(fixture.path, 'Windows'),
      'ProgramFiles': p.join(fixture.path, 'Program Files'),
      'ProgramData': p.join(fixture.path, 'ProgramData'),
      'USER_SID': sid,
    };
    whitelist = WhitelistService(
      storageDirectory: p.join(fixture.path, 'Protection'),
    );
  });
  tearDown(() {
    expect(
      p.isWithin(Directory.systemTemp.absolute.path, fixture.path),
      isTrue,
    );
    fixture.deleteSync(recursive: true);
  });
  ScanService service({List<Map<String, String>> configured = const []}) =>
      ScanService(
        environment: env,
        driveRoots: [volume],
        operabilityProbe: (paths) async => paths.toSet(),
        powerShellRunner: (script, _) async => PsResult(
          exitCode: 0,
          stdout: script == downloadSettingsScript
              ? jsonEncode(configured)
              : '',
          stderr: '',
        ),
      )..whitelist = whitelist;

  test('one-click includes current-user recycle and system and manager downloads without auto-selection', () async {
    final system = put('MovedDownloads/video.mp4', bytes: 10 * 1024 * 1024);
    final tencent = put('Volume/QMDownload/SoftMgr/setup.exe');
    final antivirus = put('Volume/360Downloads/Software/version/setup.msi');
    final recycle = put('Volume/\$Recycle.Bin/$sid/\$Rpackage.exe');
    put('Volume/\$Recycle.Bin/S-1-5-21-200/\$Rother.exe');
    put('Volume/QMDownload/Hotfix/repair.exe');
    put('Volume/QMDownload/SoftMgr/settings.db');
    put('Volume/QMDownload/SoftMgr/setup.exe.download');
    final result = await service().scanAll();
    expect(result.keys.toSet(), oneClickScanCategories);
    final files = result[CleanCategory.downloads]!.items
        .expand((item) => item.scannedFiles!)
        .toList();
    expect(files, unorderedEquals([system.path, tencent.path, antivirus.path]));
    expect(
      result[CleanCategory.downloads]!.items.every((item) => !item.selected),
      isTrue,
    );
    expect(
      result[CleanCategory.recycleBin]!.items.expand(
        (item) => item.scannedFiles!,
      ),
      [recycle.path],
    );
    expect(result[CleanCategory.recycleBin]!.selectedCount, 0);
  });

  test('configured download folders deduplicate snapshots and honor whitelist and protection', () async {
    final allowed = put('CustomPackages/small.zip');
    final protected = put('CustomPackages/protected/setup.exe');
    put('CustomPackages/settings.ini');
    await whitelist.add(protected.parent.path);
    final scanner = service(
      configured: [
        {'Path': allowed.parent.path, 'Source': '腾讯电脑管家'},
        {'Path': allowed.parent.path.toUpperCase(), 'Source': '腾讯电脑管家'},
        {'Path': env['USERPROFILE']!, 'Source': '360 软件管家'},
        {'Path': p.rootPrefix(fixture.path), 'Source': '360 软件管家'},
        {
          'Path': p.join(env['ProgramFiles']!, 'Installed'),
          'Source': '360 软件管家',
        },
      ],
    );
    final result = await scanner.scanAll(categories: {CleanCategory.downloads});
    final items = result[CleanCategory.downloads]!.items;
    expect(items, hasLength(1));
    expect(items.single.scannedFiles, [allowed.path]);
    expect(items.single.appName, '腾讯电脑管家');
    expect(items.single.selected, isFalse);
    expect(protected.existsSync(), isTrue);
  });

  test('recycled download snapshots disappear on rescan while unrelated files remain', () async {
    final system = put(
      'MovedDownloads/folder/video.mp4',
      bytes: 12 * 1024 * 1024,
    );
    final package = put('Volume/QMDownload/SoftMgr/setup.exe');
    final settings = put('Volume/QMDownload/SoftMgr/settings.ini');
    final scanner = service();
    final before = await scanner.scanAll(categories: {CleanCategory.downloads});
    final items = before[CleanCategory.downloads]!.items;
    for (final item in items) {
      item.selected = true;
    }
    var sequence = 0;
    final recycleFolder = Directory(p.join(fixture.path, 'Recycled'))
      ..createSync();
    final recycler = CleanService(
      recycler: (path) async {
        await File(path)
            .rename(p.join(recycleFolder.path, '${sequence++}.bin'));
        return true;
      },
    )..whitelist = whitelist;
    final report = await recycler.cleanItems(items, recycle: true);
    expect(report.deletedCount, 2);
    expect(report.freedBytes, 0);
    expect(report.recycledBytes, 12 * 1024 * 1024 + 5);
    expect(system.existsSync(), false);
    expect(package.existsSync(), false);
    expect(settings.existsSync(), true);
    final after = await scanner.scanAll(categories: {CleanCategory.downloads});
    expect(after[CleanCategory.downloads]!.items, isEmpty);
    // A new download at the same path is a real new candidate, never hidden.
    put('MovedDownloads/folder/video.mp4', bytes: 11 * 1024 * 1024);
    final fresh = await scanner.scanAll(categories: {CleanCategory.downloads});
    expect(fresh[CleanCategory.downloads]!.items.single.selected, false);
  });

  test('download settings script parses without executing registry operations', () async {
    if (!Platform.isWindows) return;
    final file = put('download-settings.ps1')
      ..writeAsStringSync(downloadSettingsScript);
    final escaped = file.path.replaceAll("'", "''");
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "\$tokens=\$null;\$errors=\$null;[void][Management.Automation.Language.Parser]::ParseFile('$escaped',[ref]\$tokens,[ref]\$errors);if(\$errors.Count){\$errors|ForEach-Object{\$_.Message};exit 1}",
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
}
