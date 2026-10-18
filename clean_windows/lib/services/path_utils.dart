import 'dart:io';

/// 字节格式化
String formatBytes(int bytes, {int decimals = 1}) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final digits = size >= 100 || unit == 0 ? 0 : decimals;
  return '${size.toStringAsFixed(digits)} ${units[unit]}';
}

/// 解析环境变量路径（如 %LOCALAPPDATA%）
String expandEnv(String path) {
  final home = Platform.environment['USERPROFILE'] ?? '';
  final local = Platform.environment['LOCALAPPDATA'] ?? '$home\\AppData\\Local';
  final roaming = Platform.environment['APPDATA'] ?? '$home\\AppData\\Roaming';
  final temp = Platform.environment['TEMP'] ?? '$local\\Temp';
  final public = Platform.environment['PUBLIC'] ?? 'C:\\Users\\Public';
  final systemRoot = Platform.environment['SystemRoot'] ?? 'C:\\Windows';

  return path
      .replaceAll('%USERPROFILE%', home)
      .replaceAll('%LOCALAPPDATA%', local)
      .replaceAll('%APPDATA%', roaming)
      .replaceAll('%TEMP%', temp)
      .replaceAll('%TMP%', temp)
      .replaceAll('%PUBLIC%', public)
      .replaceAll('%SystemRoot%', systemRoot)
      .replaceAll('%windir%', systemRoot)
      .replaceAll(
        RegExp(r'%USERNAME%'),
        Platform.environment['USERNAME'] ?? '',
      );
}

/// 获取用户主目录
String get userHome =>
    Platform.environment['USERPROFILE'] ?? Directory.current.path;

/// 获取本地应用数据目录
String get localAppData =>
    Platform.environment['LOCALAPPDATA'] ?? '$userHome\\AppData\\Local';

/// 获取漫游应用数据目录
String get roamingAppData =>
    Platform.environment['APPDATA'] ?? '$userHome\\AppData\\Roaming';

/// Windows 目录
String get windowsDir => Platform.environment['SystemRoot'] ?? 'C:\\Windows';
