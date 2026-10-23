import 'dart:convert';
import 'dart:io';

import 'package:clean_windows/models/clean_models.dart';
import 'package:clean_windows/models/scan_options.dart';
import 'package:clean_windows/services/clean_service.dart';
import 'package:clean_windows/services/module_cache.dart';
import 'package:clean_windows/services/process_utils.dart';
import 'package:clean_windows/services/registry_cache.dart';
import 'package:clean_windows/services/scan_service.dart';
import 'package:clean_windows/services/whitelist_service.dart';
import 'package:clean_windows/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory fixture;
  late Map<String, String> env;
  late WhitelistService whitelist;
  late ScanService scan;
  const sid = 'S-1-5-21-100';
  File put(String path, {int bytes = 7, int age = 10}) {
    final file = File(path)..parent.createSync(recursive: true);
    file.writeAsBytesSync(List.filled(bytes, 1));
    file.setLastModifiedSync(DateTime.now().subtract(Duration(days: age)));
    return file;
  }

  Future<PsResult> runner(String script, Duration timeout) async => PsResult(
    exitCode: 0,
    stdout: script == RegistryCache.scanScript ? '[]' : '',
    stderr: '',
  );
  Future<List<CleanItem>> items(CleanCategory category) async {
    final result = (await scan.scanAll(categories: {category}))[category]!;
    expect(result.error, isNull);
    return result.items;
  }

  setUp(() {
    fixture = Directory.systemTemp.createTempSync('audit_test_').absolute;
    env = {
      'USERPROFILE': fixture.path,
      'LOCALAPPDATA': p.join(fixture.path, 'AppData', 'Local'),
      'APPDATA': p.join(fixture.path, 'AppData', 'Roaming'),
      'ProgramData': p.join(fixture.path, 'ProgramData'),
      'SystemRoot': p.join(fixture.path, 'Windows'),
      'SystemDrive': fixture.path,
      'ProgramFiles': p.join(fixture.path, 'Program Files'),
      'ProgramFiles(x86)': p.join(fixture.path, 'Program Files (x86)'),
      'DOWNLOADS': p.join(fixture.path, 'MovedDownloads'),
      'TEMP': p.join(fixture.path, 'Temp'),
      'TMP': p.join(fixture.path, 'Temp'),
      'USER_SID': sid,
    };
    whitelist = WhitelistService(
      storageDirectory: p.join(fixture.path, 'settings'),
    );
    scan = ScanService(
      environment: env,
      driveRoots: [p.join(fixture.path, 'ZDrive')],
      powerShellRunner: runner,
    )..whitelist = whitelist;
    ProcessUtils.debugSkip = true;
    AppState.debugSkipProcess = true;
  });
  tearDown(() {
    ProcessUtils.debugSkip = false;
    AppState.debugSkipProcess = false;
    fixture.deleteSync(recursive: true);
  });

  test('temp age, opt-in prefetch and invalid temp root', () async {
    final old = put(p.join(env['TEMP']!, 'old.tmp'));
    put(p.join(env['TEMP']!, 'active.tmp'), age: 0);
    final prefetch = put(p.join(env['SystemRoot']!, 'Prefetch', 'app.pf'));
    expect(
      (await items(CleanCategory.systemCache)).expand((i) => i.scannedFiles!),
      [old.path],
    );
    scan.options = const ScanOptions(cleanPrefetch: true);
    expect(
      (await items(CleanCategory.systemCache)).expand((i) => i.scannedFiles!),
      unorderedEquals([old.path, prefetch.path]),
    );
    env['TEMP'] = fixture.path;
    final result = await scan.scanAll(categories: {CleanCategory.systemCache});
    expect(result[CleanCategory.systemCache]!.error, contains('过大的范围'));
  });

  test(
    'system logs correct Srt location and filter age and non-log files',
    () async {
      final old = put(
        p.join(
          env['SystemRoot']!,
          'System32',
          'LogFiles',
          'Srt',
          'SrtTrail.log',
        ),
      );
      final cbs = put(p.join(env['SystemRoot']!, 'Logs', 'CBS', 'archive.cab'));
      put(p.join(env['SystemRoot']!, 'Logs', 'CBS', 'current.log'), age: 0);
      put(p.join(env['SystemRoot']!, 'Logs', 'DISM', 'settings.db'));
      expect(
        (await items(CleanCategory.systemLogs)).expand((i) => i.scannedFiles!),
        unorderedEquals([old.path, cbs.path]),
      );
    },
  );

  test('DirectX AMD NVIDIA belong to graphics category regardless request ordering', () async {
    put(p.join(env['LOCALAPPDATA']!, 'D3DSCache', 'shader'));
    put(p.join(env['LOCALAPPDATA']!, 'AMD', 'DxCache', 'shader'));
    put(
      p.join(env['ProgramData']!, 'NVIDIA Corporation', 'NV_Cache', 'shader'),
    );
    final result = await scan.scanAll(
      categories: {
        CleanCategory.appCache,
        CleanCategory.nvidiaCache,
        CleanCategory.systemCache,
      },
    );
    expect(result[CleanCategory.nvidiaCache]!.totalSizeBytes, 21);
    expect(result[CleanCategory.appCache]!.totalSizeBytes, 0);
    expect(result[CleanCategory.systemCache]!.totalSizeBytes, 0);
    scan.options = const ScanOptions(cleanGpuCache: false);
    final disabled = await scan.scanAll(
      categories: {CleanCategory.appCache, CleanCategory.nvidiaCache},
    );
    expect(disabled.values.expand((c) => c.items), isEmpty);
  });

  test(
    'disabled browser caches cannot reappear in generic app cache',
    () async {
      put(
        p.join(
          env['LOCALAPPDATA']!,
          'Google',
          'Chrome',
          'User Data',
          'Default',
          'Cache',
          'data',
        ),
      );
      scan.options = const ScanOptions(cleanBrowserCache: false);
      final result = await scan.scanAll(
        categories: {CleanCategory.appCache, CleanCategory.browserCache},
      );
      expect(result.values.expand((c) => c.items), isEmpty);
    },
  );

  test(
    'memory dumps stay excluded even when explicitly requested',
    () async {
      final dump = put(
        p.join(
          env['LOCALAPPDATA']!,
          'Microsoft',
          'Windows',
          'WER',
          'ReportQueue',
          'app.dmp',
        ),
      );
      put(p.join(env['SystemRoot']!, 'Minidump', 'keep.txt'));
      final result = await scan.scanAll(
        categories: {CleanCategory.systemCache, CleanCategory.memoryDumps},
      );
      expect(result, isNot(contains(CleanCategory.memoryDumps)));
      expect(result[CleanCategory.systemCache]!.totalSizeBytes, 0);
      expect(dump.existsSync(), isTrue);
    },
  );

  test('update caches do not include servicing databases or duplicate system totals', () async {
    final download = put(
      p.join(
        env['SystemRoot']!,
        'SoftwareDistribution',
        'Download',
        'update.bin',
      ),
    );
    final delivery = put(
      p.join(
        env['ProgramData']!,
        'Microsoft',
        'Windows',
        'DeliveryOptimization',
        'Cache',
        'data',
      ),
    );
    final database = put(
      p.join(
        env['SystemRoot']!,
        'SoftwareDistribution',
        'DataStore',
        'DataStore.edb',
      ),
    );
    final result = await scan.scanAll(
      categories: {
        CleanCategory.systemCache,
        CleanCategory.windowsUpdate,
        CleanCategory.appCache,
      },
    );
    expect(
      result[CleanCategory.windowsUpdate]!.items.expand((i) => i.scannedFiles!),
      unorderedEquals([download.path, delivery.path]),
    );
    expect(result[CleanCategory.windowsUpdate]!.selectedCount, 2);
    expect(result[CleanCategory.systemCache]!.totalSizeBytes, 0);
    expect(database.existsSync(), isTrue);
  });

  test(
    'leftovers only offer empty directories and recheck before removal',
    () async {
      final empty = Directory(p.join(env['ProgramFiles']!, 'EmptyApp'))
        ..createSync(recursive: true);
      final repair = put(
        p.join(env['ProgramData']!, 'Package Cache', 'app.msi'),
      );
      final npmConfig = put(p.join(env['APPDATA']!, 'npm', 'config'));
      final found = await items(CleanCategory.appLeftovers);
      expect(found.single.path, empty.path);
      expect(found.single.selected, isFalse);
      final newFile = put(p.join(empty.path, 'new.txt'));
      found.single.selected = true;
      expect((await CleanService().cleanItems(found)).skippedCount, 1);
      expect(newFile.existsSync(), isTrue);
      newFile.deleteSync();
      await CleanService().cleanItems(found);
      expect(empty.existsSync(), isFalse);
      expect(repair.existsSync() && npmConfig.existsSync(), isTrue);
    },
  );

  test('download folder reports file progress and preserves files outside its snapshot', () async {
    final root = p.join(env['DOWNLOADS']!, 'ProgressBundle');
    final reviewed = [for (var i = 0; i < 16; i++) put(p.join(root, '$i.bin'))];
    final later = put(p.join(root, 'later.txt'));
    final item = CleanItem(
      id: 'bundle',
      name: '下载包',
      path: root,
      sizeBytes: 16,
      category: CleanCategory.downloads,
      scannedFiles: reviewed.map((file) => file.path).toList(),
    );
    final messages = <String>[];
    final report = await CleanService().cleanItems([
      item,
    ], onItem: (_, message, _, _) => messages.add(message));
    expect(report.deletedCount, 1);
    expect(reviewed.every((file) => !file.existsSync()), isTrue);
    expect(later.existsSync(), isTrue);
    expect(
      messages.any((message) => message.contains(reviewed.first.path)),
      isTrue,
    );
    expect(
      messages.any((message) => message.contains(reviewed.last.path)),
      isTrue,
    );
    expect(messages.last, '已清理 下载包');
  });

  test('redirected downloads clean only selected snapshot and honor child whitelist', () async {
    final dir = p.join(env['DOWNLOADS']!, 'Bundle');
    final large = put(p.join(dir, 'large.bin'), bytes: 10 * 1024 * 1024);
    final protected = put(p.join(dir, 'private.txt'));
    await whitelist.add(protected.path);
    final found = await items(CleanCategory.downloads);
    expect(found.single.selected, isFalse);
    expect(found.single.scannedFiles, [large.path]);
    final later = put(p.join(dir, 'new.txt'));
    expect((await CleanService().cleanItems(found)).deletedCount, 0);
    found.single.selected = true;
    final report = await (CleanService()..whitelist = whitelist).cleanItems(
      found,
    );
    expect(report.freedBytes, 10 * 1024 * 1024);
    expect(large.existsSync(), isFalse);
    expect(protected.existsSync() && later.existsSync(), isTrue);
  });

  test('downloads resolve Windows Known Folder', () async {
    final actual = p.join(fixture.path, 'ActualDownloadLocation');
    env.remove('DOWNLOADS');
    var called = false;
    scan = ScanService(
      environment: env,
      driveRoots: const [],
      powerShellRunner: (script, timeout) async {
        called = called || script.contains('shell:Downloads');
        return PsResult(exitCode: 0, stdout: actual, stderr: '');
      },
    );
    final file = put(p.join(actual, 'large.bin'), bytes: 10 * 1024 * 1024);
    expect((await items(CleanCategory.downloads)).single.path, file.path);
    expect(called, isTrue);
  });

  test(
    'recycle is current-user and selected-drive only with correct progress',
    () async {
      final root = p.join(fixture.path, 'ZDrive', r'$Recycle.Bin');
      final payload = put(p.join(root, sid, r'$Rone.txt'));
      final metadata = put(p.join(root, sid, r'$Ione.txt'));
      final other = put(p.join(root, 'S-1-5-21-999', r'$Rother.txt'));
      final found = await items(CleanCategory.recycleBin);
      expect(
        found.single.scannedFiles,
        unorderedEquals([payload.path, metadata.path]),
      );
      final later = put(p.join(root, sid, r'$Rlater.txt'));
      for (final item in found) {
        item.selected = true;
      }
      final progress = <int>[];
      final report = await CleanService().cleanItems(
        found,
        onItem: (_, _, done, _) => progress.add(done),
      );
      expect(report.freedBytes, 14);
      expect(progress.last, 1);
      expect(other.existsSync() && later.existsSync(), isTrue);
    },
  );

  test('protected recycle payload retains its recovery metadata', () async {
    final root = p.join(fixture.path, 'ZDrive', r'$Recycle.Bin', sid);
    final payload = put(p.join(root, r'$Rone.txt'));
    final metadata = put(p.join(root, r'$Ione.txt'));
    await whitelist.add(payload.path);
    final found = await items(CleanCategory.recycleBin);
    await CleanService().cleanItems(found);
    expect(payload.existsSync() && metadata.existsSync(), isTrue);
  });

  test('recent shortcuts and jump lists keep separate entries, no arbitrary personal files', () async {
    final root = p.join(env['APPDATA']!, 'Microsoft', 'Windows', 'Recent');
    final shortcut = put(p.join(root, 'file.lnk'));
    final jump = put(
      p.join(root, 'AutomaticDestinations', 'app.automaticDestinations-ms'),
    );
    put(p.join(root, 'keep.txt'));
    final found = await items(CleanCategory.usageTraces);
    expect(
      found.expand((i) => i.scannedFiles!),
      unorderedEquals([shortcut.path, jump.path]),
    );
    expect(found, hasLength(2));
    expect(found.every((i) => i.selected), isTrue);
  });

  test(
    'software usage finds nested logs while retaining sessions and history',
    () async {
      final log = put(
        p.join(env['APPDATA']!, 'Microsoft', 'App', 'v1', 'logs', 'old.log'),
      );
      put(p.join(env['APPDATA']!, 'App', 'sessions', 'work.json'));
      put(p.join(env['APPDATA']!, 'App', 'history', 'History'));
      put(p.join(env['APPDATA']!, 'App', 'logs', 'settings.json'));
      final found = await items(CleanCategory.softwareUsage);
      expect(found.single.scannedFiles, [log.path]);
      expect(found.single.selected, isTrue);
    },
  );

  test(
    'one-click scans only user caches with globally unique file ownership',
    () async {
      put(p.join(env['LOCALAPPDATA']!, 'D3DSCache', 'shader'));
      put(p.join(env['LOCALAPPDATA']!, 'Vendor', 'Cache', 'GPUCache', 'data'));
      final result = await scan.scanAll();
      expect(result.keys.toSet(), oneClickScanCategories);
      expect(result.values.every((r) => r.error == null), isTrue);
      final files = result.values
          .expand((c) => c.items)
          .expand((i) => i.scannedFiles ?? <String>[])
          .toList();
      expect(files.toSet().length, files.length);
    },
  );

  test('case and dot segments cannot bypass whitelist', () async {
    final target = p.join(env['LOCALAPPDATA']!, 'App', 'Cache');
    await whitelist.add(target);
    expect(whitelist.isWhitelisted(target.toUpperCase()), isTrue);
    expect(
      whitelist.isWhitelisted(p.join(target, 'nested', '..', 'data')),
      isTrue,
    );
    expect(whitelist.isWhitelisted('${target}Other'), isFalse);
    await whitelist.remove(target.toUpperCase());
    expect(whitelist.length, 0);
  });

  test('registry errors visible, targets individual values and report zero disk bytes', () async {
    scan = ScanService(
      environment: env,
      driveRoots: const [],
      powerShellRunner: (_, _) async =>
          PsResult(exitCode: 1, stdout: '', stderr: 'denied'),
    );
    expect(
      (await scan.scanAll(
        categories: {CleanCategory.registryJunk},
      ))[CleanCategory.registryJunk]!.error,
      contains('denied'),
    );
    final row = {
      'Name': '失效 MUI',
      'Path': r'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache',
      'Kind': 'MuiCache',
      'ValueName': r'C:\missing.exe.FriendlyAppName',
      'Value': 'Old App',
      'Executable': r'C:\missing.exe',
    };
    scan = ScanService(
      environment: env,
      driveRoots: const [],
      powerShellRunner: (_, _) async =>
          PsResult(exitCode: 0, stdout: jsonEncode([row]), stderr: ''),
    );
    final found = await items(CleanCategory.registryJunk);
    expect(found.single.sizeBytes, 0);
    expect(found.single.selected, isFalse);
    String? script;
    final clean = CleanService(
      powerShellRunner: (text, _) async {
        script = text;
        return PsResult(exitCode: 1, stdout: '', stderr: 'value changed');
      },
    );
    found.single.selected = true;
    final report = await clean.cleanItems(found);
    expect(report.failedCount, 1);
    expect(report.completedItemIds, isEmpty);
    expect(found.single.fileCount, 1);
    expect(script, contains('.DeleteValue('));
    expect(script, isNot(contains('Remove-Item -')));
  });

  test(
    'settings persist and forced subset scan preserves other categories',
    () async {
      final cache = ModuleCache(
        namespace: 'scan',
        storageDirectory: p.join(fixture.path, 'cache'),
      );
      final preferences = ModuleCache(
        namespace: 'prefs',
        storageDirectory: p.join(fixture.path, 'cache'),
      );
      AppState state() => AppState(
        scanService: scan,
        whitelistService: whitelist,
        scanCache: cache,
        preferencesCache: preferences,
      );
      final first = state();
      await first.updateOptions(
        const ScanOptions(cleanPrefetch: true, cleanGpuCache: false),
      );
      final restored = state();
      expect(restored.options.cleanPrefetch, isTrue);
      expect(restored.options.cleanGpuCache, isFalse);
      await restored.scan(categories: {CleanCategory.systemCache});
      await restored.scan(
        categories: {CleanCategory.browserCache},
        force: true,
      );
      expect(restored.results.keys.toSet(), {
        CleanCategory.systemCache,
        CleanCategory.browserCache,
      });
      first.dispose();
      restored.dispose();
    },
  );

  test(
    'partial cleanup keeps actual remaining files visible in state',
    () async {
      final root = p.join(env['LOCALAPPDATA']!, 'Vendor', 'Cache');
      final good = put(p.join(root, 'good.bin'));
      final protected = put(p.join(root, 'protected.bin'));
      final state = AppState(
        scanService: scan,
        whitelistService: whitelist,
        scanCache: ModuleCache(
          namespace: 'state_scan',
          storageDirectory: fixture.path,
        ),
        preferencesCache: ModuleCache(
          namespace: 'state_prefs',
          storageDirectory: fixture.path,
        ),
      );
      await state.scan(categories: {CleanCategory.appCache});
      await whitelist.add(protected.path);
      state.toggleCategory(state.results[CleanCategory.appCache]!, true);
      final report = await state.cleanSelected();
      expect(report.freedBytes, 7);
      expect(good.existsSync(), isFalse);
      expect(protected.existsSync(), isTrue);
      expect(state.results[CleanCategory.appCache]!.items.single.sizeBytes, 7);
      state.dispose();
    },
  );
  test('changed files survive cleanup and duplicate snapshots do not inflate freed bytes', () async {
    final file = put(p.join(env['LOCALAPPDATA']!, 'Vendor', 'Cache', 'data'));
    final found = await items(CleanCategory.appCache);
    for (final item in found) {
      item.selected = true;
    }
    file.writeAsStringSync('new contents after scan');
    final report = await CleanService().cleanItems(found);
    expect(report.completedItemIds, isEmpty);
    expect(report.freedBytes, 0);
    expect(file.existsSync(), isTrue);
    final again = await items(CleanCategory.appCache);
    for (final item in again) {
      item.selected = true;
    }
    final cleaned = await CleanService().cleanItems([
      again.single,
      again.single,
    ]);
    expect(cleaned.freedBytes, 'new contents after scan'.length);
  });

  test('registry scripts parse without executing registry changes', () async {
    if (!Platform.isWindows) return;
    final target = CleanItem(
      id: 'registry',
      name: 'stale',
      path: r'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache',
      category: CleanCategory.registryJunk,
      sizeBytes: 0,
      note: 'MuiCache',
      registryValueName: r'C:\missing.exe.FriendlyAppName',
      registryValueData: 'Old App',
      registryExecutable: r'C:\missing.exe',
    );
    expect(RegistryCache.accepts(target), isTrue);
    for (final script in [
      RegistryCache.scanScript,
      RegistryCache.cleanupScript(target),
    ]) {
      final encoded = base64Encode(utf8.encode(script));
      final parse =
          '\$source = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(\'$encoded\')); '
          r'$tokens=$null; $errors=$null; '
          r'[void][Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors); '
          r'if ($errors.Count -gt 0) { $errors.Message; exit 1 }';
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        parse,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    }
  });
}
