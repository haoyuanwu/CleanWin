import 'dart:io';

import 'package:clean_windows/models/clean_models.dart';
import 'package:clean_windows/services/cache_discovery.dart';
import 'package:clean_windows/services/file_operability.dart';
import 'package:clean_windows/services/scan_diagnostics.dart';
import 'package:clean_windows/services/scan_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory fixture;
  setUp(() {
    fixture = Directory.systemTemp.createTempSync('cleanwin_access_').absolute;
  });
  tearDown(() {
    expect(
      p.isWithin(Directory.systemTemp.absolute.path, fixture.path),
      isTrue,
    );
    fixture.deleteSync(recursive: true);
  });
  File put(String relative) {
    final file = File(p.join(fixture.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('cache');
    return file;
  }

  Map<String, String> environment() => {
    'USER_SID': 'S-1-5-21-100',
    'USERPROFILE': fixture.path,
    'LOCALAPPDATA': p.join(fixture.path, 'Local'),
    'APPDATA': p.join(fixture.path, 'Roaming'),
    'ProgramData': p.join(fixture.path, 'ProgramData'),
    'SystemRoot': p.join(fixture.path, 'Windows'),
  };

  test('discovery limits are never reported as unreadable directories', () {
    final result = readDiagnostics({}, {'软件目录发现已达本轮上限，可开启深度扫描继续检查：C:\\Local'});
    expect(result, contains('上限'));
    expect(result, isNot(contains('未完整读取')));
    expect(result, isNot(contains('拒绝')));
  });
  test('read failures keep actual Windows cause and usable directory path', () {
    final result = readDiagnostics({
      'denied': FileSystemException(
        'listing',
        r'C:\ProgramData\Service\*',
        const OSError('denied', 5),
      ),
      'busy': FileSystemException(
        'stat',
        r'C:\Local\busy',
        const OSError('busy', 32),
      ),
    }, {});
    expect(result, contains('2 个位置未完整读取'));
    expect(result, contains('目录访问被拒绝（Windows 5）'));
    expect(result, contains('读取时发生占用冲突（Windows 32）'));
    expect(result, isNot(contains(r'\*')));
  });
  test('service data exclusions are bounded and preserve actual application caches', () {
    const root = r'C:\ProgramData';
    for (final relative in [
      r'Microsoft\Diagnosis',
      r'Microsoft\SmsRouter\Logs',
      'Packages',
      'WindowsHolographicDevices',
      r'Windows Master Store\ServiceData',
    ]) {
      expect(
        systemServiceDataPath(p.windows.join(root, relative), root),
        isTrue,
      );
    }
    for (final path in [
      r'C:\ProgramData\Microsoft\Edge\Cache',
      r'C:\ProgramData\Vendor\Cache',
      r'C:\ProgramData\PackagesBackup\Cache',
      r'C:\Users\A\Packages\Cache',
    ]) {
      expect(systemServiceDataPath(path, root), isFalse);
    }
  });
  test('software discovery avoids service data while retaining ordinary vendor caches', () async {
    final excluded = put(
      p.join('ProgramData', 'Microsoft', 'Diagnosis', 'Cache', 'data'),
    );
    final retained = put(p.join('ProgramData', 'Vendor', 'Cache', 'data'));
    final scanned = <String>[];
    final service = ScanService(
      environment: environment(),
      driveRoots: [],
      operabilityProbe: (paths) async => paths.toSet(),
    );
    final result = await service.scanAll(
      categories: {CleanCategory.appCache},
      onProgress: (progress) => scanned.add(progress.currentPath),
    );
    final files = result.values
        .expand((category) => category.items)
        .expand((item) => item.scannedFiles!);
    expect(files, contains(retained.path));
    expect(files, isNot(contains(excluded.path)));
    expect(scanned.any((path) => path.contains('Diagnosis')), isFalse);
    expect(excluded.existsSync(), isTrue);
  });
  test(
    'readable but busy cache is diagnosed without becoming a cleanup offer',
    () async {
      final busy = put(p.join('Local', 'DingDing', 'Cache', 'busy'));
      final good = put(p.join('Local', 'DingDing', 'Cache', 'good'));
      final scanner = ScanService(
        environment: environment(),
        driveRoots: [],
        accessProbe: (paths) async => FileOperabilityReport(
          allowed: paths.where((path) => path != busy.path).toSet(),
          blocked: {
            if (paths.contains(busy.path))
              busy.path: cleanupBlockFromWindowsError(32),
          },
        ),
      );
      final category = (await scanner.scanAll(
        categories: {CleanCategory.appCache},
      ))[CleanCategory.appCache]!;
      expect(category.items.expand((item) => item.scannedFiles!), [good.path]);
      expect(category.items.single.blockedFiles, [busy.path]);
      expect(category.items.single.blockedSizeBytes, busy.lengthSync());
      expect(category.error, contains('已统计但未加入清理'));
      expect(category.unreadableCount, 0);
      expect(category.blockedFileCount, 1);
      expect(category.diagnosticLabel, '1 个文件暂不可清理');
      expect(category.error, contains('正在占用 1 个'));
      expect(category.error, contains('Windows 32'));
      expect(category.error, isNot(contains('未完整读取')));
      expect(busy.existsSync(), isTrue);
    },
  );
  test(
    'font rule never descends into Windows Hello or credential siblings',
    () async {
      final localService = p.join(
        'Windows',
        'ServiceProfiles',
        'LocalService',
        'AppData',
        'Local',
      );
      final direct = put(p.join(localService, 'FontCache3.0.0.0.dat'));
      final cache = put(
        p.join(localService, 'FontCache', 'FontCache-System.dat'),
      );
      final ngc = put(
        p.join(localService, 'Microsoft', 'Ngc', 'font-secret.dat'),
      );
      final credentials = put(
        p.join(localService, 'Credentials', 'font-token.dat'),
      );
      final unrelated = put(
        p.join(localService, 'FontCache', 'not-a-font.dat'),
      );
      final visited = <String>[];
      final scanner = ScanService(
        environment: environment(),
        driveRoots: [],
        operabilityProbe: (paths) async => paths.toSet(),
      );
      final result = await scanner.scanAll(
        categories: spaceCleanupScanCategories,
        onProgress: (progress) => visited.add(progress.currentPath),
      );
      final files = result.values
          .expand((category) => category.items)
          .expand((item) => item.scannedFiles ?? <String>[])
          .toList();
      expect(files, containsAll([direct.path, cache.path]));
      expect(files, isNot(contains(ngc.path)));
      expect(files, isNot(contains(credentials.path)));
      expect(files, isNot(contains(unrelated.path)));
      expect(
        visited.any(
          (path) => path.contains('Ngc') || path.contains('Credentials'),
        ),
        isFalse,
      );
      expect(ngc.existsSync(), isTrue);
      expect(credentials.existsSync(), isTrue);
      expect(result[CleanCategory.systemCache]!.unreadableCount, 0);
    },
  );

  test('native probe distinguishes busy, readonly and missing paths without changing files', () async {
    final normal = put('normal.cache');
    final busy = put('busy.cache');
    final readonly = put('readonly.cache');
    final missing = p.join(fixture.path, 'missing.cache');
    final lock = await busy.open();
    try {
      final attr = await Process.run('attrib.exe', ['+R', readonly.path]);
      expect(attr.exitCode, 0);
      final report = await inspectCleanupPaths([
        normal.path,
        busy.path,
        readonly.path,
        missing,
      ]);
      expect(report.allowed, {normal.path});
      expect(report.blocked[busy.path]!.reason, CleanupBlockReason.inUse);
      expect(report.blocked[busy.path]!.windowsError, 32);
      expect(
        report.blocked[readonly.path]!.reason,
        CleanupBlockReason.readOnly,
      );
      expect(report.blocked[missing]!.reason, CleanupBlockReason.disappeared);
      expect(normal.lengthSync(), 5);
      expect(busy.lengthSync(), 5);
      expect(readonly.lengthSync(), 5);
    } finally {
      await lock.close();
      await Process.run('attrib.exe', ['-R', readonly.path]);
    }
    final unlocked = await inspectCleanupPaths([busy.path, readonly.path]);
    expect(unlocked.allowed, {busy.path, readonly.path});
  }, skip: !Platform.isWindows);
}
