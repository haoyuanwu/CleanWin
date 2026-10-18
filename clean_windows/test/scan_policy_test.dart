import 'dart:io';

import 'package:clean_windows/models/clean_models.dart';
import 'package:clean_windows/models/scan_options.dart';
import 'package:clean_windows/services/file_operability.dart';
import 'package:clean_windows/services/module_cache.dart';
import 'package:clean_windows/services/scan_service.dart';
import 'package:clean_windows/services/whitelist_service.dart';
import 'package:clean_windows/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory fixture;
  late Map<String, String> env;
  setUp(() {
    fixture = Directory('.dart_tool').createTempSync('scan_policy_').absolute;
    env = {
      'USERPROFILE': fixture.path,
      'LOCALAPPDATA': p.join(fixture.path, 'AppData', 'Local'),
      'APPDATA': p.join(fixture.path, 'AppData', 'Roaming'),
      'SystemRoot': p.join(fixture.path, 'Windows'),
      'ProgramData': p.join(fixture.path, 'ProgramData'),
      'ProgramFiles': p.join(fixture.path, 'Program Files'),
      'ProgramFiles(x86)': p.join(fixture.path, 'Program Files (x86)'),
    };
  });
  tearDown(() {
    expect(
      p.isWithin(Directory('.dart_tool').absolute.path, fixture.path),
      isTrue,
    );
    fixture.deleteSync(recursive: true);
  });
  File put(String path, {bool old = true}) {
    final file = File(path)..parent.createSync(recursive: true);
    file.writeAsStringSync('data');
    if (old) {
      file.setLastModifiedSync(
        DateTime.now().subtract(const Duration(days: 10)),
      );
    }
    return file;
  }

  test('one-click prunes protected roots and defaults only operable old temporary files', () async {
    final local = env['LOCALAPPDATA']!;
    final old = put(p.join(local, 'Temp', 'old.tmp'));
    final denied = put(p.join(local, 'Temp', 'denied.tmp'));
    final fresh = put(p.join(local, 'Temp', 'fresh.tmp'), old: false);
    env['TEMP'] = p.join(fixture.path, 'RedirectedTemp');
    final redirectedOld = put(p.join(env['TEMP']!, 'old.temp'));
    final redirectedRecent = put(p.join(env['TEMP']!, 'recent.tmp'));
    redirectedRecent.setLastModifiedSync(
      DateTime.now().subtract(const Duration(days: 3)),
    );
    final installer = put(p.join(local, 'Temp', 'installer.exe'));
    final gpu = put(p.join(local, 'D3DSCache', 'shader.bin'));
    final browser = put(
      p.join(
        local,
        'Google',
        'Chrome',
        'User Data',
        'Default',
        'GPUCache',
        'shader',
      ),
    );
    final app = put(p.join(local, 'Vendor', 'Cache', 'data'));
    put(p.join(env['ProgramData']!, 'Vendor', 'Cache', 'system.bin'));
    put(p.join(env['SystemRoot']!, 'Temp', 'system.tmp'));
    final visited = <String>[];
    final service = ScanService(
      environment: env,
      powerShellRunner: (_, _) async =>
          throw StateError('One-click must not launch PowerShell'),
      operabilityProbe: (paths) async =>
          paths.where((path) => path != denied.path).toSet(),
    );
    service.options = const ScanOptions(deepScan: true);
    final result = await service.scanAll(
      onProgress: (progress) {
        if (progress.currentPath.isNotEmpty) visited.add(progress.currentPath);
      },
    );
    expect(result.keys.toSet(), oneClickScanCategories);
    expect(
      visited.any(
        (path) =>
            p.isWithin(env['ProgramData']!, path) ||
            p.isWithin(env['SystemRoot']!, path),
      ),
      isFalse,
    );
    final items = result.values.expand((category) => category.items).toList();
    expect(
      items.where((item) => item.selected).expand((item) => item.scannedFiles!),
      containsAll([old.path, redirectedOld.path]),
    );
    final files = items.expand((item) => item.scannedFiles!).toSet();
    expect(
      files.contains(denied.path) ||
          files.contains(fresh.path) ||
          files.contains(redirectedRecent.path) ||
          files.contains(installer.path),
      isFalse,
    );
    expect(files, containsAll([gpu.path, browser.path, app.path]));
    expect(
      items
          .where((item) => item.category != CleanCategory.systemCache)
          .every((item) => !item.selected),
      isTrue,
    );
    service.options = const ScanOptions(
      cleanBrowserCache: false,
      cleanGpuCache: false,
    );
    final limited = await service.scanAll();
    expect(limited.keys.toSet(), {
      CleanCategory.systemCache,
      CleanCategory.appCache,
    });
  });

  test('native capability checks skip in-use, read-only and missing files without changing data', () async {
    if (!Platform.isWindows) return;
    final available = put(p.join(fixture.path, 'normal.tmp'));
    final inUse = put(p.join(fixture.path, 'open.tmp'));
    final readOnly = put(p.join(fixture.path, 'readonly.tmp'));
    final stamp = available.statSync().modified;
    final handle = await inUse.open(mode: FileMode.append);
    try {
      final attribute = await Process.run('attrib', ['+r', readOnly.path]);
      expect(attribute.exitCode, 0);
      final allowed = await operableCleanupPaths([
        available.path,
        inUse.path,
        readOnly.path,
        p.join(fixture.path, 'missing.tmp'),
      ]);
      expect(allowed, {available.path});
      expect(available.readAsStringSync(), 'data');
      expect(available.statSync().modified, stamp);
    } finally {
      await handle.close();
      await Process.run('attrib', ['-r', readOnly.path]);
    }
    expect(await operableCleanupPaths([inUse.path]), {inUse.path});
  });

  test(
    'cached results never reselect GPU, browser, thumbnail or program caches',
    () async {
      final local = env['LOCALAPPDATA']!;
      put(p.join(local, 'Temp', 'old.tmp'));
      put(p.join(local, 'D3DSCache', 'shader'));
      put(p.join(local, 'Vendor', 'Cache', 'data'));
      put(p.join(local, 'Microsoft', 'Windows', 'Explorer', 'thumbcache_1.db'));
      final cache = ModuleCache(
        namespace: 'scan',
        storageDirectory: fixture.path,
      );
      final preferences = ModuleCache(
        namespace: 'preferences',
        storageDirectory: fixture.path,
      );
      final service = ScanService(
        environment: env,
        operabilityProbe: (paths) async => paths.toSet(),
      );
      final state = AppState(
        scanService: service,
        scanCache: cache,
        preferencesCache: preferences,
        whitelistService: WhitelistService(storageDirectory: fixture.path),
      );
      await state.scan(force: true);
      state.dispose();
      final restored = AppState(
        scanCache: cache,
        preferencesCache: preferences,
        whitelistService: WhitelistService(storageDirectory: fixture.path),
      );
      expect(restored.totalSelectedCount, 1);
      expect(
        restored.categories
            .expand((category) => category.items)
            .where((item) => item.selected)
            .single
            .id,
        'user_temp',
      );
      expect(restored.results[CleanCategory.nvidiaCache]!.selectedCount, 0);
      restored.dispose();
    },
  );
}
