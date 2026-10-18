class ScanOptions {
  const ScanOptions({
    this.cleanPrefetch = false,
    this.cleanBrowserCache = true,
    this.cleanGpuCache = true,
    this.confirmBeforeClean = true,
    this.autoScanOnStart = false,
    this.deepScan = false,
  });

  final bool cleanPrefetch;
  final bool cleanBrowserCache;
  final bool cleanGpuCache;
  final bool confirmBeforeClean;
  final bool autoScanOnStart;
  final bool deepScan;

  bool hasSameScanRules(ScanOptions other) =>
      deepScan == other.deepScan &&
      cleanPrefetch == other.cleanPrefetch &&
      cleanBrowserCache == other.cleanBrowserCache &&
      cleanGpuCache == other.cleanGpuCache;

  ScanOptions copyWith({
    bool? cleanPrefetch,
    bool? cleanBrowserCache,
    bool? cleanGpuCache,
    bool? confirmBeforeClean,
    bool? autoScanOnStart,
    bool? deepScan,
  }) => ScanOptions(
    cleanPrefetch: cleanPrefetch ?? this.cleanPrefetch,
    cleanBrowserCache: cleanBrowserCache ?? this.cleanBrowserCache,
    cleanGpuCache: cleanGpuCache ?? this.cleanGpuCache,
    confirmBeforeClean: confirmBeforeClean ?? this.confirmBeforeClean,
    autoScanOnStart: autoScanOnStart ?? this.autoScanOnStart,
    deepScan: deepScan ?? this.deepScan,
  );

  Map<String, dynamic> toJson() => {
    'cleanPrefetch': cleanPrefetch,
    'cleanBrowserCache': cleanBrowserCache,
    'cleanGpuCache': cleanGpuCache,
    'confirmBeforeClean': confirmBeforeClean,
    'autoScanOnStart': autoScanOnStart,
    'deepScan': deepScan,
  };

  factory ScanOptions.fromJson(Map<String, dynamic> json) => ScanOptions(
    cleanPrefetch: json['cleanPrefetch'] == true,
    cleanBrowserCache: json['cleanBrowserCache'] != false,
    cleanGpuCache: json['cleanGpuCache'] != false,
    confirmBeforeClean: json['confirmBeforeClean'] != false,
    autoScanOnStart: json['autoScanOnStart'] == true,
    deepScan: json['deepScan'] == true,
  );
}
