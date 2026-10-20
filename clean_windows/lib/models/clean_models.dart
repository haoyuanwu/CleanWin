/// 清理分类
enum CleanCategory {
  systemCache('系统缓存', '用户临时文件与重建类缓存（后者需手动选择）', 'assets/icons/system.svg'),
  browserCache(
    '浏览器缓存',
    'Chrome / Edge / Firefox 缓存',
    'assets/icons/browser.svg',
  ),
  appCache('软件缓存', '已安装软件在 AppData 中的缓存', 'assets/icons/system.svg'),
  systemLogs('系统日志', '日志文件、错误报告、更新缓存', 'assets/icons/logs.svg'),
  recycleBin('回收站', '清空回收站中的文件', 'assets/icons/recycle.svg'),
  nvidiaCache('显卡缓存', 'DirectX、NVIDIA、AMD 着色器缓存', 'assets/icons/gpu.svg'),
  appLeftovers('应用残留', '安装目录中的空目录（需手动确认）', 'assets/icons/leftover.svg'),
  downloads('下载文件夹', '系统下载与软件管家的下载包（需手动勾选）', 'assets/icons/download.svg'),
  memoryDumps('内存转储', '蓝屏转储与 Minidump', 'assets/icons/dump.svg'),
  windowsUpdate('更新缓存', 'Windows Update 下载缓存', 'assets/icons/update.svg'),
  registryJunk(
    '注册表垃圾',
    '失效程序的 MUI 缓存与 App Paths 值（需手动确认）',
    'assets/icons/logs.svg',
  ),
  usageTraces('使用痕迹', '最近使用、跳转列表等 Windows 痕迹', 'assets/icons/system.svg'),
  softwareUsage('软件使用记录', '软件日志与最近文件快捷方式（需手动确认）', 'assets/icons/system.svg');

  const CleanCategory(this.title, this.subtitle, this.icon);

  final String title;
  final String subtitle;
  final String icon;

  /// Only the system temporary-file category has any automatic selections;
  /// the scanner further restricts it to aged, operable temporary-file items.
  bool get defaultSelected => this == CleanCategory.systemCache;

  /// 是否需要管理员权限
  bool get needsAdmin =>
      this == CleanCategory.windowsUpdate || this == CleanCategory.systemLogs;
}

/// Personal downloads and recycle-bin contents are reviewed manually.
const oneClickScanCategories = {
  CleanCategory.nvidiaCache,
  CleanCategory.systemCache,
  CleanCategory.browserCache,
  CleanCategory.appCache,
  CleanCategory.recycleBin,
  CleanCategory.downloads,
};

bool automaticallySelectCleanupItem(CleanCategory category, String id) =>
    category == CleanCategory.systemCache &&
    (id == 'user_temp' || id.startsWith('temp_'));

bool isConservativeTemporaryFile(String path) =>
    RegExp(r'\.(tmp|temp)$', caseSensitive: false).hasMatch(path);

/// 单个可清理条目
class CleanItem {
  CleanItem({
    required this.id,
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.category,
    this.fileCount = 0,
    this.selected = true,
    this.note,
    this.iconPath,
    this.appName,
    this.scannedFiles,
    this.fileSignatures,
    this.removeEmptyDirectory = false,
    this.registryValueName,
    this.registryValueData,
    this.registryExecutable,
    this.requiredKeeperPath,
    this.requiredKeeperSignature,
  });

  final String id;
  final String name;
  final String path;
  int sizeBytes;
  final CleanCategory category;
  int fileCount;
  bool selected;
  final String? note;

  /// 软件 logo 本地 PNG（软件缓存项）
  String? iconPath;

  /// 所属软件名
  final String? appName;

  /// Exact files included in a directory scan, including filters/exclusions.
  /// Null is reserved for legacy items and special actions such as recycle bin.
  final List<String>? scannedFiles;

  /// File size and modification time, used to skip files changed after preview.
  final Map<String, String>? fileSignatures;
  final bool removeEmptyDirectory;
  final String? registryValueName;
  final String? registryValueData;
  final String? registryExecutable;
  final String? requiredKeeperPath;
  final String? requiredKeeperSignature;

  DateTime? get reviewedModified {
    final signature = fileSignatures?[path];
    final micros = signature == null
        ? null
        : int.tryParse(signature.split(':').last);
    return micros == null ? null : DateTime.fromMicrosecondsSinceEpoch(micros);
  }

  String get cleanupImpact => switch (category) {
    CleanCategory.systemCache =>
      automaticallySelectCleanupItem(category, id)
          ? '仅处理扫描时已确认可操作的旧临时文件；正在使用或已变化的文件会跳过。'
          : '可重建的系统缓存；清理后首次打开可能稍慢，建议按需选择。',
    CleanCategory.browserCache => '网页资源缓存；清理后部分页面需要重新下载资源，不处理密码、书签和 Cookie。',
    CleanCategory.appCache => '软件缓存候选；清理后可能需要重新加载或下载资源，请按需选择。',
    CleanCategory.nvidiaCache => '着色器缓存；清理后游戏或图形软件可能重新编译并暂时卡顿，默认不勾选。',
    CleanCategory.downloads => '个人文件，默认不勾选；所选文件移入回收站，可在回收站恢复。',
    CleanCategory.recycleBin => '清空后无法从回收站恢复，请先检查其中内容。',
    _ => category.subtitle,
  };
}

/// 一个分类的扫描结果
class ScanCategory {
  ScanCategory({
    required this.category,
    required this.items,
    required this.scanDuration,
    this.error,
  });

  final CleanCategory category;
  final List<CleanItem> items;
  final Duration scanDuration;
  final String? error;

  int get totalSizeBytes => items.fold(0, (sum, item) => sum + item.sizeBytes);

  int get selectedSizeBytes => items
      .where((i) => i.selected)
      .fold(0, (sum, item) => sum + item.sizeBytes);

  int get selectedCount => items.where((i) => i.selected).length;

  bool get isEmpty => items.isEmpty;

  void selectAll(bool selected) {
    for (final item in items) {
      item.selected = selected;
    }
  }
}

/// 单次清理使用的取消信号。
class CleanCancellation {
  bool _requested = false;
  final _listeners = <void Function()>[];
  bool get requested => _requested;
  void Function() listen(void Function() callback) {
    _listeners.add(callback);
    if (_requested) callback();
    return () => _listeners.remove(callback);
  }

  void cancel() {
    if (_requested) return;
    _requested = true;
    for (final callback in [..._listeners]) {
      callback();
    }
  }
}

/// 清理结果
class CleanReport {
  CleanReport({
    required this.freedBytes,
    required this.deletedCount,
    required this.skippedCount,
    required this.failedCount,
    this.failures = const [],
    this.completedItemIds = const {},
    this.cancelled = false,
    this.recycledBytes = 0,
  });

  final int freedBytes;
  final int deletedCount;
  final int skippedCount;
  final int failedCount;
  final List<String> failures;
  final Set<String> completedItemIds;
  final bool cancelled;
  final int recycledBytes;

  static CleanReport empty() => CleanReport(
    freedBytes: 0,
    deletedCount: 0,
    skippedCount: 0,
    failedCount: 0,
  );
}

/// 扫描进度
class ScanProgress {
  const ScanProgress({
    this.currentCategory,
    this.completedCategories = 0,
    this.totalCategories = 0,
    this.foundBytes = 0,
    this.message = '',
    this.currentPath = '',
  });

  final CleanCategory? currentCategory;
  final int completedCategories;
  final int totalCategories;
  final int foundBytes;
  final String message;
  final String currentPath;

  double get ratio =>
      totalCategories == 0 ? 0 : completedCategories / totalCategories;

  ScanProgress copyWith({
    CleanCategory? currentCategory,
    int? completedCategories,
    int? totalCategories,
    int? foundBytes,
    String? message,
    String? currentPath,
  }) {
    return ScanProgress(
      currentCategory: currentCategory ?? this.currentCategory,
      completedCategories: completedCategories ?? this.completedCategories,
      totalCategories: totalCategories ?? this.totalCategories,
      foundBytes: foundBytes ?? this.foundBytes,
      message: message ?? this.message,
      currentPath: currentPath ?? this.currentPath,
    );
  }
}
