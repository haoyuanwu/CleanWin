import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

enum CleanupBlockReason {
  inUse('正在占用', '退出相关软件后重扫'),
  metadataDenied('文件属性核对受限', '扫描后访问条件已变化，可重新扫描核对'),
  deleteDenied('无删除权限', '可统计，但当前身份不能删除；提权也不保证能处理服务专用目录'),
  readOnly('只读文件', '保留只读保护，不自动修改属性'),
  systemProtected('系统属性保护', '保留系统文件，不强行处理'),
  linked('链接或重解析点', '保留链接边界，不跟随到其他位置'),
  offline('离线文件', '不触发下载或自动取回'),
  disappeared('扫描后已消失', '临时文件可能已被软件自行删除'),
  pathTooLong('路径过长', '检查实际路径长度'),
  unavailable('未通过可清理检查', '查看错误码后重试');

  const CleanupBlockReason(this.label, this.action);
  final String label;
  final String action;
}

class CleanupPathBlock {
  const CleanupPathBlock(this.reason, {this.windowsError});
  final CleanupBlockReason reason;
  final int? windowsError;
}

class FileOperabilityReport {
  const FileOperabilityReport({required this.allowed, this.blocked = const {}});
  final Set<String> allowed;
  final Map<String, CleanupPathBlock> blocked;
}

CleanupPathBlock cleanupBlockFromWindowsError(
  int code, {
  bool forDeletion = true,
}) => CleanupPathBlock(switch (code) {
  32 || 33 => CleanupBlockReason.inUse,
  5 =>
    forDeletion
        ? CleanupBlockReason.deleteDenied
        : CleanupBlockReason.metadataDenied,
  2 || 3 => CleanupBlockReason.disappeared,
  206 => CleanupBlockReason.pathTooLong,
  _ => CleanupBlockReason.unavailable,
}, windowsError: code);

/// Compatibility API. The detailed probe preserves the exact reason for each rejection.
Future<Set<String>> operableCleanupPaths(List<String> paths) async =>
    (await inspectCleanupPaths(paths)).allowed;

/// This is a delete-capability check, not a readability check. Never mutates files.
Future<FileOperabilityReport> inspectCleanupPaths(List<String> paths) async {
  if (paths.isEmpty) return const FileOperabilityReport(allowed: {});
  if (!Platform.isWindows) {
    return FileOperabilityReport(
      allowed: {},
      blocked: {
        for (final path in paths)
          path: const CleanupPathBlock(CleanupBlockReason.unavailable),
      },
    );
  }
  return Isolate.run(() => _probeWindows(paths));
}

FileOperabilityReport _probeWindows(List<String> paths) {
  final kernel = DynamicLibrary.open('kernel32.dll');
  final allocate = kernel
      .lookupFunction<
        Pointer<Void> Function(Uint32, IntPtr),
        Pointer<Void> Function(int, int)
      >('LocalAlloc');
  final release = kernel
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >('LocalFree');
  final attributes = kernel
      .lookupFunction<
        Uint32 Function(Pointer<Uint16>),
        int Function(Pointer<Uint16>)
      >('GetFileAttributesW');
  final open = kernel
      .lookupFunction<
        IntPtr Function(
          Pointer<Uint16>,
          Uint32,
          Uint32,
          Pointer<Void>,
          Uint32,
          Uint32,
          IntPtr,
        ),
        int Function(Pointer<Uint16>, int, int, Pointer<Void>, int, int, int)
      >('CreateFileW');
  final close = kernel
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
  final lastError = kernel.lookupFunction<Uint32 Function(), int Function()>(
    'GetLastError',
  );
  final allowed = <String>{};
  final blocked = <String, CleanupPathBlock>{};
  for (final path in paths) {
    final absolute = File(path).absolute.path;
    final text = absolute.startsWith(r'\\?\')
        ? absolute
        : absolute.startsWith(r'\\')
        ? '\\\\?\\UNC\\${absolute.substring(2)}'
        : '\\\\?\\$absolute';
    final units = text.codeUnits;
    final memory = allocate(0, (units.length + 1) * 2);
    if (memory == nullptr) {
      blocked[path] = const CleanupPathBlock(CleanupBlockReason.unavailable);
      continue;
    }
    try {
      final name = memory.cast<Uint16>();
      name.asTypedList(units.length + 1)
        ..setRange(0, units.length, units)
        ..[units.length] = 0;
      final flags = attributes(name);
      if (flags == 0xFFFFFFFF) {
        blocked[path] = cleanupBlockFromWindowsError(
          lastError(),
          forDeletion: false,
        );
        continue;
      }
      final protected = switch (flags) {
        final value when value & 0x400 != 0 => CleanupBlockReason.linked,
        final value when value & 0x1000 != 0 => CleanupBlockReason.offline,
        final value when value & 0x4 != 0 => CleanupBlockReason.systemProtected,
        final value when value & 0x1 != 0 => CleanupBlockReason.readOnly,
        _ => null,
      };
      if (protected != null) {
        blocked[path] = CleanupPathBlock(protected);
        continue;
      }
      // Keep the exclusive DELETE check: discovery must not weaken cleanup safety.
      final handle = open(name, 0x10000, 0, nullptr, 3, 0x02200000, 0);
      if (handle == -1) {
        blocked[path] = cleanupBlockFromWindowsError(lastError());
        continue;
      }
      try {
        allowed.add(path);
      } finally {
        close(handle);
      }
    } finally {
      release(memory);
    }
  }
  return FileOperabilityReport(allowed: allowed, blocked: blocked);
}
