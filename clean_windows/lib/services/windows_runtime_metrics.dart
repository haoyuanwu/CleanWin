import 'dart:ffi';

class RuntimeMetrics {
  const RuntimeMetrics({
    required this.cpuPercent,
    required this.totalMemoryMb,
    required this.usedMemoryMb,
  });
  final double? cpuPercent;
  final double totalMemoryMb;
  final double usedMemoryMb;
  double get memoryPercent =>
      totalMemoryMb <= 0 ? 0 : usedMemoryMb / totalMemoryMb * 100;
}

final class _FileTime extends Struct {
  @Uint32()
  external int low;
  @Uint32()
  external int high;
  int get ticks => (high << 32) | low;
}

final class _MemoryStatus extends Struct {
  @Uint32()
  external int length;
  @Uint32()
  external int load;
  @Uint64()
  external int totalPhysical;
  @Uint64()
  external int availablePhysical;
  @Uint64()
  external int totalPageFile;
  @Uint64()
  external int availablePageFile;
  @Uint64()
  external int totalVirtual;
  @Uint64()
  external int availableVirtual;
  @Uint64()
  external int availableExtendedVirtual;
}

/// Native reads avoid performance-counter sampling waits and WMI subprocesses.
class WindowsRuntimeMetrics {
  WindowsRuntimeMetrics() {
    final library = DynamicLibrary.open('kernel32.dll');
    _getHeap = library
        .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
          'GetProcessHeap',
        );
    _allocate = library
        .lookupFunction<
          Pointer<Void> Function(Pointer<Void>, Uint32, IntPtr),
          Pointer<Void> Function(Pointer<Void>, int, int)
        >('HeapAlloc');
    _free = library
        .lookupFunction<
          Int32 Function(Pointer<Void>, Uint32, Pointer<Void>),
          int Function(Pointer<Void>, int, Pointer<Void>)
        >('HeapFree');
    _getTimes = library
        .lookupFunction<
          Int32 Function(
            Pointer<_FileTime>,
            Pointer<_FileTime>,
            Pointer<_FileTime>,
          ),
          int Function(
            Pointer<_FileTime>,
            Pointer<_FileTime>,
            Pointer<_FileTime>,
          )
        >('GetSystemTimes');
    _getMemory = library
        .lookupFunction<
          Int32 Function(Pointer<_MemoryStatus>),
          int Function(Pointer<_MemoryStatus>)
        >('GlobalMemoryStatusEx');
  }
  late final Pointer<Void> Function() _getHeap;
  late final Pointer<Void> Function(Pointer<Void>, int, int) _allocate;
  late final int Function(Pointer<Void>, int, Pointer<Void>) _free;
  late final int Function(
    Pointer<_FileTime>,
    Pointer<_FileTime>,
    Pointer<_FileTime>,
  )
  _getTimes;
  late final int Function(Pointer<_MemoryStatus>) _getMemory;
  int? _previousIdle;
  int? _previousTotal;
  double? _lastCpu;

  RuntimeMetrics read() {
    final heap = _getHeap();
    // MEMORYSTATUSEX (64 bytes) followed by three FILETIME structs (8 each).
    final block = _allocate(
      heap,
      8,
      sizeOf<_MemoryStatus>() + 3 * sizeOf<_FileTime>(),
    );
    if (block == nullptr) throw StateError('无法分配运行状态采样空间');
    try {
      final memory = block.cast<_MemoryStatus>();
      memory.ref.length = sizeOf<_MemoryStatus>();
      final bytes = block.cast<Uint8>();
      final idle = (bytes + sizeOf<_MemoryStatus>()).cast<_FileTime>();
      final kernel = (bytes + sizeOf<_MemoryStatus>() + sizeOf<_FileTime>())
          .cast<_FileTime>();
      final user = (bytes + sizeOf<_MemoryStatus>() + 2 * sizeOf<_FileTime>())
          .cast<_FileTime>();
      if (_getMemory(memory) == 0 || _getTimes(idle, kernel, user) == 0) {
        throw StateError('无法读取系统运行状态');
      }
      final total = kernel.ref.ticks + user.ref.ticks;
      if (_previousTotal != null && _previousIdle != null) {
        final elapsed = total - _previousTotal!;
        if (elapsed > 0) {
          final idleDelta = idle.ref.ticks - _previousIdle!;
          _lastCpu = ((elapsed - idleDelta) / elapsed * 100).clamp(0, 100);
        }
      }
      _previousIdle = idle.ref.ticks;
      _previousTotal = total;
      return RuntimeMetrics(
        cpuPercent: _lastCpu,
        totalMemoryMb: memory.ref.totalPhysical / 1048576,
        usedMemoryMb:
            (memory.ref.totalPhysical - memory.ref.availablePhysical) / 1048576,
      );
    } finally {
      _free(heap, 0, block);
    }
  }
}
