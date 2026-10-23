import 'dart:convert';
import 'dart:io';

import 'package:clean_windows/models/clean_models.dart';
import 'package:clean_windows/services/download_discovery.dart';
import 'package:clean_windows/services/cache_discovery.dart';
import 'package:clean_windows/services/process_utils.dart';
import 'package:clean_windows/services/scan_service.dart';
import 'package:clean_windows/services/whitelist_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory fixture;
  late Map<String, String> environment;
  setUp(() {
    fixture = Directory.systemTemp.createTempSync('cleanwin_rules_').absolute;
    environment = {
      'USERPROFILE': p.join(fixture.path, 'User'),
      'LOCALAPPDATA': p.join(fixture.path, 'User', 'AppData', 'Local'),
      'APPDATA': p.join(fixture.path, 'User', 'AppData', 'Roaming'),
      'DOWNLOADS': p.join(fixture.path, 'Downloads'),
      'SystemRoot': p.join(fixture.path, 'Windows'),
      'SystemDrive': fixture.path,
      'ProgramData': p.join(fixture.path, 'ProgramData'),
      'ProgramFiles': p.join(fixture.path, 'Program Files'),
      'USER_SID': 'S-1-5-21-100',
    };
  });
  tearDown(() {
    expect(
      p.isWithin(Directory.systemTemp.absolute.path, fixture.path),
      isTrue,
    );
    fixture.deleteSync(recursive: true);
  });
  File put(String path, {String content = 'data', int age = 10}) {
    final file = File(path)..parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    file.setLastModifiedSync(DateTime.now().subtract(Duration(days: age)));
    return file;
  }

  ScanService scanner({Set<String> denied = const {}}) => ScanService(
    environment: environment,
    driveRoots: const [],
    operabilityProbe: (paths) async =>
        paths.where((path) => !denied.contains(path)).toSet(),
    powerShellRunner: (_, _) async =>
        PsResult(exitCode: 0, stdout: '[]', stderr: ''),
  );
  List<String> files(Map<CleanCategory, ScanCategory> result) => result.values
      .expand((c) => c.items)
      .expand((i) => i.scannedFiles ?? <String>[])
      .toList();

  test('software discovery covers other apps, profiles and shared data without scanning protected state', () async {
    final local = environment['LOCALAPPDATA']!,
        roaming = environment['APPDATA']!,
        shared = environment['ProgramData']!;
    final expected = [
      put(p.join(roaming, 'WorkBuddy', 'CachedData', 'version', 'data')).path,
      put(p.join(roaming, 'bilibili', 'Cache', 'Cache_Data', 'data_0')).path,
      put(p.join(roaming, 'youku-app', 'Code Cache', 'js', 'entry')).path,
      put(p.join(roaming, 'UnknownEditor', 'Cache', 'resource')).path,
      put(
        p.join(
          local,
          'OtherVendor',
          'OtherApp',
          'User Data',
          'Default',
          'Cache',
          'data',
        ),
      ).path,
      put(
        p.join(
          local,
          'Packages',
          'Other.Package',
          'LocalCache',
          'Roaming',
          'App',
          'Cache',
          'data',
        ),
      ).path,
      put(p.join(shared, 'AnotherVendor', 'Cache', 'resource')).path,
      put(
        p.join(
          roaming,
          'Tencent',
          'QQLive',
          'WebView2',
          'version',
          'User Data',
          'Default',
          'Cache',
          'data',
        ),
      ).path,
      put(p.join(roaming, 'UnknownApp', 'logs', 'old.log'), age: 10).path,
    ];
    final keep = [
      put(p.join(roaming, 'UnknownApp', 'logs', 'new.log'), age: 0),
      put(p.join(roaming, 'UnknownApp', 'logs', 'settings.json')),
      put(
        p.join(
          local,
          'OtherVendor',
          'OtherApp',
          'User Data',
          'Default',
          'Sessions',
          'session',
        ),
      ),
      put(
        p.join(
          local,
          'OtherVendor',
          'OtherApp',
          'User Data',
          'Default',
          'IndexedDB',
          'Cache',
          'personal',
        ),
      ),
      put(p.join(roaming, 'youku', 'nplayerdisk', 'Cache', 'offline-video')),
      put(
        p.join(
          roaming,
          'Tencent',
          'QQLive',
          'CacheFile',
          'Cache',
          'offline-video',
        ),
      ),
      put(p.join(local, 'npm-cache', 'Cache', 'dependency')),
      put(
        p.join(roaming, 'UnknownEditor', 'node_modules', 'Cache', 'dependency'),
      ),
      put(p.join(roaming, 'UnknownEditor', 'GPUCache', 'shader')),
    ];
    final result = await scanner().scanAll(
      categories: spaceCleanupScanCategories,
    );
    final found = files(result);
    expect(found, unorderedEquals(expected));
    expect(found.toSet().length, found.length);
    expect(
      result[CleanCategory.appCache]!.items.every((i) => i.selected),
      isTrue,
    );
    for (final file in keep) {
      expect(found, isNot(contains(file.path)));
      expect(file.existsSync(), isTrue);
    }
  });

  test('metadata discovery reports its limit and can cancel without traversing all directories', () async {
    final root = Directory(p.join(fixture.path, 'limited'))..createSync();
    put(p.join(root.path, 'vendor', 'one', 'Cache', 'data'));
    put(p.join(root.path, 'vendor', 'two', 'Cache', 'data'));
    var limited = false;
    await discoverCaches(
      root,
      maxDepth: 8,
      maxDirectories: 1,
      onLimit: (_) => limited = true,
    ).toList();
    expect(limited, isTrue);
    var cancelled = false;
    final paths = <String>[];
    await discoverCaches(
      root,
      maxDepth: 8,
      cancelled: () => cancelled,
      onPath: (path) {
        paths.add(path);
        cancelled = true;
      },
    ).toList();
    expect(paths.length, 1);
    final depths = <int>[];
    await discoverCaches(
      root,
      maxDepth: 8,
      breadthFirst: true,
      onPath: (path) {
        depths.add(
          p.equals(root.path, path)
              ? 0
              : p.split(p.relative(path, from: root.path)).length,
        );
      },
    ).toList();
    expect(depths, orderedEquals([...depths]..sort()));
  });

  test('fast scan finds explicit app and Chinese browser caches without touching app state', () async {
    final local = environment['LOCALAPPDATA']!,
        roaming = environment['APPDATA']!;
    final found = [
      put(p.join(roaming, 'Code', 'Code Cache', 'data')).path,
      put(p.join(local, 'Vendor', 'Deep', 'Cache', 'resource')).path,
      put(p.join(roaming, 'Cursor', 'CachedData', 'data')).path,
      put(p.join(local, 'DingDing', 'Cache', 'data')).path,
      put(p.join(local, 'kingsoft', 'wps', 'cache', 'http', 'data')).path,
      put(p.join(roaming, '360se6', 'User Data', 'Default', 'Cache', 'data'))
          .path,
      put(
        p.join(
          local,
          'Tencent',
          'QQBrowser',
          'User Data',
          'Default',
          'Code Cache',
          'data',
        ),
      ).path,
      put(p.join(roaming, 'Tencent', 'QQBrowser', 'webkit_cache', 'data')).path,
    ];
    final protected = [
      put(p.join(roaming, 'Code', 'User', 'settings.json')),
      put(p.join(local, 'kingsoft', 'wps', 'backup', 'document.docx')),
      put(p.join(roaming, '360se6', 'User Data', 'Default', 'Login Data')),
      put(
        p.join(roaming, '360se6', 'User Data', 'Default', 'Network', 'Cookies'),
      ),
      put(p.join(roaming, 'Tencent', 'WeChat', 'FileStorage', 'work.docx')),
      put(
        p.join(local, 'Vendor', 'Deep', 'More', 'Nested', 'Cache', 'ignored'),
      ),
      put(p.join(local, 'Program', 'node_modules', 'Cache', 'dependency')),
    ];
    final service = scanner();
    final result = await service.scanAll();
    expect(files(result), unorderedEquals(found));
    final items = result.values.expand((c) => c.items);
    expect(
      items
          .where((i) => i.category == CleanCategory.nvidiaCache)
          .every((i) => !i.selected),
      isTrue,
    );
    expect(
      items
          .where((i) => i.category != CleanCategory.nvidiaCache)
          .every((i) => i.selected),
      isTrue,
    );
    expect(protected.every((f) => f.existsSync()), isTrue);
    expect(files(result).length, files(result).toSet().length);
  });

  test(
    'new rules still respect whitelist, file operability and cancellation',
    () async {
      final root = p.join(environment['LOCALAPPDATA']!, 'DingDing', 'Cache');
      final allowed = put(p.join(root, 'good'));
      final denied = put(p.join(root, 'busy'));
      final protected = put(p.join(root, 'protected', 'file'));
      final whitelist = WhitelistService(
        storageDirectory: p.join(fixture.path, 'Protection'),
      );
      await whitelist.add(protected.parent.path);
      final service = scanner(denied: {denied.path})..whitelist = whitelist;
      expect(files(await service.scanAll()), [allowed.path]);
      service.cancellation = CleanCancellation()..cancel();
      expect(await service.scanAll(), isEmpty);
      expect(denied.readAsStringSync(), 'data');
      expect(protected.readAsStringSync(), 'data');
    },
  );

  test(
    'small and empty downloads appear with exact unselected snapshots',
    () async {
      final small = put(p.join(environment['DOWNLOADS']!, 'notes.txt'));
      final empty = put(
        p.join(environment['DOWNLOADS']!, 'empty.txt'),
        content: '',
      );
      final nested = put(
        p.join(environment['DOWNLOADS']!, 'Folder', 'small.zip'),
      );
      final result = await scanner().scanAll(
        categories: {CleanCategory.downloads},
      );
      expect(
        files(result),
        unorderedEquals([small.path, empty.path, nested.path]),
      );
      expect(
        result.values.expand((c) => c.items).every((i) => !i.selected),
        isTrue,
      );
      expect(
        result[CleanCategory.downloads]!.items.every(
          (i) => i.fileSignatures!.isNotEmpty,
        ),
        isTrue,
      );
    },
  );

  test('browser profiles discover custom downloads while rejecting broad roots and broken metadata', () async {
    final root = p.join(
      environment['LOCALAPPDATA']!,
      'Google',
      'Chrome',
      'User Data',
    );
    final custom = p.join(fixture.path, 'Custom downloads');
    final file = put(p.join(custom, 'readme.txt'));
    put(
      p.join(root, 'Default', 'Preferences'),
      content: jsonEncode({
        'download': {'default_directory': custom},
      }),
    );
    put(p.join(root, 'Profile 1', 'Preferences'), content: '{invalid');
    put(
      p.join(root, 'Profile 2', 'Preferences'),
      content: jsonEncode({
        'download': {'default_directory': environment['USERPROFILE']},
      }),
    );
    put(
      p.join(root, 'Profile 3', 'Preferences'),
      content: jsonEncode({
        'download': {'default_directory': environment['SystemRoot']},
      }),
    );
    put(
      p.join(root, 'Profile 4', 'Preferences'),
      content: jsonEncode({
        'download': {
          'default_directory': p.join(environment['ProgramFiles']!, 'App'),
        },
      }),
    );
    put(
      p.join(root, 'Profile 5', 'Preferences'),
      content: jsonEncode({
        'download': {'default_directory': custom.toUpperCase()},
      }),
    );
    final result = await scanner().scanAll(
      categories: {CleanCategory.downloads},
    );
    expect(files(result), [file.path]);
    expect(result[CleanCategory.downloads]!.items.single.selected, isFalse);
    expect(
      await readDownloadPreferences(p.join(root, 'Profile 1', 'Missing')),
      isNull,
    );
    final large = put(
      p.join(root, 'large'),
      content: 'x' * (2 * 1024 * 1024 + 1),
    );
    expect(await readDownloadPreferences(large.path), isNull);
  });

  test('manager packages are individual snapshots for accurate type and age filtering', () async {
    final root = p.join(
      environment['LOCALAPPDATA']!,
      'Tencent',
      'QQPCMgr',
      'Download',
    );
    final package = put(p.join(root, 'editor.msi'), age: 40);
    final archive = put(p.join(root, 'media.zip'), age: 1);
    final settings = put(p.join(root, 'settings.ini'));
    final incomplete = put(p.join(root, 'editor.msi.download'));
    final result = await scanner().scanAll(
      categories: {CleanCategory.downloads},
    );
    final items = result[CleanCategory.downloads]!.items;
    expect(files(result), unorderedEquals([package.path, archive.path]));
    expect(items, hasLength(2));
    expect(items.every((i) => i.fileCount == 1 && !i.selected), isTrue);
    expect(
      items.singleWhere((i) => i.path == package.path).reviewedModified!,
      package.statSync().modified,
    );
    expect(items.map((i) => i.appName).toSet(), {'腾讯电脑管家'});
    expect(settings.existsSync() && incomplete.existsSync(), isTrue);
  });

  test('system additions and old logs exclude runtime components and personal data', () async {
    final local = environment['LOCALAPPDATA']!,
        roaming = environment['APPDATA']!,
        windows = environment['SystemRoot']!;
    final icon = put(p.join(local, 'IconCache.db'));
    final font = put(p.join(local, 'GDIPFONTCACHEV1.DAT'));
    final netLog = put(
      p.join(windows, 'Microsoft.NET', 'Framework64', 'v4', 'build.log'),
    );
    final tencentLog = put(p.join(roaming, 'Tencent', 'Logs', 'old.log'));
    final iis = put(
      p.join(fixture.path, 'inetpub', 'logs', 'LogFiles', 'W3SVC1', 'old.log'),
      age: 40,
    );
    final excluded = [
      put(p.join(windows, 'Microsoft.NET', 'Framework64', 'v4', 'runtime.dll')),
      put(p.join(windows, 'assembly', 'NativeImages_v4', 'assembly.ni.dll')),
      put(p.join(roaming, 'Tencent', 'Logs', 'new.log'), age: 1),
      put(p.join(roaming, 'Tencent', 'Logs', 'important.db')),
      put(p.join(roaming, 'Tencent', 'WeChat', 'Logs', 'chat.log')),
      put(
        p.join(
          fixture.path,
          'inetpub',
          'logs',
          'LogFiles',
          'W3SVC1',
          'recent.log',
        ),
        age: 10,
      ),
    ];
    final result = await scanner().scanAll(
      categories: {CleanCategory.systemCache, CleanCategory.systemLogs},
    );
    expect(
      files(result),
      unorderedEquals([
        icon.path,
        font.path,
        netLog.path,
        tencentLog.path,
        iis.path,
      ]),
    );
    expect(
      result.values.expand((c) => c.items).every((i) => i.selected),
      isTrue,
    );
    expect(excluded.every((f) => f.existsSync()), isTrue);
    final fast = await scanner().scanAll();
    expect(fast.containsKey(CleanCategory.systemLogs), isFalse);
    expect(files(fast), unorderedEquals([icon.path, font.path]));
  });
  test('Thunder settings decode Unicode paths without accessing the registry', () async {
    if (!Platform.isWindows) return;
    final script = put(
      p.join(fixture.path, 'settings.ps1'),
      content: '\ufeff$downloadSettingsScript',
    );
    final ini = put(
      p.join(fixture.path, 'settings.ini'),
      content: '\ufeff[Other]\nDefaultPath=C:\\Ignored\n[PrivateSpace]\nDefaultPath="D:\\下载文件\\临时 包"\n',
    );
    String quote(String value) => value.replaceAll("'", "''");
    final command =
        "[Console]::OutputEncoding=[Text.Encoding]::UTF8;"
        "\$t=\$null;\$e=\$null;"
        "\$a=[Management.Automation.Language.Parser]::ParseFile('${quote(script.path)}',[ref]\$t,[ref]\$e);"
        "if(\$e.Count){throw 'Invalid script'};"
        "\$f=\$a.Find({param(\$n) \$n -is [Management.Automation.Language.FunctionDefinitionAst] -and \$n.Name -eq 'Read-TaskDefault'},\$true);"
        ". ([scriptblock]::Create(\$f.Extent.Text));"
        "\$rows=@(Read-TaskDefault '${quote(ini.path)}');ConvertTo-Json -InputObject \$rows -Compress";
    final result = await Process.run(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-Command', command],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(jsonDecode('${result.stdout}'), [
      {'Source': '迅雷下载', 'Path': r'D:\下载文件\临时 包', 'PackagesOnly': false},
    ]);
  });
}
