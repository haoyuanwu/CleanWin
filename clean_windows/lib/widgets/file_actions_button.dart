import 'dart:async';

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

class FileMenuAction {
  const FileMenuAction(
    this.label, {
    required this.icon,
    required this.onSelected,
    this.destructive = false,
  });
  final String label;
  final IconData icon;
  final FutureOr<void> Function()? onSelected;
  final bool destructive;
}

class FileActionsButton extends StatelessWidget {
  const FileActionsButton({
    super.key,
    required this.path,
    this.onMoved,
    this.allowMove = true,
    this.actions = const [],
  }) : child = null,
       enabled = true;
  const FileActionsButton.contextMenu({
    super.key,
    required this.path,
    required Widget this.child,
    this.onMoved,
    this.enabled = true,
    this.allowMove = true,
    this.actions = const [],
  });
  final String path;
  final VoidCallback? onMoved;
  final Widget? child;
  final bool enabled;
  final bool allowMove;
  final List<FileMenuAction> actions;
  List<PopupMenuEntry<String>> _menu(BuildContext context) => [
    if (path.trim().isNotEmpty) ...[
      _entry(context, 'reveal', '打开所在位置', Icons.folder_open_rounded),
      _entry(context, 'copy', '复制路径', Icons.copy_rounded),
      if (allowMove)
        _entry(context, 'move', '移动到其他目录', Icons.drive_file_move_rounded),
    ],
    if (actions.isNotEmpty && path.trim().isNotEmpty) const PopupMenuDivider(),
    for (var i = 0; i < actions.length; i++)
      _entry(
        context,
        'action_$i',
        actions[i].label,
        actions[i].icon,
        enabled: actions[i].onSelected != null,
        destructive: actions[i].destructive,
      ),
  ];
  PopupMenuItem<String> _entry(
    BuildContext context,
    String value,
    String label,
    IconData icon, {
    bool enabled = true,
    bool destructive = false,
  }) => PopupMenuItem(
    value: value,
    enabled: enabled,
    child: Row(
      children: [
        Icon(
          icon,
          size: 17,
          color: destructive ? Theme.of(context).colorScheme.error : null,
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: destructive
              ? TextStyle(color: Theme.of(context).colorScheme.error)
              : null,
        ),
      ],
    ),
  );
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
                  items: _menu(context),
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
      itemBuilder: _menu,
      onSelected: (value) => _perform(context, value),
    );
  }

  Future<void> _perform(BuildContext context, String value) async {
    try {
      if (value.startsWith('action_')) {
        final index = int.tryParse(value.substring(7));
        if (index != null && index >= 0 && index < actions.length) {
          await actions[index].onSelected?.call();
        }
      } else if (value == 'move') {
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
