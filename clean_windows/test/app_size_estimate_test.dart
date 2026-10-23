import 'dart:convert';
import 'dart:io';

import 'package:clean_windows/models/installed_app.dart';
import 'package:clean_windows/services/module_cache.dart';
import 'package:clean_windows/services/path_utils.dart';
import 'package:clean_windows/services/process_utils.dart';
import 'package:clean_windows/services/uninstall_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    ProcessUtils.debugSkip = true;
  });
  tearDown(() {
    ProcessUtils.debugSkip = false;
  });

  group('extractExecutablePath', () {
    test('strips icon index and quotes', () {
      expect(
        extractExecutablePath(r'"C:\App\app.exe",0'),
        r'C:\App\app.exe',
      );
      expect(extractExecutablePath(r'C:\App\app.exe'), r'C:\App\app.exe');
      expect(
        extractExecutablePath(r'C:\App\unins000.exe /SILENT'),
        r'C:\App\unins000.exe',
      );
      expect(extractExecutablePath(''), isNull);
    });

    test('rejects bare executable names so cwd is never measured', () {
      expect(extractExecutablePath(r'msiexec.exe /X{ABC}'), isNull);
      expect(extractExecutablePath('unins000.exe'), isNull);
    });
  });

  group('resolveInstallRoot', () {
    test('prefers existing install location', () {
      final dir = Directory.systemTemp.createTempSync('cleanwin-root-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final root = resolveInstallRoot(
        installLocation: dir.path,
        uninstallString: r'C:\nowhere\unins000.exe',
      );
      expect(root, dir.path);
    });

    test('falls back to uninstaller directory', () {
      final dir = Directory.systemTemp.createTempSync('cleanwin-root-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final exe = File('${dir.path}\\unins000.exe')..writeAsStringSync('x');
      final root = resolveInstallRoot(uninstallString: '"${exe.path}"');
      expect(root, dir.path);
    });
  });

  group('measureDirectoryBytes', () {
    test('sums nested file sizes', () async {
      final dir = Directory.systemTemp.createTempSync('cleanwin-measure-');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}\\a.bin').writeAsBytesSync(List.filled(100, 1));
      final sub = Directory('${dir.path}\\sub')..createSync();
      File('${sub.path}\\b.bin').writeAsBytesSync(List.filled(50, 2));
      expect(measureDirectoryBytesSync(dir.path), 150);
      expect(await measureDirectoryBytes(dir.path), 150);
    });
  });

  group('UninstallService.fillMissingSizes', () {
    test('measures install root when registry size is missing', () async {
      final dir = Directory.systemTemp.createTempSync('cleanwin-app-');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}\\payload.bin').writeAsBytesSync(List.filled(2048, 3));

      final cache = ModuleCache(
        namespace: 'test_apps_${DateTime.now().microsecondsSinceEpoch}',
        storageDirectory: Directory.systemTemp.createTempSync(
          'cleanwin-cache-',
        ).path,
      );
      addTearDown(() {
        final d = Directory(cache.storageDirectory!);
        if (d.existsSync()) d.deleteSync(recursive: true);
      });

      final service = UninstallService(
        runner: (script, timeout) async =>
            PsResult(exitCode: 0, stdout: '[]', stderr: ''),
        cache: cache,
      );

      final app = InstalledApp(
        displayName: 'Measured',
        installLocation: dir.path,
        uninstallString: '"${dir.path}\\unins000.exe"',
      );
      var updates = 0;
      await service.fillMissingSizes([app], onUpdated: (_) => updates++);
      expect(app.measuredSizeBytes, 2048);
      expect(app.sizeIsMeasured, isTrue);
      expect(app.hasSize, isTrue);
      expect(updates, 1);

      // 二次调用走缓存，不再测量也能恢复
      final second = InstalledApp(
        displayName: 'Measured',
        installLocation: dir.path,
        uninstallString: '"${dir.path}\\unins000.exe"',
      );
      await service.fillMissingSizes([second]);
      expect(second.measuredSizeBytes, 2048);
    });

    test('keeps registry sizes and leaves unresolvable apps unknown', () async {
      final cache = ModuleCache(
        namespace: 'test_apps_${DateTime.now().microsecondsSinceEpoch}',
        storageDirectory: Directory.systemTemp.createTempSync(
          'cleanwin-cache-',
        ).path,
      );
      addTearDown(() {
        final d = Directory(cache.storageDirectory!);
        if (d.existsSync()) d.deleteSync(recursive: true);
      });

      final service = UninstallService(
        runner: (script, timeout) async =>
            PsResult(exitCode: 0, stdout: '[]', stderr: ''),
        cache: cache,
      );

      final registryApp = InstalledApp(
        displayName: 'From Registry',
        estimatedSizeKb: 512,
        uninstallString: 'msiexec.exe /X{ABC}',
      );
      final unknown = InstalledApp(
        displayName: 'No Path',
        uninstallString: 'msiexec.exe /X{XYZ}',
      );
      await service.fillMissingSizes([registryApp, unknown]);
      expect(registryApp.measuredSizeBytes, isNull);
      expect(registryApp.estimatedSizeBytes, 512 * 1024);
      expect(unknown.measuredSizeBytes, isNull);
      expect(unknown.hasSize, isFalse);
    });

    test('listInstalled restores measured sizes from cache', () async {
      final storage = Directory.systemTemp.createTempSync('cleanwin-cache-');
      addTearDown(() {
        if (storage.existsSync()) storage.deleteSync(recursive: true);
      });
      final cache = ModuleCache(
        namespace: 'test_apps_${DateTime.now().microsecondsSinceEpoch}',
        storageDirectory: storage.path,
      );

      final dir = Directory.systemTemp.createTempSync('cleanwin-cached-');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}\\x.bin').writeAsBytesSync(List.filled(4096, 9));

      final payload = jsonEncode([
        {
          'DisplayName': 'Cached Size App',
          'UninstallString': r'C:\nowhere\unins000.exe',
          'EstimatedSize': null,
          'InstallLocation': dir.path,
        },
      ]);
      final service = UninstallService(
        runner: (script, timeout) async =>
            PsResult(exitCode: 0, stdout: payload, stderr: ''),
        cache: cache,
      );

      // 先填充测量缓存
      final seed = InstalledApp(
        displayName: 'Cached Size App',
        uninstallString: r'C:\nowhere\unins000.exe',
        installLocation: dir.path,
      );
      await service.fillMissingSizes([seed]);
      expect(seed.measuredSizeBytes, 4096);

      // 强制重新列表，identity 相同应恢复 measuredSizeBytes
      final listed = await service.listInstalled(force: true);
      expect(listed, hasLength(1));
      expect(listed.single.measuredSizeBytes, 4096);
      expect(listed.single.hasSize, isTrue);
    });
  });
}
