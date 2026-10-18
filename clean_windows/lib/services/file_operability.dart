import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

/// Probe DELETE access without modifying, truncating, or marking files for
/// deletion. Exclusive sharing also excludes files currently in use.
Future<Set<String>> operableCleanupPaths(List<String> paths) async {
  if (paths.isEmpty) return {};
  if (!Platform.isWindows) return {}; // This cleaner targets Windows.
  return Isolate.run(() => _probeWindows(paths));
}

Set<String> _probeWindows(List<String> paths) {
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
  final allowed = <String>{};
  for (final path in paths) {
    final absolute = File(path).absolute.path;
    final text = absolute.startsWith(r'\\?\')
        ? absolute
        : absolute.startsWith(r'\\')
        ? '\\\\?\\UNC\\${absolute.substring(2)}'
        : '\\\\?\\$absolute';
    final units = text.codeUnits;
    final memory = allocate(0, (units.length + 1) * 2);
    if (memory == nullptr) continue;
    try {
      final name = memory.cast<Uint16>();
      name.asTypedList(units.length + 1)
        ..setRange(0, units.length, units)
        ..[units.length] = 0;
      final flags = attributes(name);
      // Read-only, system, reparse and offline targets are not cleanup offers.
      if (flags == 0xFFFFFFFF || flags & (0x1 | 0x4 | 0x400 | 0x1000) != 0) {
        continue;
      }
      final handle = open(name, 0x10000, 0, nullptr, 3, 0x02200000, 0);
      if (handle == -1) continue;
      try {
        allowed.add(path);
      } finally {
        close(handle);
      }
    } finally {
      release(memory);
    }
  }
  return allowed;
}
