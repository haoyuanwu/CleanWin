import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../models/clean_models.dart';
import 'clean_service.dart';
import 'content_digest.dart';
import 'file_safety.dart';
import 'whitelist_service.dart';

class FileMoveService {
  FileMoveService(this.whitelist);
  final WhitelistService whitelist;
  Future<String> move(
    String path,
    String directory,
    String reviewedSignature,
    CleanCancellation cancellation, {
    void Function(String)? progress,
  }) async {
    if (!whitelist.readable ||
        whitelist.isWhitelisted(path) ||
        protectedSystemPath(path) ||
        protectedSystemPath(directory)) {
      throw StateError('此路径受保护');
    }
    if (await hasLinkedAncestorAsync(path) ||
        await hasLinkedAncestorAsync(directory)) {
      throw StateError('路径包含链接');
    }
    final source = File(path);
    final target = p.join(directory, p.basename(path));
    if (p.equals(p.absolute(path), p.absolute(target)) ||
        await FileSystemEntity.type(target, followLinks: false) !=
            FileSystemEntityType.notFound) {
      throw StateError('目标已存在，不会覆盖');
    }
    if (fileSignature(await source.stat()) != reviewedSignature) {
      throw StateError('文件已改变，请重新确认');
    }
    final stage = await Directory(directory).createTemp('.cleanwin-move-');
    final copy = File(p.join(stage.path, 'verified-copy'));
    try {
      if (cancellation.requested) return '移动已取消，原文件保留';
      progress?.call('正在复制，原文件保留');
      await source.copy(copy.path);
      progress?.call('正在校验文件内容');
      final digest = await contentDigest(path, cancellation: cancellation);
      if (cancellation.requested) return '移动已取消，原文件保留';
      final copiedDigest = await contentDigest(
        copy.path,
        cancellation: cancellation,
      );
      if (cancellation.requested) return '移动已取消，原文件保留';
      if (digest == null ||
          digest != copiedDigest ||
          fileSignature(await source.stat()) != reviewedSignature) {
        throw StateError('内容校验未完成或文件已改变，原文件保留');
      }
      if (cancellation.requested) return '移动已取消，原文件保留';
      if (await hasLinkedAncestorAsync(directory)) throw StateError('目标目录已改变');
      await _moveNoReplace(copy.path, target);
      progress?.call('目标内容已校验，正在处理原文件');
      final stat = await source.stat();
      final cleaner = CleanService()..whitelist = whitelist;
      final report = await cleaner.cleanItems([
        CleanItem(
          id: path,
          name: p.basename(path),
          path: path,
          sizeBytes: stat.size,
          category: CleanCategory.downloads,
          scannedFiles: [path],
          fileSignatures: {path: reviewedSignature},
        ),
      ], cancellation: cancellation);
      return report.completedItemIds.contains(path)
          ? '已移动到 $target'
          : '目标副本已保存到 $target，原文件仍保留';
    } finally {
      if (await copy.exists()) await copy.delete();
      await stage.delete();
    }
  }
}

Future<void> _moveNoReplace(String source, String target) async {
  if (!Platform.isWindows) {
    // Tests on other platforms must also refuse existing targets.
    await File(target).create(exclusive: true);
    try {
      await File(source).rename(target);
    } catch (_) {
      await File(target).delete();
      rethrow;
    }
    return;
  }
  final moved = await Isolate.run(() {
    final kernel = DynamicLibrary.open('kernel32.dll');
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
    final move = kernel
        .lookupFunction<
          Int32 Function(Pointer<Uint16>, Pointer<Uint16>),
          int Function(Pointer<Uint16>, Pointer<Uint16>)
        >('MoveFileW');
    Pointer<Uint16> wide(String text) {
      final pointer = allocate(0x40, (text.length + 1) * 2).cast<Uint16>();
      if (pointer == nullptr) throw StateError('无法分配文件操作内存');
      pointer
          .asTypedList(text.length + 1)
          .setRange(0, text.length, text.codeUnits);
      return pointer;
    }

    final from = wide(source);
    final to = wide(target);
    try {
      return move(from, to) != 0;
    } finally {
      free(from.cast());
      free(to.cast());
    }
  });
  if (!moved) throw FileSystemException('目标已存在、目录已改变或无法写入，原文件保留', target);
}
