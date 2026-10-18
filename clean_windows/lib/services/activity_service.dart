import 'package:flutter/foundation.dart';

import '../models/clean_models.dart';
import 'module_cache.dart';

class ActivityJournal {
  ActivityJournal({ModuleCache? cache, this.enabled = true})
    : _cache =
          cache ??
          ModuleCache(namespace: 'activity', ttl: const Duration(days: 3650));
  final bool enabled;
  final ModuleCache _cache;
  String? error;
  List<Map<String, dynamic>> get records =>
      (enabled ? _cache.getList('records_v1') ?? [] : [])
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .toList();
  void record(
    String title,
    CleanReport report, {
    List<String> names = const [],
  }) {
    if (!enabled) return;
    final entry = <String, dynamic>{
      'time': DateTime.now().toIso8601String(),
      'title': title,
      'freed': report.freedBytes,
      'recycled': report.recycledBytes,
      'completed': report.deletedCount,
      'skipped': report.skippedCount,
      'failed': report.failedCount,
      'cancelled': report.cancelled,
      'failures': report.failures.take(20).toList(),
      'names': names.take(20).toList(),
    };
    try {
      _cache.setDurable('records_v1', [entry, ...records].take(200).toList());
      error = null;
    } catch (_) {
      error = '操作已完成，但历史记录未能保存';
    }
  }
}

class ActiveTask {
  const ActiveTask(this.title, this.detail, this.cancel);
  final String title;
  final String detail;
  final VoidCallback? cancel;
}

class TaskBoard extends ChangeNotifier {
  static final instance = TaskBoard();
  final Map<String, ActiveTask> _tasks = {};
  final Set<String> _stopping = {};
  Map<String, ActiveTask> get tasks => Map.unmodifiable(_tasks);
  void update(String id, String title, String detail, {VoidCallback? cancel}) {
    _tasks[id] = ActiveTask(
      title,
      _stopping.contains(id) ? '正在取消 · $detail' : detail,
      _stopping.contains(id) ? null : cancel,
    );
    notifyListeners();
  }

  void cancel(String id) {
    final task = _tasks[id];
    if (task?.cancel == null) return;
    _stopping.add(id);
    task!.cancel!();
    update(id, task.title, task.detail);
  }

  void finish(String id) {
    _stopping.remove(id);
    if (_tasks.remove(id) != null) notifyListeners();
  }
}
