import 'package:flutter/material.dart';

import '../services/file_actions.dart';

import 'dart:io';

import 'package:provider/provider.dart';

import '../models/clean_models.dart';
import '../services/activity_service.dart';
import '../services/file_move_service.dart';
import '../services/file_safety.dart';
import '../services/whitelist_service.dart';
import '../state/app_state.dart';
import 'path_picker.dart';

class FileActionsButton extends StatelessWidget {
  const FileActionsButton({super.key, required this.path, this.onMoved})
    : child = null,
      enabled = true;
  const FileActionsButton.contextMenu({
    super.key,
    required this.path,
    required Widget this.child,
    this.onMoved,
    this.enabled = true,
  });
  final String path;
  final VoidCallback? onMoved;
  final Widget? child;
  final bool enabled;
  static const _items = <PopupMenuEntry<String>>[
    PopupMenuItem(value: 'reveal', child: Text('打开所在位置')),
    PopupMenuItem(value: 'copy', child: Text('复制路径')),
    PopupMenuItem(value: 'move', child: Text('移动到其他目录')),
  ];
  @override
  Widget build(BuildContext context) {
    if (child != null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapUp: !enabled
            ? null
            : (details) async {
                final overlay =
                    Navigator.of(context).overlay!.context.findRenderObject()!
                        as RenderBox;
                final point = overlay.globalToLocal(details.globalPosition);
                final value = await showMenu<String>(
                  context: context,
                  position: RelativeRect.fromRect(
                    Rect.fromLTWH(point.dx, point.dy, 0, 0),
                    Offset.zero & overlay.size,
                  ),
                  items: _items,
                );
                if (value != null && context.mounted) {
                  await _perform(context, value);
                }
              },
        child: child,
      );
    }
    return PopupMenuButton<String>(
      tooltip: '文件操作',
      icon: const Icon(Icons.more_horiz_rounded, size: 18),
      itemBuilder: (_) => _items,
      onSelected: (value) => _perform(context, value),
    );
  }

  Future<void> _perform(BuildContext context, String value) async {
    try {
      if (value == 'move') {
        final before = await File(path).stat();
        if (!context.mounted) return;
        if (before.type != FileSystemEntityType.file) {
          throw StateError('文件夹请在资源管理器中移动');
        }
        final directory = await pickScanDirectory(context);
        if (directory == null || !context.mounted) return;
        final state = context.read<AppState?>();
        final cancellation = CleanCancellation();
        final id = 'move-$path';
        String message;
        try {
          TaskBoard.instance.update(
            id,
            '文件移动',
            path,
            cancel: cancellation.cancel,
          );
          message =
              await FileMoveService(state?.whitelist ?? WhitelistService())
                  .move(
                    path,
                    directory,
                    fileSignature(before),
                    cancellation,
                    progress: (message) => TaskBoard.instance.update(
                      id,
                      '文件移动',
                      '$message\n$path',
                      cancel: cancellation.cancel,
                    ),
                  );
          state?.journal.record(
            '文件移动',
            CleanReport(
              freedBytes: 0,
              deletedCount: message.startsWith('已移动') ? 1 : 0,
              skippedCount: 0,
              failedCount: 0,
              cancelled: cancellation.requested,
            ),
            names: [path, message],
          );
          if (message.startsWith('已移动')) onMoved?.call();
        } finally {
          TaskBoard.instance.finish(id);
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
        }
      } else if (value == 'reveal') {
        await FileActions.reveal(path);
      } else {
        await FileActions.copyPath(path);
      }
      if (context.mounted && value == 'copy') {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('路径已复制')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is StateError ? error.message : '操作未完成，请检查文件和目录权限',
            ),
          ),
        );
      }
    }
  }
}
