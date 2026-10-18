import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

final class _Guid extends Struct {
  @Uint32()
  external int a;
  @Uint16()
  external int b;
  @Uint16()
  external int c;
  @Array(8)
  external Array<Uint8> d;
}

/// Use the Windows recycle-only operation. Failure never triggers file.delete.
Future<bool> recycleFile(String path) async {
  if (!Platform.isWindows) return false;
  return Isolate.run(() {
    final kernel = DynamicLibrary.open('kernel32.dll');
    final ole = DynamicLibrary.open('ole32.dll');
    final allocate = kernel
        .lookupFunction<
          Pointer<Void> Function(Uint32, IntPtr),
          Pointer<Void> Function(int, int)
        >('LocalAlloc');
    final free = kernel
        .lookupFunction<
          Pointer<Void> Function(Pointer<Void>),
          Pointer<Void> Function(Pointer<Void>)
        >('LocalFree');
    final initialize = ole
        .lookupFunction<
          Int32 Function(Pointer<Void>, Uint32),
          int Function(Pointer<Void>, int)
        >('CoInitializeEx');
    final uninitialize = ole.lookupFunction<Void Function(), void Function()>(
      'CoUninitialize',
    );
    final parseGuid = ole
        .lookupFunction<
          Int32 Function(Pointer<Uint16>, Pointer<_Guid>),
          int Function(Pointer<Uint16>, Pointer<_Guid>)
        >('CLSIDFromString');
    final create = ole
        .lookupFunction<
          Int32 Function(
            Pointer<_Guid>,
            Pointer<Void>,
            Uint32,
            Pointer<_Guid>,
            Pointer<Pointer<Void>>,
          ),
          int Function(
            Pointer<_Guid>,
            Pointer<Void>,
            int,
            Pointer<_Guid>,
            Pointer<Pointer<Void>>,
          )
        >('CoCreateInstance');
    final parseItem = DynamicLibrary.open('shell32.dll')
        .lookupFunction<
          Int32 Function(
            Pointer<Uint16>,
            Pointer<Void>,
            Pointer<_Guid>,
            Pointer<Pointer<Void>>,
          ),
          int Function(
            Pointer<Uint16>,
            Pointer<Void>,
            Pointer<_Guid>,
            Pointer<Pointer<Void>>,
          )
        >('SHCreateItemFromParsingName');
    final memory = <Pointer<Void>>[];
    Pointer<T> reserve<T extends NativeType>(int bytes) {
      final block = allocate(0x40, bytes);
      if (block == nullptr) throw StateError('无法分配回收站操作内存');
      memory.add(block);
      return block.cast<T>();
    }

    Pointer<Uint16> wide(String text) {
      final pointer = reserve<Uint16>((text.length + 1) * 2);
      pointer
          .asTypedList(text.length + 1)
          .setRange(0, text.length, text.codeUnits);
      return pointer;
    }

    Pointer<_Guid> guid(String value) {
      final pointer = reserve<_Guid>(sizeOf<_Guid>());
      if (parseGuid(wide(value), pointer) < 0) throw StateError('无效 COM 标识');
      return pointer;
    }

    Pointer<Pointer<Void>> table(Pointer<Void> object) =>
        object.cast<Pointer<Pointer<Void>>>().value;
    void release(Pointer<Void> object) {
      if (object != nullptr) {
        table(object)[2]
            .cast<NativeFunction<Uint32 Function(Pointer<Void>)>>()
            .asFunction<int Function(Pointer<Void>)>()(object);
      }
    }

    Pointer<Void> operation = nullptr;
    Pointer<Void> item = nullptr;
    final initialized = initialize(nullptr, 2) >= 0;
    try {
      if (!initialized) return false;
      final result = reserve<Pointer<Void>>(sizeOf<Pointer<Void>>());
      if (create(
            guid('{3AD05575-8857-4850-9277-11B85BDB8E09}'),
            nullptr,
            1,
            guid('{947AAB5F-0A5C-4C13-B4D6-4BF7836FC9F8}'),
            result,
          ) <
          0) {
        return false;
      }
      operation = result.value;
      final vtable = table(operation);
      final setFlags = vtable[5]
          .cast<NativeFunction<Int32 Function(Pointer<Void>, Uint32)>>()
          .asFunction<int Function(Pointer<Void>, int)>();
      if (setFlags(
            operation,
            0x00080000 | 0x00100000 | 0x20000000 | 0x400 | 0x10 | 0x4,
          ) <
          0) {
        return false;
      }
      final itemOut = reserve<Pointer<Void>>(sizeOf<Pointer<Void>>());
      if (parseItem(
            wide(File(path).absolute.path),
            nullptr,
            guid('{43826D1E-E718-42EE-BC55-A1E261C37BFE}'),
            itemOut,
          ) <
          0) {
        return false;
      }
      item = itemOut.value;
      final remove = vtable[18]
          .cast<
            NativeFunction<
              Int32 Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)
            >
          >()
          .asFunction<
            int Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)
          >();
      if (remove(operation, item, nullptr) < 0) return false;
      final perform = vtable[21]
          .cast<NativeFunction<Int32 Function(Pointer<Void>)>>()
          .asFunction<int Function(Pointer<Void>)>();
      if (perform(operation) < 0) return false;
      final aborted = reserve<Int32>(4);
      final didAbort = vtable[22]
          .cast<NativeFunction<Int32 Function(Pointer<Void>, Pointer<Int32>)>>()
          .asFunction<int Function(Pointer<Void>, Pointer<Int32>)>();
      return didAbort(operation, aborted) >= 0 && aborted.value == 0;
    } finally {
      release(item);
      release(operation);
      for (final pointer in memory.reversed) {
        free(pointer);
      }
      if (initialized) uninitialize();
    }
  });
}
