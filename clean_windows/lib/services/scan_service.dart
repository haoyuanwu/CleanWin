import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'cache_discovery.dart';
import 'file_safety.dart';
import 'file_operability.dart';

import '../models/clean_models.dart';
import '../models/scan_options.dart';
import 'app_icon_service.dart';
import 'process_utils.dart';
import 'registry_cache.dart';
import 'whitelist_service.dart';

/// 扫描服务：遍历各清理目标，统计体积
class ScanService {
  ScanService({
    Map<String, String>? environment,
    this.driveRoots,
    PowerShellRunner? powerShellRunner,
    Future<Set<String>> Function(List<String>)? operabilityProbe,
  }) : _environment = environment ?? Platform.environment,

       _runPowerShell = powerShellRunner ?? runPowerShell,
       _operabilityProbe = operabilityProbe ?? operableCleanupPaths;

  final List<String>? driveRoots;
  final PowerShellRunner _runPowerShell;
  final Future<Set<String>> Function(List<String>) _operabilityProbe;
  bool _oneClick = false;
  CleanCancellation? cancellation;
  void Function(int, int, String)? _onPermissionProgress;
  bool get _cancelled => cancellation?.requested ?? false;

  List<CleanCategory> categoriesForScan(Set<CleanCategory>? categories) => [
    for (final category in categories ?? oneClickScanCategories)
      if ((category != CleanCategory.browserCache ||
              options.cleanBrowserCache) &&
          (category != CleanCategory.nvidiaCache || options.cleanGpuCache))
        category,
  ];
  String get userHome => _environment['USERPROFILE'] ?? Directory.current.path;

  final Map<String, String> _environment;
  final Set<String> _scannedPaths = {};
  final Set<String> _scanIssues = {};
  void Function(String path)? _onScanPath;

  void _recordScanIssue(FileSystemException error) {
    if ({2, 3}.contains(error.osError?.errorCode)) return;
    _scanIssues.add(error.path ?? '未知路径');
  }

  String get localAppData =>
      _environment['LOCALAPPDATA'] ?? '$userHome\\AppData\\Local';
  String get roamingAppData =>
      _environment['APPDATA'] ?? '$userHome\\AppData\\Roaming';
  String get windowsDir => _environment['SystemRoot'] ?? r'C:\Windows';
  String get programData => _environment['ProgramData'] ?? r'C:\ProgramData';
  String get systemDriveRoot {
    final drive = _environment['SystemDrive'];
    if (drive == null) return p.rootPrefix(windowsDir);
    return p.isAbsolute(drive) ? drive : '$drive\\';
  }

  /// 可选白名单：命中则在扫描结果中过滤掉
  WhitelistService? whitelist;
  ScanOptions options = const ScanOptions();

  /// 扫描所有分类（可指定子集）
  Future<Map<CleanCategory, ScanCategory>> scanAll({
    Set<CleanCategory>? categories,
    void Function(ScanProgress progress)? onProgress,
    void Function(ScanCategory result)? onCategoryDone,
  }) async {
    if (whitelist?.readable == false) throw StateError(whitelist!.lastError!);
    _scannedPaths.clear();
    _oneClick = categories == null;
    // Specialized categories own their files before generic cache discovery.
    const order = [
      CleanCategory.memoryDumps,
      CleanCategory.nvidiaCache,
      CleanCategory.windowsUpdate,
      CleanCategory.systemCache,
      CleanCategory.browserCache,
      CleanCategory.appCache,
      CleanCategory.systemLogs,
      CleanCategory.recycleBin,
      CleanCategory.appLeftovers,
      CleanCategory.downloads,
      CleanCategory.registryJunk,
      CleanCategory.usageTraces,
      CleanCategory.softwareUsage,
    ];
    final targets = order
        .where(categoriesForScan(categories).contains)
        .toList();
    final results = <CleanCategory, ScanCategory>{};
    var completed = 0;
    var foundBytes = 0;
    ScanProgress? activeProgress;
    var latestPath = '';
    var emittedPath = '';
    final pathClock = Stopwatch()..start();

    void emitPath({bool force = false}) {
      if (activeProgress == null ||
          latestPath.isEmpty ||
          latestPath == emittedPath) {
        return;
      }
      // First path is immediate; subsequent updates are at most 10 per second.
      // Flush the final path before finishing even when a category is very fast.
      if (!force &&
          emittedPath.isNotEmpty &&
          pathClock.elapsedMilliseconds < 100) {
        return;
      }
      emittedPath = latestPath;
      pathClock.reset();
      onProgress?.call(activeProgress.copyWith(currentPath: latestPath));
    }

    _onScanPath = onProgress == null
        ? null
        : (path) {
            latestPath = path;
            emitPath();
          };
    try {
      for (final cat in targets) {
        if (_cancelled) break;
        latestPath = '';
        emittedPath = '';
        activeProgress = ScanProgress(
          currentCategory: cat,
          completedCategories: completed,
          totalCategories: targets.length,
          foundBytes: foundBytes,
          message: '正在扫描${cat.title}…',
        );
        onProgress?.call(activeProgress);

        final sw = Stopwatch()..start();
        ScanCategory result;
        try {
          result = await _scanCategory(cat);
          activeProgress = activeProgress.copyWith(
            message: '正在核对${cat.title}的可清理权限…',
          );
          onProgress?.call(activeProgress);
          _onPermissionProgress = (done, total, path) => onProgress?.call(
            activeProgress!.copyWith(
              message: '正在核对${cat.title}的可清理权限（$done / $total）',
              currentPath: path,
            ),
          );
          result = await _operableResult(result);
          _onPermissionProgress = null;
        } on Exception catch (e) {
          result = ScanCategory(
            category: cat,
            items: [],
            scanDuration: sw.elapsed,
            error: e.toString(),
          );
        }
        sw.stop();
        emitPath(force: true);
        activeProgress = null;
        final filtered = result.items
            .where((item) => !(whitelist?.isWhitelisted(item.path) ?? false))
            .toList();
        final filteredResult = ScanCategory(
          category: cat,
          items: filtered,
          scanDuration: sw.elapsed,
          error: result.error,
        );
        results[cat] = filteredResult;
        foundBytes += filteredResult.totalSizeBytes;
        completed++;
        onCategoryDone?.call(filteredResult);
        onProgress?.call(
          ScanProgress(
            currentCategory: cat,
            completedCategories: completed,
            totalCategories: targets.length,
            foundBytes: foundBytes,
            message: '已完成${cat.title}',
          ),
        );
      }
      onProgress?.call(
        ScanProgress(
          completedCategories: completed,
          totalCategories: targets.length,
          foundBytes: foundBytes,
          message: _cancelled ? '扫描已取消，已核对结果已保留' : '扫描完成',
        ),
      );
      return results;
    } finally {
      _onScanPath = null;
      _onPermissionProgress = null;
      pathClock.stop();
    }
  }

  Future<ScanCategory> _scanCategory(CleanCategory cat) async {
    _scanIssues.clear();
    final sw = Stopwatch()..start();
    List<CleanItem> items;
    switch (cat) {
      case CleanCategory.systemCache:
        items = await _scanSystemCache();
      case CleanCategory.browserCache:
        items = options.cleanBrowserCache ? await _scanBrowserCache() : [];
      case CleanCategory.appCache:
        items = await _scanAppCaches();
      case CleanCategory.systemLogs:
        items = await _scanSystemLogs();
      case CleanCategory.recycleBin:
        items = await _scanRecycleBin();
      case CleanCategory.nvidiaCache:
        items = options.cleanGpuCache ? await _scanNvidiaCache() : [];
      case CleanCategory.appLeftovers:
        items = await _scanAppLeftovers();
      case CleanCategory.downloads:
        items = await _scanDownloads();
      case CleanCategory.memoryDumps:
        items = await _scanMemoryDumps();
      case CleanCategory.windowsUpdate:
        items = await _scanWindowsUpdate();
      case CleanCategory.registryJunk:
        items = await _scanRegistryJunk();
      case CleanCategory.usageTraces:
        items = await _scanUsageTraces();
      case CleanCategory.softwareUsage:
        items = await _scanSoftwareUsage();
    }
    return ScanCategory(
      category: cat,
      items: items,
      scanDuration: sw.elapsed,
      error: _scanIssues.isEmpty
          ? null
          : '有 ${_scanIssues.length} 个位置无法完整读取，结果仅包含可访问的文件。'
                '\n${_scanIssues.take(5).join('\n')}',
    );
  }

  Future<ScanCategory> _operableResult(ScanCategory result) async {
    if (result.category == CleanCategory.registryJunk) return result;
    final candidates = <String>{
      for (final item in result.items) ...[
        if (item.removeEmptyDirectory) item.path,
        ...?item.scannedFiles,
      ],
    };
    final paths = candidates.toList();
    final allowed = <String>{};
    var checked = 0;
    for (var offset = 0; offset < paths.length; offset += 256) {
      if (_cancelled) break;
      final end = (offset + 256).clamp(0, paths.length);
      allowed.addAll(await _operabilityProbe(paths.sublist(offset, end)));
      checked = end;
      _onPermissionProgress?.call(end, paths.length, paths[end - 1]);
    }
    final items = <CleanItem>[];
    for (final item in result.items) {
      if (item.removeEmptyDirectory) {
        if (allowed.contains(item.path)) items.add(item);
        continue;
      }
      final files = (item.scannedFiles ?? const <String>[])
          .where(allowed.contains)
          .toList();
      if (files.isEmpty) continue;
      final signatures = <String, String>{
        for (final path in files)
          if (item.fileSignatures?[path] != null)
            path: item.fileSignatures![path]!,
      };
      final bytes = signatures.values.fold<int>(
        0,
        (sum, value) => sum + (int.tryParse(value.split(':').first) ?? 0),
      );
      items.add(
        CleanItem(
          id: item.id,
          name: item.name,
          path: item.path,
          sizeBytes: bytes,
          category: item.category,
          fileCount: files.length,
          scannedFiles: List.unmodifiable(files),
          fileSignatures: Map.unmodifiable(signatures),
          selected: item.selected,
          note: item.note,
          appName: item.appName,
          iconPath: item.iconPath,
        ),
      );
    }
    final notices = [
      if (result.error?.isNotEmpty == true) result.error!,
      if (checked > allowed.length)
        '已跳过 ${checked - allowed.length} 个当前不可操作的文件（可能被占用、只读或权限不足）。',
    ];
    return ScanCategory(
      category: result.category,
      items: items,
      scanDuration: result.scanDuration,
      error: notices.isEmpty ? null : notices.join('\n'),
    );
  }

  // ---------- 各分类扫描 ----------

  /// Discover disposable caches across vendors, nested profiles and Store apps.
  Future<List<CleanItem>> _scanAppCaches() async {
    final items = <CleanItem>[];
    if (_oneClick && !options.deepScan) {
      for (final relative in [
        'Code/Cache',
        'Discord/Cache',
        'Slack/Cache',
        'Spotify/Cache',
        'Microsoft/Teams/Cache',
      ]) {
        if (_cancelled) break;
        for (final root in [localAppData, roamingAppData]) {
          final path = p.joinAll([root, ...relative.split('/')]);
          final item = await _dirItem(
            id: 'appcache_$path',
            name: relative.split('/').first,
            path: path,
            category: CleanCategory.appCache,
            note: '已知软件缓存；清理后可能需要重新加载',
          );
          if (item.fileCount > 0) items.add(item);
        }
      }
      return items;
    }
    final iconService = AppIconService();
    for (final root in {
      localAppData,
      roamingAppData,
      p.join(p.dirname(localAppData), 'LocalLow'),
      if (!_oneClick) programData,
    }) {
      await for (final cache in discoverCaches(
        Directory(root),
        maxDepth: _oneClick ? 6 : 8,
        onError: _recordScanIssue,
        onPath: _onScanPath,
        cancelled: () => _cancelled,
        exclude: (path) =>
            _excluded(path, CleanCategory.appCache) ||
            _ownedBySpecializedScanner(path),
      )) {
        final relative = p.relative(cache.path, from: root);
        final parts = p.split(relative);
        final appName =
            parts.first.toLowerCase() == 'packages' && parts.length > 1
            ? parts[1]
            : parts.first;
        final item = await _dirItem(
          id: 'appcache_${cache.path}',
          name: appName,
          path: cache.path,
          category: CleanCategory.appCache,
          note: relative,
          appName: appName,
        );
        if (item.fileCount == 0) continue;
        if (!_oneClick) {
          item.iconPath = await iconService.resolveIcon(
            appName: appName,
            installLocation: cache.path,
          );
        }
        items.add(item);
      }
    }
    items.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    return items;
  }

  Future<List<CleanItem>> _scanSystemCache() async {
    final items = <CleanItem>[];

    // 用户临时目录
    items.add(
      await _dirItem(
        id: 'user_temp',
        name: '用户临时文件',
        path: '$localAppData\\Temp',
        category: CleanCategory.systemCache,
        minAge: const Duration(days: 7),
        note: '仅推荐七天前、当前可删除且未被占用的临时文件',
      ),
    );

    // Windows 临时目录
    items.add(
      await _dirItem(
        id: 'windows_temp',
        name: 'Windows 临时文件',
        path: '$windowsDir\\Temp',
        category: CleanCategory.systemCache,
        minAge: const Duration(days: 1),
      ),
    );

    // Prefetch
    if (options.cleanPrefetch) {
      items.add(
        await _dirItem(
          id: 'prefetch',
          name: 'Prefetch 预读取',
          path: '$windowsDir\\Prefetch',
          category: CleanCategory.systemCache,
        ),
      );
    }

    // 缩略图 / 图标缓存
    items.add(
      await _dirItem(
        id: 'thumbnails',
        name: '缩略图缓存',
        path: '$localAppData\\Microsoft\\Windows\\Explorer',
        category: CleanCategory.systemCache,
        nameFilter: (name) {
          final n = name.toLowerCase();
          return n.startsWith('thumbcache_');
        },
      ),
    );

    // 系统图标缓存
    items.add(
      await _dirItem(
        id: 'sys_icon_cache',
        name: '系统图标缓存',
        path: '$localAppData\\Microsoft\\Windows\\Explorer',
        category: CleanCategory.systemCache,
        nameFilter: (name) => name.toLowerCase().startsWith('iconcache'),
      ),
    );

    // 字体缓存
    items.add(
      await _dirItem(
        id: 'font_cache',
        name: '字体缓存',
        path: '$windowsDir\\ServiceProfiles\\LocalService\\AppData\\Local',
        category: CleanCategory.systemCache,
        nameFilter: (name) {
          final n = name.toLowerCase();
          return n.startsWith('fontcache') ||
              n.endsWith('.dat') && n.contains('font');
        },
      ),
    );
    items.add(
      await _dirItem(
        id: 'font_cache_user',
        name: '字体缓存（用户）',
        path: '$localAppData\\Microsoft\\Windows\\FontCache',
        category: CleanCategory.systemCache,
      ),
    );
    items.add(
      await _dirItem(
        id: 'font_cache_sys',
        name: '系统字体缓存',
        path: '$windowsDir\\System32',
        category: CleanCategory.systemCache,
        recursive: false,
        nameFilter: (name) => name.toLowerCase() == 'fntcache.dat',
      ),
    );

    // 证书 / 加密相关缓存（CryptnetUrlCache 等，安全可清）
    items.add(
      await _dirItem(
        id: 'cryptnet',
        name: 'Internet 临时缓存（IE）',
        path: '$localAppData\\Microsoft\\Windows\\INetCache\\IE',
        category: CleanCategory.systemCache,
      ),
    );
    items.add(
      await _dirItem(
        id: 'cryptnet_low',
        name: 'Internet 临时缓存（低完整性）',
        path: '$localAppData\\Microsoft\\Windows\\INetCache\\Low',
        category: CleanCategory.systemCache,
      ),
    );
    items.add(
      await _dirItem(
        id: 'cert_enrollment',
        name: '证书注册缓存',
        path: '$localAppData\\Microsoft\\CryptnetUrlCache',
        category: CleanCategory.systemCache,
      ),
    );

    // Windows 错误报告
    items.add(
      await _dirItem(
        id: 'wer_local',
        name: 'Windows 错误报告（用户）',
        path: '$localAppData\\Microsoft\\Windows\\WER',
        category: CleanCategory.systemCache,
      ),
    );
    items.add(
      await _dirItem(
        id: 'wer_programdata',
        name: 'Windows 错误报告（系统）',
        path: '$programData\\Microsoft\\Windows\\WER',
        category: CleanCategory.systemCache,
      ),
    );

    // Environment temp may be redirected outside AppData.
    for (final temp in {_environment['TEMP'], _environment['TMP']}) {
      if (temp == null || temp.isEmpty) continue;
      if ([
        userHome,
        localAppData,
        roamingAppData,
        windowsDir,
        programData,
      ].any((root) => p.equals(temp, root) || p.isWithin(temp, root))) {
        _scanIssues.add('临时目录配置指向过大的范围，已跳过：$temp');
        continue;
      }
      items.add(
        await _dirItem(
          id: 'temp_$temp',
          name: '环境变量临时目录',
          path: temp,
          category: CleanCategory.systemCache,
          minAge: const Duration(days: 7),
        ),
      );
    }
    for (final (name, path) in <(String, String)>[
      (
        'Internet 临时缓存',
        p.join(localAppData, 'Microsoft', 'Windows', 'INetCache'),
      ),
      (
        '证书下载缓存（LocalLow）',
        p.join(
          p.dirname(localAppData),
          'LocalLow',
          'Microsoft',
          'CryptnetUrlCache',
        ),
      ),
      (
        '系统证书下载缓存',
        p.join(
          windowsDir,
          'System32',
          'config',
          'systemprofile',
          'AppData',
          'LocalLow',
          'Microsoft',
          'CryptnetUrlCache',
        ),
      ),
    ]) {
      items.add(
        await _dirItem(
          id: 'system_$path',
          name: name,
          path: path,
          category: CleanCategory.systemCache,
        ),
      );
    }
    return items.where((i) => i.sizeBytes > 0 || i.fileCount > 0).toList();
  }

  List<(String, String)> get _browserRoots => [
    ('Chrome', p.join(localAppData, 'Google', 'Chrome', 'User Data')),
    ('Chrome Beta', p.join(localAppData, 'Google', 'Chrome Beta', 'User Data')),
    ('Chrome Dev', p.join(localAppData, 'Google', 'Chrome Dev', 'User Data')),
    (
      'Chrome Canary',
      p.join(localAppData, 'Google', 'Chrome SxS', 'User Data'),
    ),
    ('Edge', p.join(localAppData, 'Microsoft', 'Edge', 'User Data')),
    ('Edge Beta', p.join(localAppData, 'Microsoft', 'Edge Beta', 'User Data')),
    ('Edge Dev', p.join(localAppData, 'Microsoft', 'Edge Dev', 'User Data')),
    ('Edge Canary', p.join(localAppData, 'Microsoft', 'Edge SxS', 'User Data')),
    ('Firefox', p.join(localAppData, 'Mozilla', 'Firefox', 'Profiles')),
    (
      'Brave',
      p.join(localAppData, 'BraveSoftware', 'Brave-Browser', 'User Data'),
    ),
    ('Chromium', p.join(localAppData, 'Chromium', 'User Data')),
    ('Vivaldi', p.join(localAppData, 'Vivaldi', 'User Data')),
    ('Opera', p.join(localAppData, 'Opera Software')),
    ('Opera', p.join(roamingAppData, 'Opera Software')),
  ];

  bool _ownedBySpecializedScanner(String path) {
    final roots = [
      ..._browserRoots.map((entry) => entry.$2),
      p.join(localAppData, 'NVIDIA'),
      p.join(localAppData, 'NVIDIA Corporation'),
      p.join(programData, 'NVIDIA Corporation', 'NV_Cache'),
      p.join(localAppData, 'AMD'),
      p.join(localAppData, 'D3DSCache'),
      p.join(localAppData, 'Microsoft', 'Windows'),
      p.join(programData, 'Microsoft', 'Windows', 'WER'),
      p.join(programData, 'Microsoft', 'Windows', 'DeliveryOptimization'),
    ];
    return roots.any((root) => p.equals(root, path) || p.isWithin(root, path));
  }

  Future<List<CleanItem>> _scanBrowserCache() async {
    final items = <CleanItem>[];
    for (final (name, root) in _browserRoots) {
      items.addAll(
        await _browserProfiles(
          root: root,
          browserName: name,
          cacheDirs: name == 'Firefox' ? const ['thumbnails'] : const [],
          category: CleanCategory.browserCache,
        ),
      );
    }
    return items.where((item) => item.fileCount > 0).toList();
  }

  Future<List<CleanItem>> _browserProfiles({
    required String root,
    required String browserName,
    required List<String> cacheDirs,
    required CleanCategory category,
  }) async {
    final items = <CleanItem>[];
    await for (final cache in discoverCaches(
      Directory(root),
      maxDepth: _oneClick ? 6 : 8,
      onError: _recordScanIssue,
      onPath: _onScanPath,
      cancelled: () => _cancelled,
      cacheNames: {
        ...disposableCacheNames,
        ...cacheDirs.map((name) => p.basename(name).toLowerCase()),
      },
      exclude: (path) => whitelist?.isWhitelisted(path) ?? false,
    )) {
      final relative = p.relative(cache.path, from: root);
      final item = await _dirItem(
        id: '${browserName.toLowerCase()}_${cache.path}',
        name: '$browserName · $relative',
        path: cache.path,
        category: category,
      );
      if (item.fileCount > 0) items.add(item);
    }
    return items;
  }

  Future<List<CleanItem>> _scanSystemLogs() async {
    final items = <CleanItem>[];

    items.add(
      await _dirItem(
        id: 'cbs_log',
        name: 'CBS 组件日志',
        path: '$windowsDir\\Logs\\CBS',
        category: CleanCategory.systemLogs,
        nameFilter: (n) =>
            n.toLowerCase().endsWith('.log') ||
            n.toLowerCase().endsWith('.cab'),
      ),
    );

    items.add(
      await _dirItem(
        id: 'dism_log',
        name: 'DISM 日志',
        path: '$windowsDir\\Logs\\DISM',
        category: CleanCategory.systemLogs,
      ),
    );

    items.add(
      await _dirItem(
        id: 'panther',
        name: '安装日志 Panther',
        path: '$windowsDir\\Panther',
        category: CleanCategory.systemLogs,
      ),
    );

    // 更多系统日志
    items.add(
      await _dirItem(
        id: 'setup_logs',
        name: 'Setup 安装日志',
        path: '$windowsDir\\Logs\\MoSetup',
        category: CleanCategory.systemLogs,
      ),
    );
    items.add(
      await _dirItem(
        id: 'waas_mediacache',
        name: '更新媒体缓存日志',
        path: '$windowsDir\\Logs\\waasmedic',
        category: CleanCategory.systemLogs,
      ),
    );
    items.add(
      await _dirItem(
        id: 'do_logs',
        name: '传递优化日志',
        path:
            '$windowsDir\\ServiceProfiles\\NetworkService\\AppData\\Local\\Microsoft\\Windows\\DeliveryOptimization\\Logs',
        category: CleanCategory.systemLogs,
      ),
    );
    items.add(
      await _dirItem(
        id: 'actsetup',
        name: '升级操作日志',
        path: p.join(systemDriveRoot, r'$WINDOWS.~BT', 'Sources', 'Panther'),
        category: CleanCategory.systemLogs,
      ),
    );
    items.add(
      await _dirItem(
        id: 'wpr',
        name: '性能跟踪日志',
        path: '$localAppData\\WPR',
        category: CleanCategory.systemLogs,
      ),
    );
    items.add(
      await _dirItem(
        id: 'windows_territories',
        name: '诊断归档日志',
        path: '$windowsDir\\Logs\\WindowsBackup',
        category: CleanCategory.systemLogs,
      ),
    );
    items.add(
      await _dirItem(
        id: 'srt',
        name: '启动修复日志',
        path: '$windowsDir\\System32\\LogFiles\\Srt',
        category: CleanCategory.systemLogs,
      ),
    );

    items.add(
      await _dirItem(
        id: 'windows_logs',
        name: 'Windows 日志目录',
        path: '$windowsDir\\Logs',
        category: CleanCategory.systemLogs,
      ),
    );
    return items.where((i) => i.sizeBytes > 0).toList();
  }

  Future<List<CleanItem>> _scanRecycleBin() async {
    var sid = _environment['USER_SID'];
    if (sid == null) {
      final result = await _runPowerShell(
        '[Security.Principal.WindowsIdentity]::GetCurrent().User.Value',
        const Duration(seconds: 10),
      );
      if (!result.success) {
        throw FileSystemException('无法获取回收站用户', result.stderr);
      }
      sid = result.stdout.trim();
    }
    if (!RegExp(r'^S-1-\d+(?:-\d+)+$').hasMatch(sid)) {
      throw const FileSystemException('无法确认当前用户的回收站');
    }
    var drives = driveRoots;
    if (drives == null) {
      final result = await _runPowerShell(r'''
$ErrorActionPreference = 'Stop'
$roots = @([IO.DriveInfo]::GetDrives() | Where-Object {
  $_.IsReady -and ($_.DriveType -eq 'Fixed' -or $_.DriveType -eq 'Removable')
} | ForEach-Object { $_.RootDirectory.FullName })
ConvertTo-Json -InputObject @($roots) -Compress
''', const Duration(seconds: 10));
      if (!result.success) {
        throw FileSystemException('无法枚举回收站磁盘', result.stderr);
      }
      // String arrays are decoded separately from record-based JSON helpers.
      drives = _decodeDriveRoots(result.stdout);
    }
    final items = <CleanItem>[];
    for (final root in drives) {
      final item = await _dirItem(
        id: 'recycle_$root',
        name: '回收站 · $root',
        path: p.join(root, r'$Recycle.Bin', sid),
        category: CleanCategory.recycleBin,
        note: '仅清理当前用户在此磁盘已扫描的回收站文件',
      );
      if (item.fileCount > 0) items.add(item);
    }
    return items;
  }

  Future<List<CleanItem>> _scanNvidiaCache() async {
    final items = <CleanItem>[];
    final targets = <(String, String)>[
      ('DirectX 着色器缓存', p.join(localAppData, 'D3DSCache')),
      ('NVIDIA DirectX', p.join(localAppData, 'NVIDIA', 'DXCache')),
      ('NVIDIA OpenGL', p.join(localAppData, 'NVIDIA', 'GLCache')),
      ('NVIDIA Compute', p.join(localAppData, 'NVIDIA', 'ComputeCache')),
      (
        'NVIDIA NV_Cache',
        p.join(localAppData, 'NVIDIA Corporation', 'NV_Cache'),
      ),
      ('NVIDIA 系统缓存', p.join(programData, 'NVIDIA Corporation', 'NV_Cache')),
      ('AMD DirectX', p.join(localAppData, 'AMD', 'DxCache')),
      ('AMD DXC', p.join(localAppData, 'AMD', 'DxcCache')),
      ('AMD OpenGL', p.join(localAppData, 'AMD', 'GLCache')),
      ('AMD Vulkan', p.join(localAppData, 'AMD', 'VkCache')),
    ];
    final seen = <String>{};
    for (final (id, path) in targets) {
      if (seen.contains(path.toLowerCase())) continue;
      seen.add(path.toLowerCase());
      items.add(
        await _dirItem(
          id: id,
          name: id,
          path: path,
          category: CleanCategory.nvidiaCache,
        ),
      );
    }
    return items.where((i) => i.sizeBytes > 0 || i.fileCount > 0).toList();
  }

  Future<List<CleanItem>> _scanAppLeftovers() async {
    // A directory name does not prove that an application was uninstalled.
    // Only offer verified empty install directories, with manual selection.
    final items = <CleanItem>[];
    for (final root in {
      _environment['ProgramFiles'],
      _environment['ProgramFiles(x86)'],
      p.join(localAppData, 'Programs'),
    }.whereType<String>()) {
      for (final child in await _children(Directory(root))) {
        if (child is! Directory ||
            (whitelist?.isWhitelisted(child.path) ?? false)) {
          continue;
        }
        try {
          _onScanPath?.call(child.path);
          if (!(await child.list(followLinks: false).isEmpty)) continue;
          items.add(
            CleanItem(
              id: 'empty_${child.path}',
              name: '空安装目录 · ${p.basename(child.path)}',
              path: child.path,
              sizeBytes: 0,
              category: CleanCategory.appLeftovers,
              selected: false,
              removeEmptyDirectory: true,
              note: '仅删除空目录；目录出现新文件时跳过。不能仅凭目录名判断卸载残留。',
            ),
          );
        } on FileSystemException catch (error) {
          _recordScanIssue(error);
        }
      }
    }
    return items;
  }

  Future<List<CleanItem>> _scanDownloads() async {
    final items = <CleanItem>[];
    final dir = Directory(await _downloadsPath());

    final children = await _children(dir);

    for (final child in children) {
      if (child is File) {
        final item = await _fileItem(
          id: 'dl_${child.path}',
          name: p.basename(child.path),
          path: child.path,
          category: CleanCategory.downloads,
        );
        if (item.sizeBytes >= 10 * 1024 * 1024) items.add(item);
      } else if (child is Directory) {
        final item = await _dirItem(
          id: 'dl_dir_${child.path}',
          name: '${child.path.split(Platform.pathSeparator).last}/',
          path: child.path,
          category: CleanCategory.downloads,
        );
        if (item.sizeBytes >= 10 * 1024 * 1024) {
          item.selected = false;
          items.add(item);
        }
      }
    }

    items.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    return items;
  }

  Future<List<CleanItem>> _scanMemoryDumps() async {
    final items = <CleanItem>[];
    items.add(
      await _dirItem(
        id: 'minidump',
        name: 'Minidump 小型转储',
        path: '$windowsDir\\Minidump',
        category: CleanCategory.memoryDumps,
      ),
    );
    items.add(
      await _fileItem(
        id: 'memory_dmp',
        name: 'MEMORY.DMP 完整转储',
        path: '$windowsDir\\MEMORY.DMP',
        category: CleanCategory.memoryDumps,
      ),
    );
    items.add(
      await _dirItem(
        id: 'livekernel',
        name: 'LiveKernelReports',
        path: '$windowsDir\\LiveKernelReports',
        category: CleanCategory.memoryDumps,
      ),
    );
    items.add(
      await _dirItem(
        id: 'crashdumps_user',
        name: '用户崩溃转储',
        path: '$localAppData\\CrashDumps',
        category: CleanCategory.memoryDumps,
      ),
    );
    for (final root in [
      p.join(localAppData, 'Microsoft', 'Windows', 'WER'),
      p.join(programData, 'Microsoft', 'Windows', 'WER'),
    ]) {
      items.add(
        await _dirItem(
          id: 'wer_dump_$root',
          name: '错误报告中的转储文件',
          path: root,
          category: CleanCategory.memoryDumps,
        ),
      );
    }
    return items.where((i) => i.fileCount > 0).toList();
  }

  Future<List<CleanItem>> _scanWindowsUpdate() async {
    final items = <CleanItem>[];
    items.add(
      await _dirItem(
        id: 'wu_download',
        name: 'Windows Update 下载缓存',
        path: '$windowsDir\\SoftwareDistribution\\Download',
        category: CleanCategory.windowsUpdate,
      ),
    );
    items.add(
      await _dirItem(
        id: 'wu_delivery',
        name: '传递优化缓存',
        path:
            '$windowsDir\\ServiceProfiles\\NetworkService\\AppData\\Local\\Microsoft\\Windows\\DeliveryOptimization\\Cache',
        category: CleanCategory.windowsUpdate,
      ),
    );
    items.add(
      await _dirItem(
        id: 'wu_delivery_programdata',
        name: '传递优化缓存（系统数据）',
        path: p.join(
          programData,
          'Microsoft',
          'Windows',
          'DeliveryOptimization',
          'Cache',
        ),
        category: CleanCategory.windowsUpdate,
      ),
    );
    return items.where((i) => i.fileCount > 0).toList();
  }

  /// 注册表垃圾：无效 MUI 缓存、失效 App Paths、空的无用键（安全预览，删除走 PowerShell）
  Future<List<CleanItem>> _scanRegistryJunk() async {
    final result = await _runPowerShell(
      RegistryCache.scanScript,
      const Duration(seconds: 25),
    );
    if (!result.success) throw FileSystemException('注册表扫描未完成', result.stderr);
    if (!(ProcessUtils.debugSkip && result.stdout.trim().isEmpty)) {
      final decoded = jsonDecode(result.stdout);
      if (decoded is! List && decoded is! Map) {
        throw const FormatException('注册表扫描返回的结果无效');
      }
    }
    final items = <CleanItem>[];
    for (final row in ProcessUtils.parseJsonList(result.stdout)) {
      final path = row['Path']?.toString() ?? '';
      _onScanPath?.call(path);
      final name = row['ValueName']?.toString();
      final item = CleanItem(
        id: 'registry_${path}_$name',
        name: row['Name']?.toString() ?? '失效程序记录',
        path: path,
        category: CleanCategory.registryJunk,
        sizeBytes: 0,
        fileCount: 1,
        selected: false,
        note: row['Kind']?.toString(),
        registryValueName: name,
        registryValueData: row['Value']?.toString(),
        registryExecutable: row['Executable']?.toString(),
      );
      if (RegistryCache.accepts(item)) items.add(item);
    }
    return items;
  }

  /// Windows 使用痕迹：最近文件、跳转列表、缩略图之外的痕迹
  Future<List<CleanItem>> _scanUsageTraces() async {
    final items = <CleanItem>[];

    items.add(
      await _dirItem(
        id: 'recent_files',
        name: '最近使用的文件',
        path: '$roamingAppData\\Microsoft\\Windows\\Recent',
        category: CleanCategory.usageTraces,
        note: '快捷方式',
        recursive: false,
        nameFilter: (name) => p.extension(name).toLowerCase() == '.lnk',
      ),
    );

    items.add(
      await _dirItem(
        id: 'recent_automatic',
        name: '跳转列表（自动）',
        path:
            '$roamingAppData\\Microsoft\\Windows\\Recent\\AutomaticDestinations',
        category: CleanCategory.usageTraces,
        nameFilter: (name) =>
            name.toLowerCase().endsWith('.automaticdestinations-ms'),
      ),
    );

    items.add(
      await _dirItem(
        id: 'recent_custom',
        name: '跳转列表（自定义）',
        path: '$roamingAppData\\Microsoft\\Windows\\Recent\\CustomDestinations',
        category: CleanCategory.usageTraces,
        nameFilter: (name) =>
            name.toLowerCase().endsWith('.customdestinations-ms'),
      ),
    );

    // 按 .lnk 过滤 Recent 根目录体积已含在 dir 递归里
    return items.where((i) => i.sizeBytes > 0 || i.fileCount > 0).toList();
  }

  /// Only recognized log files and recent-file shortcuts, never sessions or history databases.
  Future<List<CleanItem>> _scanSoftwareUsage() async {
    final items = <CleanItem>[];
    for (final root in {
      localAppData,
      roamingAppData,
      p.join(p.dirname(localAppData), 'LocalLow'),
    }) {
      await for (final dir in discoverCaches(
        Directory(root),
        cacheNames: const {'logs', 'log', 'recent', 'recent files', 'traces'},
        includePackageTemp: false,
        pruneCaches: true,
        exclude: (path) => whitelist?.isWhitelisted(path) ?? false,
        onError: _recordScanIssue,
        onPath: _onScanPath,
        cancelled: () => _cancelled,
      )) {
        final relative = p.relative(dir.path, from: root);
        final item = await _dirItem(
          id: 'usage_${dir.path}',
          name: relative,
          path: dir.path,
          category: CleanCategory.softwareUsage,
          nameFilter: (name) => {
            '.log',
            '.old',
            '.etl',
            '.lnk',
          }.contains(p.extension(name).toLowerCase()),
          note: '软件日志或最近文件快捷方式，不含会话、聊天记录和历史数据库',
        );
        if (item.fileCount > 0) items.add(item);
      }
    }
    items.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    return items;
  }

  Future<List<FileSystemEntity>> _children(Directory dir) async {
    _onScanPath?.call(dir.path);
    final children = <FileSystemEntity>[];
    try {
      if (FileSystemEntity.typeSync(dir.path, followLinks: false) ==
          FileSystemEntityType.link) {
        return children;
      }
      await for (final child in dir.list(followLinks: false)) {
        _onScanPath?.call(child.path);
        children.add(child);
      }
    } on FileSystemException catch (error) {
      _recordScanIssue(error);
    }
    return children;
  }
  // ---------- 通用工具 ----------

  List<String> _decodeDriveRoots(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! List) throw const FormatException('磁盘枚举结果无效');
    return decoded.whereType<String>().where(p.isAbsolute).toSet().toList();
  }

  Future<String> _downloadsPath() async {
    final configured = _environment['DOWNLOADS'];
    if (configured != null && p.isAbsolute(configured)) return configured;
    final result = await _runPowerShell(r'''
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$shell = New-Object -ComObject Shell.Application
$folder = $shell.NameSpace('shell:Downloads')
if ($null -eq $folder) { throw '无法定位下载文件夹' }
$folder.Self.Path
''', const Duration(seconds: 10));
    final path = result.stdout.trim();
    if (result.success && p.isAbsolute(path)) return path;
    if (!result.success) _scanIssues.add('下载目录定位失败，使用用户默认目录');
    return p.join(userHome, 'Downloads');
  }

  bool _excluded(String path, CleanCategory category) {
    if (_cancelled) return true;
    if (category != CleanCategory.downloads &&
        category != CleanCategory.recycleBin &&
        protectedCachePath(path)) {
      return true;
    }
    if (whitelist?.isWhitelisted(path) ?? false) return true;
    if (_oneClick) {
      for (final root in [
        windowsDir,
        programData,
        _environment['ProgramFiles'],
        _environment['ProgramFiles(x86)'],
      ].whereType<String>()) {
        if (p.equals(root, path) || p.isWithin(root, path)) return true;
      }
    }
    if (category == CleanCategory.downloads ||
        category == CleanCategory.recycleBin) {
      return false;
    }
    for (final name in [
      'Documents',
      'Pictures',
      'Desktop',
      'Videos',
      'Music',
      'Downloads',
    ]) {
      final root = p.join(userHome, name);
      if (p.equals(path, root) || p.isWithin(root, path)) return true;
    }
    return false;
  }

  Future<CleanItem> _dirItem({
    required String id,
    required String name,
    required String path,
    required CleanCategory category,
    bool Function(String name)? nameFilter,
    String? note,
    String? appName,
    Duration? minAge,
    bool recursive = true,
  }) async {
    final dir = Directory(path);
    if (_excluded(path, category)) {
      return CleanItem(
        id: id,
        name: name,
        path: path,
        sizeBytes: 0,
        category: category,
        note: '已排除',
        scannedFiles: const [],
        appName: appName,
      );
    }

    var size = 0;
    var count = 0;
    final scannedFiles = <String>[];
    final signatures = <String, String>{};
    await for (final entity in walkFiles(
      dir,
      onError: _recordScanIssue,
      onPath: _onScanPath,
      cancelled: () => _cancelled,
      exclude: (path) => _excluded(path, category),
      recursive: recursive,
    )) {
      final file = entity as File;
      if (nameFilter != null && !nameFilter(p.basename(file.path))) continue;
      if (_oneClick &&
          automaticallySelectCleanupItem(category, id) &&
          !isConservativeTemporaryFile(file.path)) {
        continue;
      }
      final extension = p.extension(file.path).toLowerCase();
      if (category == CleanCategory.memoryDumps &&
          !{'.dmp', '.mdmp', '.hdmp'}.contains(extension)) {
        continue;
      }
      if (category == CleanCategory.systemLogs &&
          !{'.log', '.etl', '.old', '.cab'}.contains(extension)) {
        continue;
      }
      final key = p.normalize(p.absolute(file.path)).toLowerCase();
      if (_scannedPaths.contains(key)) continue;
      try {
        final stat = await file.stat();
        final age =
            minAge ??
            (category == CleanCategory.systemLogs
                ? const Duration(days: 7)
                : null);
        if (age != null && DateTime.now().difference(stat.modified) < age) {
          continue;
        }
        final bytes = stat.size;
        _scannedPaths.add(key);
        scannedFiles.add(file.path);
        signatures[file.path] = fileSignature(stat);
        size += bytes;
        count++;
      } on FileSystemException catch (error) {
        _recordScanIssue(error);
        // A locked or vanished file does not abort the directory.
      }
    }
    return CleanItem(
      id: id,
      name: name,
      path: path,
      sizeBytes: size,
      category: category,
      fileCount: count,
      scannedFiles: List.unmodifiable(scannedFiles),
      fileSignatures: Map.unmodifiable(signatures),
      selected:
          automaticallySelectCleanupItem(category, id) &&
          scannedFiles.isNotEmpty &&
          scannedFiles.every(isConservativeTemporaryFile),
      note: note,
      appName: appName,
    );
  }

  Future<CleanItem> _fileItem({
    required String id,
    required String name,
    required String path,
    required CleanCategory category,
    String? note,
  }) async {
    _onScanPath?.call(path);
    final file = File(path);
    if (_excluded(path, category) || hasLinkedAncestor(path)) {
      return CleanItem(
        id: id,
        name: name,
        path: path,
        sizeBytes: 0,
        category: category,
        note: '已排除或路径包含链接',
        scannedFiles: const [],
      );
    }
    int size = 0;
    String? signature;
    final key = p.normalize(p.absolute(path)).toLowerCase();
    if (!_scannedPaths.contains(key)) {
      try {
        final stat = await file.stat();
        size = stat.size;
        signature = fileSignature(stat);
        _scannedPaths.add(key);
      } on FileSystemException catch (error) {
        _recordScanIssue(error);
      }
    }
    return CleanItem(
      id: id,
      name: name,
      path: path,
      sizeBytes: size,
      category: category,
      fileCount: size > 0 ? 1 : 0,
      selected: category.defaultSelected,
      scannedFiles: _scannedPaths.contains(key) && size > 0 ? [path] : const [],
      fileSignatures: signature == null ? null : {path: signature},
      note: note,
    );
  }
}
