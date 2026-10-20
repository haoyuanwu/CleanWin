import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/clean_models.dart';
import '../services/activity_service.dart';
import '../services/duplicate_service.dart';
import '../services/path_utils.dart';
import '../state/app_state.dart';
import 'file_actions_button.dart';
import 'path_picker.dart';

Future<void> showDuplicateFiles(BuildContext context, {String root = ''}) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DuplicateDialog(root: root),
    );

class DuplicateDialog extends StatefulWidget {
  const DuplicateDialog({super.key, this.root = '', this.service});
  final String root;
  final DuplicateService? service;
  @override
  State<DuplicateDialog> createState() => _DuplicateDialogState();
}

class _DuplicateDialogState extends State<DuplicateDialog> {
  late String _root = widget.root;
  late final _service =
      widget.service ??
      DuplicateService(whitelist: context.read<AppState?>()?.whitelist);
  List<DuplicateGroup> _groups = [];
  CleanCancellation? _cancellation;
  bool _busy = false;
  String _message = '按文件内容校验，默认不勾选；每组至少保留一个副本。';
  final _clock = Stopwatch();
  String get _taskId => 'duplicates-${identityHashCode(this)}';
  @override
  void dispose() {
    _cancellation?.cancel();
    TaskBoard.instance.finish(_taskId);
    super.dispose();
  }

  Future<void> _run({bool recycle = false}) async {
    final cancellation = _cancellation = CleanCancellation();
    setState(() => _busy = true);
    TaskBoard.instance.update(
      _taskId,
      '重复文件检查',
      _root,
      cancel: cancellation.cancel,
    );
    _clock.start();
    try {
      if (recycle) {
        final report = await _service.recycleSelected(_groups, cancellation);
        if (!mounted) return;
        context.read<AppState?>()?.journal.record('重复文件', report);
        setState(() {
          for (final group in _groups) {
            group.files.removeWhere(
              (file) => report.completedItemIds.contains(file.path),
            );
          }
          _groups.removeWhere((group) => group.files.length < 2);
          _message =
              '${report.cancelled ? '已取消 · ' : ''}已移到回收站 ${report.deletedCount} 项 · ${formatBytes(report.recycledBytes)}。${report.failures.take(2).join('；')}';
        });
      } else {
        final groups = await _service.scan(
          _root,
          cancellation: cancellation,
          onProgress: (path) {
            if (_clock.elapsedMilliseconds < 150) return;
            _clock.reset();
            TaskBoard.instance.update(
              _taskId,
              '重复文件检查',
              path,
              cancel: cancellation.cancel,
            );
            if (mounted) setState(() => _message = path);
          },
        );
        if (mounted) {
          setState(() {
            _groups = groups;
            _message =
                '${cancellation.requested ? '已取消' : '检查完成'} · ${groups.length} 组 · ${_service.skipped} 个文件未参与校验';
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _message = '操作未完整完成，未处理文件保留');
    } finally {
      TaskBoard.instance.finish(_taskId);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('重复文件'),
      content: SizedBox(
        width: 820,
        height: math.min(580, MediaQuery.sizeOf(context).height * .65),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          final path = await pickScanDirectory(
                            context,
                            initial: _root,
                          );
                          if (path != null && mounted) {
                            setState(() {
                              _root = path;
                              _groups = [];
                            });
                          }
                        },
                  icon: const Icon(Icons.folder_open_rounded),
                  label: const Text('选择目录'),
                ),
                FilledButton(
                  onPressed: _busy || _root.isEmpty ? null : () => _run(),
                  child: const Text('内容校验'),
                ),
                if (_busy)
                  TextButton(
                    onPressed: () => _cancellation?.cancel(),
                    child: const Text('取消'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(_root, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Text(
              _message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
            if (_busy) const LinearProgressIndicator(),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: _groups.length,
                itemBuilder: (context, index) {
                  final group = _groups[index];
                  return Card(
                    child: ExpansionTile(
                      title: Text(
                        '${group.files.length} 个副本 · 每个 ${formatBytes(group.files.first.sizeBytes)}',
                      ),
                      subtitle: const Text(
                        '第一项保留，其他副本需手动选择',
                        style: TextStyle(fontSize: 11),
                      ),
                      children: [
                        for (var i = 0; i < group.files.length; i++)
                          FileActionsButton.contextMenu(
                            path: group.files[i].path,
                            allowMove: false,
                            enabled: !_busy,
                            actions: [
                              if (i > 0)
                                FileMenuAction(
                                  group.files[i].selected ? '取消勾选' : '勾选此项',
                                  icon: Icons.check_box_outlined,
                                  onSelected: () => setState(
                                    () => group.files[i].selected =
                                        !group.files[i].selected,
                                  ),
                                ),
                            ],
                            child: ListTile(
                              leading: i == 0
                                  ? const Tooltip(
                                      message: '保留此副本',
                                      child: Icon(Icons.lock_outline_rounded),
                                    )
                                  : Checkbox(
                                      value: group.files[i].selected,
                                      onChanged: _busy
                                          ? null
                                          : (value) => setState(
                                              () => group.files[i].selected =
                                                  value ?? false,
                                            ),
                                    ),
                              title: Text(
                                group.files[i].name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                group.files[i].path,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: FileActionsButton(
                                path: group.files[i].path,
                                allowMove: false,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed:
              _busy ||
                  !_groups.any(
                    (group) => group.files.any((file) => file.selected),
                  )
              ? null
              : () async {
                  final approved = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('移到回收站'),
                      content: const Text('将再次校验文件内容与保留副本，再把手动选中的副本移到回收站。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('确认'),
                        ),
                      ],
                    ),
                  );
                  if (approved == true && mounted) await _run(recycle: true);
                },
          child: const Text('所选副本移到回收站'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}
