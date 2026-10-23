/// 已安装软件
class InstalledApp {
  InstalledApp({
    required this.displayName,
    this.displayVersion,
    this.publisher,
    this.installLocation,
    this.uninstallString,
    this.quietUninstallString,
    this.estimatedSizeKb,
    this.registryKey,
    this.displayIcon,
    this.isSystemComponent = false,
  });

  final String displayName;
  final String? displayVersion;
  final String? publisher;
  final String? installLocation;
  final String? uninstallString;
  final String? quietUninstallString;
  final int? estimatedSizeKb;
  final String? registryKey;
  final String? displayIcon;
  final bool isSystemComponent;

  /// 本地缓存的 PNG 图标路径（运行时填充）
  String? iconPath;

  /// 安装目录实测大小（字节，运行时填充）；注册表未报告时使用
  int? measuredSizeBytes;

  /// 注册表是否直接报告了有效大小
  bool get hasRegistrySize => (estimatedSizeKb ?? 0) > 0;

  /// 对外展示/排序使用的大小（字节）：优先注册表，其次实测
  int get estimatedSizeBytes {
    if (hasRegistrySize) return estimatedSizeKb! * 1024;
    return measuredSizeBytes ?? 0;
  }

  /// 当前大小是否只是安装目录估算
  bool get sizeIsMeasured => !hasRegistrySize && (measuredSizeBytes ?? 0) > 0;

  bool get hasSize => estimatedSizeBytes > 0;

  String get identity =>
      (registryKey?.isNotEmpty == true
              ? registryKey!
              : '$displayName|$displayVersion|$installLocation|$uninstallString')
          .toLowerCase();

  bool get canUninstall =>
      (uninstallString != null && uninstallString!.trim().isNotEmpty) ||
      (quietUninstallString != null && quietUninstallString!.trim().isNotEmpty);

  factory InstalledApp.fromJson(Map<String, dynamic> json) {
    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      return int.tryParse(v.toString());
    }

    String? parseStr(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    return InstalledApp(
      displayName: parseStr(json['DisplayName']) ?? '未知软件',
      displayVersion: parseStr(json['DisplayVersion']),
      publisher: parseStr(json['Publisher']),
      installLocation: parseStr(json['InstallLocation']),
      uninstallString: parseStr(json['UninstallString']),
      quietUninstallString: parseStr(json['QuietUninstallString']),
      estimatedSizeKb: parseInt(json['EstimatedSize']),
      registryKey: parseStr(json['RegistryKey']),
      displayIcon: parseStr(json['DisplayIcon']),
      isSystemComponent: parseStr(json['SystemComponent']) == '1',
    );
  }
}
