import 'dart:io';
import 'dart:isolate';

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

/// 从可执行文件/图标串中提取 exe 路径（去掉 ",0" 等图标索引）
String? extractExecutablePath(String? raw) {
  if (raw == null) return null;
  var s = raw.trim();
  if (s.isEmpty) return null;
  if (s.startsWith('"')) {
    final end = s.indexOf('"', 1);
    if (end > 0) s = s.substring(1, end);
  } else {
    final exeIdx = s.toLowerCase().indexOf('.exe');
    if (exeIdx > 0) {
      s = s.substring(0, exeIdx + 4).trim();
    } else {
      final comma = s.indexOf(',');
      if (comma > 0) s = s.substring(0, comma).trim();
    }
  }
  s = s.replaceAll('/', '\\');
  // 只接受绝对路径，避免 msiexec.exe 等相对名被解析成当前目录
  if (!RegExp(r'^[A-Za-z]:\\').hasMatch(s)) return null;
  return s;
}

/// 推断安装根目录：优先 InstallLocation，其次卸载/图标 exe 所在目录
String? resolveInstallRoot({
  String? installLocation,
  String? uninstallString,
  String? quietUninstallString,
  String? displayIcon,
}) {
  String? fromDir(String? raw) {
    if (raw == null) return null;
    final s = expandEnv(raw.trim().replaceAll('/', '\\')).trim();
    if (s.isEmpty) return null;
    if (!RegExp(r'^[A-Za-z]:\\').hasMatch(s)) return null;
    final cleaned = s.endsWith('\\') ? s.substring(0, s.length - 1) : s;
    return cleaned.isEmpty ? null : cleaned;
  }

  final location = fromDir(installLocation);
  if (location != null && Directory(location).existsSync()) return location;

  for (final raw in [displayIcon, uninstallString, quietUninstallString]) {
    final exe = extractExecutablePath(raw);
    if (exe == null) continue;
    final file = File(exe);
    final parent = fromDir(file.parent.path);
    if (parent == null || isDriveRoot(parent)) continue;
    if (file.existsSync() || Directory(parent).existsSync()) {
      return parent;
    }
  }

  // InstallLocation 不存在时仍返回规范化路径，交给测量阶段跳过
  return location;
}

/// 是否是盘符根目录（禁止对 C:\ 之类做全盘测量）
bool isDriveRoot(String path) {
  final s = path.trim().replaceAll('/', '\\');
  return RegExp(r'^[A-Za-z]:\\?$').hasMatch(s);
}

/// 递归累加目录下文件大小（跟随 junction 以外的目录；忽略失败项）
int measureDirectoryBytesSync(String path) {
  if (isDriveRoot(path)) return 0;
  var total = 0;
  final stack = <String>[path];
  var visited = 0;
  while (stack.isNotEmpty) {
    if (++visited > 200000) break;
    final current = stack.removeLast();
    List<FileSystemEntity> entities;
    try {
      entities = Directory(current).listSync(followLinks: false);
    } on FileSystemException {
      continue;
    } on Exception {
      continue;
    }
    for (final entity in entities) {
      if (entity is File) {
        try {
          total += entity.lengthSync();
        } on FileSystemException {
          /* skip unreadable file */
        }
      } else if (entity is Directory) {
        stack.add(entity.path);
      } else if (entity is Link) {
        // 不跟随符号链接，避免环
        continue;
      }
    }
  }
  return total;
}

/// 在后台 isolate 测量目录大小，避免卡住 UI
Future<int> measureDirectoryBytes(String path) {
  return Isolate.run(() => measureDirectoryBytesSync(path));
}

/// 后台批量测量多个目录，返回 path -> bytes（仅包含成功且 >0 的项）
Future<Map<String, int>> measureDirectories(List<String> paths) {
  return Isolate.run(() {
    final result = <String, int>{};
    for (final path in paths) {
      final bytes = measureDirectoryBytesSync(path);
      if (bytes > 0) result[path] = bytes;
    }
    return result;
  });
}
