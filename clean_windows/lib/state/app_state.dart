import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/clean_models.dart';
import '../models/scan_options.dart';
import '../models/installed_app.dart';
import '../services/app_icon_service.dart';
import '../services/clean_service.dart';
import '../services/disk_services.dart';
import '../services/module_cache.dart';
import '../services/registry_scan_service.dart';
import '../services/scan_service.dart';
import '../services/uninstall_service.dart';
import '../services/whitelist_service.dart';
import '../services/activity_service.dart';

/// 全局应用状态
class AppState extends ChangeNotifier {
  // Versioned because older snapshots do not contain file-level boundaries.
  static const _scanCacheKey = 'results_v6';
  AppState({
    bool scanOnStart = false,
    ScanService? scanService,
    CleanService? cleanService,
    UninstallService? uninstallService,
    RegistryScanService? registryService,
    WhitelistService? whitelistService,
    AppIconService? iconService,
    ModuleCache? scanCache,
    ModuleCache? preferencesCache,
    ActivityJournal? journal,
  }) : journal = journal ?? ActivityJournal(enabled: !debugSkipProcess),
       _forceScanOnStart = scanOnStart,
       _scanService = scanService ?? ScanService(),
       _cleanService = cleanService ?? CleanService(),
       _uninstallService = uninstallService ?? UninstallService(),
       _registryService = registryService ?? RegistryScanService(),
       _whitelist = whitelistService ?? WhitelistService(),
       _icons = iconService ?? AppIconService(),
       _scanCache = scanCache ?? AppCache.scan,
       _preferencesCache =
           preferencesCache ??
           ModuleCache(
             namespace: 'preferences',
             ttl: const Duration(days: 3650),
           ) {
    _scanService.whitelist = _whitelist;
    _cleanService.whitelist = _whitelist;
    _options = ScanOptions.fromJson(
      _preferencesCache.getMap('scan_options') ?? {},
    );
    _scanService.options = _options;
    if (!debugSkipProcess) {
      final cached = _scanCache.getList(_scanCacheKey);
      if (cached != null) _restoreScanCache(cached);
    }
  }

  final bool _forceScanOnStart;
  final ActivityJournal journal;
  bool _startupScanHandled = false;
  bool consumeStartupScanRequest() {
    if (_startupScanHandled || debugSkipProcess) return false;
    _startupScanHandled = true;
    return _forceScanOnStart || _options.autoScanOnStart;
  }

  final ScanService _scanService;
  final CleanService _cleanService;
  final UninstallService _uninstallService;
  final RegistryScanService _registryService;
  final WhitelistService _whitelist;
  final AppIconService _icons;
  final ModuleCache _scanCache;
  final ModuleCache _preferencesCache;
  late ScanOptions _options;
  ScanOptions get options => _options;
  String? _optionsSaveError;
  String? get optionsSaveError => _optionsSaveError;
  bool _savingOptions = false;
  bool get savingOptions => _savingOptions;
  Future<bool> updateOptions(ScanOptions value) async {
    if (_savingOptions) return false;
    final scanRulesChanged = !_options.hasSameScanRules(value);
    if (scanRulesChanged && (_scanning || _cleaning)) return false;
    final previous = _options;
    _savingOptions = true;
    _optionsSaveError = null;
    _options = value;
    notifyListeners();
    try {
      await _preferencesCache.setDurableAsync('scan_options', value.toJson());
    } catch (_) {
      _options = previous;
      _savingOptions = false;
      _optionsSaveError = '设置未能保存，请检查本地设置目录是否可写后重试';
      notifyListeners();
      return false;
    }
    _optionsSaveError = null;
    _scanService.options = value;
    if (scanRulesChanged) {
      _results.clear();
      await _scanCache.invalidateAsync(_scanCacheKey);
    }
    _savingOptions = false;
    notifyListeners();
    return true;
  }

  int _scanGeneration = 0;
  int get scanGeneration => _scanGeneration;

  /// 测试环境置 true，避免启动真实子进程
  @visibleForTesting
  static bool debugSkipProcess = false;

  WhitelistService get whitelist => _whitelist;
  AppIconService get iconService => _icons;

  // ---- 扫描 ----
  bool _scanning = false;
  String? _scanError;
  String? get scanError => _scanError;
  bool _cleaning = false;
  ScanProgress _progress = const ScanProgress();
  final Map<CleanCategory, ScanCategory> _results = {};
  DateTime? _lastScanAt;
  DateTime? _lastCleanAt;
  int _lastFreedBytes = 0;

  bool get scanning => _scanning;
  bool get cleaning => _cleaning;
  ScanProgress get progress => _progress;
  Map<CleanCategory, ScanCategory> get results => Map.unmodifiable(_results);
  DateTime? get lastScanAt => _lastScanAt;
  DateTime? get lastCleanAt => _lastCleanAt;
  int get lastFreedBytes => _lastFreedBytes;

  bool get hasResults => _results.isNotEmpty;

  int get totalFoundBytes =>
      _results.values.fold(0, (s, c) => s + c.totalSizeBytes);

  int get totalSelectedBytes =>
      _results.values.fold(0, (s, c) => s + c.selectedSizeBytes);

  int get totalSelectedCount =>
      _results.values.fold(0, (s, c) => s + c.selectedCount);

  List<ScanCategory> get categories =>
      _results.values.toList()
        ..sort((a, b) => b.totalSizeBytes.compareTo(a.totalSizeBytes));

  // ---- 卸载 ----
  bool _loadingApps = false;
  bool _installedAppsLoaded = false;
  DateTime? _appsUpdatedAt;
  List<InstalledApp> _installedApps = [];
  String _appFilter = '';

  bool get loadingApps => _loadingApps;
  bool get hasInstalledAppsSnapshot =>
      _installedAppsLoaded || _installedApps.isNotEmpty;
  List<InstalledApp> get installedApps {
    final q = _appFilter.trim().toLowerCase();
    if (q.isEmpty) return List.unmodifiable(_installedApps);
    return _installedApps
        .where(
          (a) =>
              a.displayName.toLowerCase().contains(q) ||
              (a.publisher?.toLowerCase().contains(q) ?? false),
        )
        .toList();
  }

  String get appFilter => _appFilter;

  set appFilter(String value) {
    _appFilter = value;
    notifyListeners();
  }

  // ---- 下载 ----
  final Set<String> _selectedDownloadIds = {};

  Set<String> get selectedDownloadIds => Set.unmodifiable(_selectedDownloadIds);

  void toggleDownloadSelection(String id) {
    if (_selectedDownloadIds.contains(id)) {
      _selectedDownloadIds.remove(id);
    } else {
      _selectedDownloadIds.add(id);
    }
    final cat = _results[CleanCategory.downloads];
    if (cat != null) {
      for (final item in cat.items) {
        item.selected = _selectedDownloadIds.contains(item.id);
      }
    }
    notifyListeners();
  }

  // ---- 操作 ----

  void cancelScan() {
    _scanService.cancellation?.cancel();
  }

  Future<void> scan({
    Set<CleanCategory>? categories,
    bool force = false,
  }) async {
    if (_scanning || _cleaning || _savingOptions) return;

    _scanGeneration++;
    _scanning = true;
    final cancellation = _scanService.cancellation = CleanCancellation();
    _scanError = null;
    _progress = ScanProgress(
      totalCategories: _scanService.categoriesForScan(categories).length,
      message: '准备扫描…',
    );
    notifyListeners();

    TaskBoard.instance.update('scan', '一键扫描', '准备扫描', cancel: cancelScan);

    try {
      if (force && categories == null) {
        _results.clear();
      }

      final results = await _scanService.scanAll(
        categories: categories,
        onProgress: (p) {
          _progress = p;
          TaskBoard.instance.update(
            'scan',
            '一键扫描',
            '${p.message}\n${p.currentPath}',
            cancel: cancelScan,
          );
          notifyListeners();
        },
        onCategoryDone: (result) {
          // 每完成一项立即写入并刷新 UI
          _results[result.category] = result;
          if (result.category == CleanCategory.downloads) {
            for (final item in result.items) {
              item.selected = _selectedDownloadIds.contains(item.id);
            }
          }
          final totalFound = _results.values.fold<int>(
            0,
            (s, c) => s + c.totalSizeBytes,
          );
          _progress = _progress.copyWith(foundBytes: totalFound);
          notifyListeners();
        },
      );

      // 收尾合并（保证完整）
      if (categories == null) {
        _results
          ..clear()
          ..addAll(results);
      } else {
        _results.addAll(results);
      }

      final dl = _results[CleanCategory.downloads];
      if (dl != null) {
        for (final item in dl.items) {
          item.selected = _selectedDownloadIds.contains(item.id);
        }
      }

      _lastScanAt = DateTime.now();
      if (cancellation.requested) _scanError = '扫描已取消，已核对结果保留，可继续查看或重新扫描';
      await _saveScanCache();
    } catch (_) {
      _scanError = _whitelist.readable
          ? '扫描未完整完成，已读取内容保留供查看，请重新扫描重试'
          : _whitelist.lastError;
      rethrow;
    } finally {
      _scanning = false;
      TaskBoard.instance.finish('scan');
      _progress = _progress.copyWith(
        message: cancellation.requested
            ? '扫描已取消'
            : _scanError == null
            ? '扫描完成'
            : '扫描未完成',
        currentPath: '',
      );
      notifyListeners();
    }
  }

  Future<void> _saveScanCache({bool writeAsync = false}) async {
    final payload = _results.entries
        .map(
          (e) => {
            'category': e.key.name,
            'error': e.value.error,
            'items': e.value.items
                .map(
                  (i) => {
                    'id': i.id,
                    'name': i.name,
                    'path': i.path,
                    'sizeBytes': i.sizeBytes,
                    'fileCount': i.fileCount,
                    'note': i.note,
                    'scannedFiles': i.scannedFiles,
                    'fileSignatures': i.fileSignatures,
                    'appName': i.appName,
                    'iconPath': i.iconPath,
                    'removeEmptyDirectory': i.removeEmptyDirectory,
                    'registryValueName': i.registryValueName,
                    'registryValueData': i.registryValueData,
                    'registryExecutable': i.registryExecutable,
                    'autoSelect':
                        automaticallySelectCleanupItem(i.category, i.id) &&
                        i.scannedFiles != null &&
                        i.scannedFiles!.isNotEmpty &&
                        i.scannedFiles!.every(isConservativeTemporaryFile),
                  },
                )
                .toList(),
          },
        )
        .toList();
    if (writeAsync) {
      await _scanCache.setAsync(_scanCacheKey, payload);
    } else {
      _scanCache.set(_scanCacheKey, payload);
    }
  }

  void _restoreScanCache(List<dynamic> raw) {
    _results.clear();
    for (final entry in raw) {
      if (entry is! Map) continue;
      final catName = entry['category']?.toString();
      final cat = CleanCategory.values
          .where((c) => c.name == catName)
          .firstOrNull;
      if (cat == null) continue;
      final items = <CleanItem>[];
      final rawItems = entry['items'];
      if (rawItems is List) {
        for (final ir in rawItems) {
          if (ir is! Map) continue;
          items.add(
            CleanItem(
              id: ir['id']?.toString() ?? '',
              name: ir['name']?.toString() ?? '',
              path: ir['path']?.toString() ?? '',
              sizeBytes: (ir['sizeBytes'] as num?)?.toInt() ?? 0,
              category: cat,
              fileCount: (ir['fileCount'] as num?)?.toInt() ?? 0,
              note: ir['note']?.toString(),
              scannedFiles: ir['scannedFiles'] is List
                  ? List<String>.unmodifiable(
                      (ir['scannedFiles'] as List).whereType<String>(),
                    )
                  : null,
              appName: ir['appName']?.toString(),
              fileSignatures: ir['fileSignatures'] is Map
                  ? Map<String, String>.from(ir['fileSignatures'] as Map)
                  : null,
              iconPath: ir['iconPath']?.toString(),
              removeEmptyDirectory: ir['removeEmptyDirectory'] == true,
              registryValueName: ir['registryValueName']?.toString(),
              registryValueData: ir['registryValueData']?.toString(),
              registryExecutable: ir['registryExecutable']?.toString(),
              selected:
                  ir['autoSelect'] == true &&
                  automaticallySelectCleanupItem(
                    cat,
                    ir['id']?.toString() ?? '',
                  ),
            ),
          );
        }
      }
      _results[cat] = ScanCategory(
        category: cat,
        items: items,
        scanDuration: Duration.zero,
        error: entry['error']?.toString(),
      );
    }
  }

  void toggleItem(CleanItem item) {
    item.selected = !item.selected;
    if (item.category == CleanCategory.downloads) {
      if (item.selected) {
        _selectedDownloadIds.add(item.id);
      } else {
        _selectedDownloadIds.remove(item.id);
      }
    }
    notifyListeners();
  }

  void toggleCategory(ScanCategory category, bool selected) {
    category.selectAll(selected);
    if (category.category == CleanCategory.downloads) {
      _selectedDownloadIds.clear();
      if (selected) {
        for (final item in category.items) {
          _selectedDownloadIds.add(item.id);
        }
      }
    }
    notifyListeners();
  }

  String? get whitelistError => _whitelist.lastError;
  Future<bool> _changeWhitelist(Future<void> Function() action) async {
    try {
      await action();
      notifyListeners();
      return true;
    } catch (_) {
      notifyListeners();
      return false;
    }
  }

  Future<bool> addToWhitelist(CleanItem item) async {
    if (!await _changeWhitelist(() => _whitelist.add(item.path))) return false;
    _results[item.category]?.items.removeWhere((e) => e.id == item.id);
    _scanCache.invalidate(_scanCacheKey);
    notifyListeners();
    return true;
  }

  Future<bool> addCategoryToWhitelist(ScanCategory category) async {
    if (!await _changeWhitelist(
      () => _whitelist.addAll(category.items.map((e) => e.path)),
    )) {
      return false;
    }
    category.items.clear();
    _scanCache.invalidate(_scanCacheKey);
    notifyListeners();
    return true;
  }

  Future<bool> removeFromWhitelist(String path) =>
      _changeWhitelist(() => _whitelist.remove(path));
  Future<bool> addManualWhitelist(String path) async {
    if (!await _changeWhitelist(() => _whitelist.add(path))) return false;
    _results.clear();
    _scanCache.invalidate(_scanCacheKey);
    notifyListeners();
    return true;
  }

  Future<bool> clearWhitelist() => _changeWhitelist(_whitelist.clear);

  CleanCancellation? _cleanCancellation;
  void cancelCleaning() {
    if (_cleaning) _cleanCancellation?.cancel();
  }

  void forgetMovedDownload(String id) {
    _results[CleanCategory.downloads]?.items.removeWhere(
      (item) => item.id == id,
    );
    _selectedDownloadIds.remove(id);
    unawaited(_saveScanCache(writeAsync: true));
    notifyListeners();
  }

  Future<CleanReport> cleanSelected({
    Set<CleanCategory>? categories,
    void Function(CleanItem item, String message, int done, int total)?
    onProgress,
  }) async {
    if (_cleaning || _scanning || _savingOptions) return CleanReport.empty();
    _cleaning = true;
    final cancellation = _cleanCancellation = CleanCancellation();
    TaskBoard.instance.update(
      'cleanup',
      '文件清理',
      '正在准备',
      cancel: cancelCleaning,
    );
    notifyListeners();

    try {
      final items = _results.values
          .where(
            (category) =>
                categories == null || categories.contains(category.category),
          )
          .expand((c) => c.items)
          .where((i) => i.selected)
          .toList();

      final report = await _cleanService.cleanItems(
        items,
        recycle: true,
        cancellation: cancellation,
        onItem: (item, message, done, total) {
          TaskBoard.instance.update(
            'cleanup',
            '文件清理',
            '$done / $total · $message',
            cancel: cancelCleaning,
          );
          onProgress?.call(item, message, done, total);
        },
      );
      journal.record(
        categories?.contains(CleanCategory.downloads) == true ? '下载管理' : '一键清理',
        report,
        names: items.map((item) => item.name).toList(),
      );
      if (!report.cancelled ||
          report.freedBytes > 0 ||
          report.deletedCount > 0) {
        _lastCleanAt = DateTime.now();
        _lastFreedBytes = report.freedBytes;
      }

      for (final category in _results.values) {
        category.items.removeWhere(
          (item) => report.completedItemIds.contains(item.id),
        );
      }
      _selectedDownloadIds.removeWhere(
        (id) => report.completedItemIds.contains(id),
      );
      await _saveScanCache(writeAsync: true);
      return report;
    } finally {
      _cleanCancellation = null;
      TaskBoard.instance.finish('cleanup');
      _cleaning = false;
      notifyListeners();
    }
  }

  Future<void> loadInstalledApps({bool force = false}) async {
    if (_loadingApps) return;
    if (!force &&
        _installedAppsLoaded &&
        _appsUpdatedAt != null &&
        DateTime.now().difference(_appsUpdatedAt!) <
            const Duration(minutes: 5)) {
      return;
    }
    _loadingApps = true;
    TaskBoard.instance.update('apps', '软件列表', '正在更新安装记录');
    notifyListeners();
    try {
      _installedApps = await _uninstallService.listInstalled(force: force);
      _installedAppsLoaded = true;
      _appsUpdatedAt = DateTime.now();
      unawaited(_loadIcons());
    } finally {
      _loadingApps = false;
      TaskBoard.instance.finish('apps');
      notifyListeners();
    }
  }

  Future<void> _loadIcons() async {
    for (final app in _installedApps) {
      if (app.iconPath != null) continue;
      final path = await _icons.resolveIcon(
        appName: app.displayName,
        installLocation: app.installLocation,
        uninstallString: app.uninstallString,
        displayIcon: app.displayIcon,
      );
      if (path != null) {
        app.iconPath = path;
        notifyListeners();
      }
    }
  }

  // ---- 注册表扫描（与页面生命周期解耦）----
  bool _registryScanning = false;
  List<RegistryIssue> _registryIssues = [];

  bool get registryScanning => _registryScanning;
  List<RegistryIssue> get registryIssues => List.unmodifiable(_registryIssues);
  List<RegistryCoverage> get registryCoverage =>
      List.unmodifiable(_registryService.coverage);
  List<String> get registryWarnings =>
      List.unmodifiable(_registryService.warnings);

  Future<void> scanRegistry({bool force = false}) async {
    if (_registryScanning) return;
    _registryScanning = true;
    TaskBoard.instance.update('registry', '注册表扫描', '正在读取可清理记录');
    notifyListeners();
    try {
      _registryIssues = (await _registryService.scan(force: force))
          .where((issue) => issue.canDelete)
          .toList();
    } finally {
      _registryScanning = false;
      TaskBoard.instance.finish('registry');
      notifyListeners();
    }
  }

  Future<bool> deleteRegistryIssue(RegistryIssue issue) async {
    final ok = await _registryService.deleteValue(issue);
    if (ok) {
      _registryIssues = _registryIssues.where((e) => e != issue).toList();
      notifyListeners();
    }
    return ok;
  }

  // ---- 大文件扫描（与页面生命周期解耦）----
  final List<FileEntry> _largeFiles = [];
  bool _largeScanning = false;
  String _largeMessage = '';
  CancelToken _largeCancel = CancelToken();

  List<FileEntry> get largeFiles => List.unmodifiable(_largeFiles);
  bool get largeScanning => _largeScanning;
  String get largeMessage => _largeMessage;

  Future<void> scanLargeFiles({
    required String root,
    required int minBytes,
    bool force = false,
  }) async {
    if (_largeScanning) return;
    _largeCancel = CancelToken();
    _largeScanning = true;
    _largeMessage = '准备扫描…';
    if (force) _largeFiles.clear();
    notifyListeners();

    final service = LargeFileService();
    if (!force) {
      final cached = service.loadCached(root, minBytes);
      if (cached.isNotEmpty) {
        _largeFiles
          ..clear()
          ..addAll(cached);
        _largeScanning = false;
        _largeMessage = '已从缓存加载 ${cached.length} 个文件';
        notifyListeners();
        return;
      }
    }

    final batch = <FileEntry>[];
    try {
      await for (final f in service.scanLargeFiles(
        root,
        minBytes: minBytes,
        cancel: _largeCancel,
        onProgress: (n, dir) {
          _largeMessage = '已发现 $n 个大文件\n$dir';
          notifyListeners();
        },
      )) {
        batch.add(f);
        if (batch.length >= 15 || _largeFiles.length + batch.length >= 500) {
          _largeFiles.addAll(batch);
          batch.clear();
          notifyListeners();
        }
        if (_largeFiles.length >= 500) {
          _largeCancel.cancel();
          break;
        }
      }
      if (batch.isNotEmpty) {
        _largeFiles.addAll(batch);
        batch.clear();
      }
      service.saveCached(root, minBytes, _largeFiles);
      _largeMessage = '共 ${_largeFiles.length} 个文件';
    } on Exception catch (_) {
      if (batch.isNotEmpty) _largeFiles.addAll(batch);
    } finally {
      _largeScanning = false;
      notifyListeners();
    }
  }

  void stopLargeFilesScan() {
    _largeCancel.cancel();
    _largeScanning = false;
    _largeMessage = '已停止';
    notifyListeners();
  }

  void toggleLargeFileSelected(FileEntry entry) {
    entry.selected = !entry.selected;
    notifyListeners();
  }

  Future<int> deleteSelectedLargeFiles() async {
    final service = LargeFileService()..whitelist = _whitelist;
    final targets = _largeFiles.where((f) => f.selected).toList();
    final report = await service.deleteReviewedFiles(targets);
    _largeFiles.removeWhere((f) => report.completedItemIds.contains(f.path));
    notifyListeners();
    return report.freedBytes;
  }

  Future<UninstallResult> uninstallApp(InstalledApp app) async {
    TaskBoard.instance.update('installer', '软件卸载', app.displayName);
    try {
      final result = await _uninstallService.uninstall(app);
      journal.record(
        '软件卸载',
        CleanReport(
          freedBytes: 0,
          deletedCount: result.success ? 1 : 0,
          skippedCount: 0,
          failedCount: result.status == UninstallStatus.failed ? 1 : 0,
          cancelled: result.status == UninstallStatus.cancelled,
          failures: result.success ? [] : [result.message],
        ),
        names: [app.displayName, result.message],
      );
      if (result.success) {
        _installedApps.removeWhere((entry) => entry.identity == app.identity);
        notifyListeners();
      }
      return result;
    } finally {
      TaskBoard.instance.finish('installer');
    }
  }

  /// C 盘剩余空间
  Future<({int total, int free})?> diskSpace(String letter) async {
    if (debugSkipProcess) return null;
    return DiskAnalysisService().driveSpace(letter);
  }

  Future<int> freeDiskBytes() async {
    if (debugSkipProcess) return 0;
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'(Get-PSDrive C).Free',
      ], stdoutEncoding: utf8);
      return int.tryParse(result.stdout.toString().trim()) ?? 0;
    } on Exception catch (_) {
      return 0;
    }
  }

  /// 复制文本到剪贴板
  Future<void> copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  /// 在资源管理器中打开
  Future<void> revealInExplorer(String path) async {
    final normalized = path.replaceAll('/', '\\');
    try {
      if (Directory(normalized).existsSync() || File(normalized).existsSync()) {
        await Process.run('explorer', [normalized]);
      } else {
        // 打开父目录
        final parent = normalized.contains('\\')
            ? normalized.substring(0, normalized.lastIndexOf('\\'))
            : normalized;
        await Process.run('explorer', [parent]);
      }
    } on Exception catch (_) {}
  }
}
