import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/clean_models.dart';
import '../services/occupied_file_service.dart';
import '../services/path_utils.dart';
import '../state/app_state.dart';

Duration _motion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : const Duration(milliseconds: 320);

/// Shared dialog treatment adapts to the cosmic page and light module pages.
class CleanDialogSurface extends StatelessWidget {
  const CleanDialogSurface({
    super.key,
    required this.child,
    required this.accent,
  });
  final Widget child;
  final Color accent;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final secondaryText = dark
        ? const Color(0xFFE4EDF8)
        : const Color(0xFF1E293B);
    final secondaryFill = dark
        ? const Color(0xFF1C2D44)
        : const Color(0xFFF1F5F9);
    final disabledText = dark
        ? const Color(0xFFA3B3C7)
        : const Color(0xFF475569);
    final disabledFill = dark
        ? const Color(0xFF1A2537)
        : const Color(0xFFF1F5F9);
    final dialogTheme = theme.copyWith(
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              foregroundColor: secondaryText,
              backgroundColor: secondaryFill,
              disabledForegroundColor: disabledText,
              disabledBackgroundColor: disabledFill,
              minimumSize: const Size(0, 44),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                fontFamily: 'Segoe UI',
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ).copyWith(
              side: WidgetStateProperty.resolveWith(
                (states) => BorderSide(
                  color: states.contains(WidgetState.disabled)
                      ? (dark
                            ? const Color(0xFF45556C)
                            : const Color(0xFFCBD5E1))
                      : states.contains(WidgetState.focused) ||
                            states.contains(WidgetState.hovered)
                      ? accent
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
            ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: accent.computeLuminance() > .179
              ? Colors.black
              : Colors.white,
          disabledForegroundColor: disabledText,
          disabledBackgroundColor: disabledFill,
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
    final surface = dark ? const Color(0xFF192E3B) : Colors.white;
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.sizeOf(context).height * .86,
        ),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: accent.withValues(alpha: .25),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .16),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: SingleChildScrollView(
              child: Theme(
                data: dialogTheme,
                child: Padding(padding: const EdgeInsets.all(26), child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CleanConfirmationDialog extends StatelessWidget {
  const CleanConfirmationDialog({
    super.key,
    required this.title,
    required this.count,
    required this.bytes,
    required this.recycledBytes,
    required this.description,
  });
  final String title, description;
  final int count, bytes, recycledBytes;
  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return CleanDialogSurface(
      accent: accent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DialogHeading(
            icon: Icons.cleaning_services_rounded,
            accent: accent,
            title: title,
            subtitle: '确认后开始处理已选项目',
          ),
          const SizedBox(height: 24),
          _SpaceCard(
            label: recycledBytes > 0 && bytes == recycledBytes
                ? '将移入回收站'
                : '预计直接释放',
            bytes: recycledBytes > 0 && bytes == recycledBytes
                ? recycledBytes
                : bytes - recycledBytes,
            accent: accent,
          ),
          const SizedBox(height: 12),
          Text(
            '已选 $count 项 · 共 ${formatBytes(bytes)}',
            textAlign: TextAlign.center,
          ),
          if (recycledBytes > 0) ...[
            const SizedBox(height: 14),
            _Notice(
              icon: Icons.restore_from_trash_rounded,
              text: '下载文件移入回收站：${formatBytes(recycledBytes)}，清空后才释放空间。',
            ),
          ],
          const SizedBox(height: 18),
          _Notice(icon: Icons.info_outline_rounded, text: description),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: const Text('确认清理'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class OccupiedAppsDialog extends StatefulWidget {
  const OccupiedAppsDialog({
    super.key,
    required this.applications,
    required this.fileCount,
    required this.forCleanup,
    required this.canCloseAndRestore,
  });

  final List<OccupiedApplication> applications;
  final int fileCount;
  final bool forCleanup;
  final bool canCloseAndRestore;

  @override
  State<OccupiedAppsDialog> createState() => _OccupiedAppsDialogState();
}

class _OccupiedAppsDialogState extends State<OccupiedAppsDialog> {
  final Set<int> _selected = {};

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final safeApps = widget.applications
        .where((app) => app.safeToClose && app.restartable)
        .toList();
    return CleanDialogSurface(
      accent: accent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DialogHeading(
            icon: Icons.lock_clock_outlined,
            accent: accent,
            title: widget.forCleanup ? '清理前关闭占用软件？' : '关闭占用软件后重新扫描？',
            subtitle: '${widget.fileCount} 个文件正被以下软件使用',
          ),
          const SizedBox(height: 20),
          for (final app in widget.applications)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _selected.contains(app.pid),
              onChanged: app.safeToClose && app.restartable
                  ? (selected) => setState(() {
                      if (selected == true) {
                        _selected.add(app.pid);
                      } else {
                        _selected.remove(app.pid);
                      }
                    })
                  : null,
              secondary: Icon(
                app.safeToClose && app.restartable
                    ? Icons.apps_rounded
                    : Icons.shield_outlined,
                color: app.safeToClose && app.restartable
                    ? accent
                    : Theme.of(context).colorScheme.error,
              ),
              title: Text(app.name),
              subtitle: Text(
                '${app.safeToClose && app.restartable ? '处理完成后自动重新打开' : '系统、服务或无法安全恢复，不会自动关闭'} · PID ${app.pid}',
              ),
            ),
          const SizedBox(height: 14),
          _Notice(
            icon: Icons.info_outline_rounded,
            text: widget.canCloseAndRestore
                ? '请先保存软件中的工作。CleanWin 只请求正常退出，不会强制结束无响应进程。'
                : '这些占用程序无法全部安全恢复。CleanWin 将保留对应文件，不会强制结束程序。',
          ),
          const SizedBox(height: 22),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, <int>{}),
                child: Text(widget.forCleanup ? '不关闭，跳过占用文件' : '保留当前结果'),
              ),
              if (safeApps.length > 1)
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.pop(
                    context,
                    safeApps.map((app) => app.pid).toSet(),
                  ),
                  icon: const Icon(Icons.select_all_rounded, size: 18),
                  label: const Text('一键全部关闭'),
                ),
              if (widget.canCloseAndRestore)
                FilledButton.icon(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.pop(context, Set<int>.from(_selected)),
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: Text(widget.forCleanup ? '关闭所选并清理' : '关闭所选并重扫'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The progress modal automatically reveals a dedicated result panel on finish.
/// Keep the same route so completion can never expose an interactive page while
/// cleanup is still finalizing, and cancellation retains its actual report.
class CleanProgressDialog extends StatefulWidget {
  const CleanProgressDialog({super.key, this.categories});
  final Set<CleanCategory>? categories;
  @override
  State<CleanProgressDialog> createState() => _CleanProgressDialogState();
}

class _CleanProgressDialogState extends State<CleanProgressDialog> {
  double _ratio = 0;
  String _current = '准备清理…';
  int _done = 0, _total = 0;
  CleanReport? _report;
  bool _running = true, _cancelling = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted) return;
    final state = context.read<AppState>();
    setState(() {
      _total = state.results.values
          .where(
            (category) =>
                widget.categories == null ||
                widget.categories!.contains(category.category),
          )
          .expand((category) => category.items)
          .where((item) => item.selected)
          .length;
    });
    try {
      final report = await state.cleanSelected(
        categories: widget.categories,
        onProgress: (item, message, done, total) {
          if (!mounted) return;
          setState(() {
            _current = message;
            _done = done;
            _total = total;
            _ratio = total == 0 ? 1 : (done / total).clamp(0, 1);
          });
        },
      );
      if (mounted) setState(() => _report = report);
    } catch (_) {
      if (mounted) setState(() => _error = '清理未完成，请重新扫描后重试。');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final journalError = context.watch<AppState>().journal.error;
    final report = _report;
    final partial =
        report != null &&
        (report.failedCount > 0 ||
            report.skippedCount > 0 ||
            report.failures.isNotEmpty);
    final success =
        !_running &&
        _error == null &&
        report != null &&
        !report.cancelled &&
        !partial &&
        report.deletedCount > 0;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final successColor = dark
        ? const Color(0xFF6FE5C3)
        : const Color(0xFF087F62);
    final warning = dark ? const Color(0xFFF3C583) : const Color(0xFF9A5A11);
    final accent = _running
        ? scheme.primary
        : success
        ? successColor
        : _error != null || partial
        ? warning
        : scheme.onSurfaceVariant;
    final title = _running
        ? (_cancelling ? '正在取消…' : '正在清理')
        : _error != null
        ? '清理未完成'
        : report?.cancelled == true
        ? '已取消清理'
        : success
        ? '清理成功'
        : partial
        ? (report.deletedCount > 0 ? '部分清理完成' : '清理未完成')
        : '无需清理';
    return PopScope(
      canPop: !_running,
      child: CleanDialogSurface(
        accent: accent,
        child: AnimatedSize(
          duration: _motion(context),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: _motion(context),
            child: _running
                ? _progress(context, accent)
                : Column(
                    key: const ValueKey('cleanup-result'),
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DialogHeading(
                        accent: accent,
                        icon: success
                            ? Icons.check_rounded
                            : report?.cancelled == true
                            ? Icons.stop_rounded
                            : _error != null || partial
                            ? Icons.priority_high_rounded
                            : Icons.done_all_rounded,
                        title: title,
                        subtitle: success
                            ? '已完成本次所选项目'
                            : report?.cancelled == true
                            ? '已完成的操作保留，剩余项目可稍后继续'
                            : _error ??
                                  (partial ? '部分项目被占用或未能处理，请核对详情' : '没有项目被清理'),
                      ),
                      if (report != null) ...[
                        const SizedBox(height: 24),
                        _SpaceCard(
                          label:
                              report.freedBytes == 0 && report.recycledBytes > 0
                              ? '已移入回收站'
                              : '已释放空间',
                          bytes:
                              report.freedBytes == 0 && report.recycledBytes > 0
                              ? report.recycledBytes
                              : report.freedBytes,
                          accent: accent,
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _StatChip(
                              label: '成功',
                              value: report.deletedCount,
                              color: successColor,
                            ),
                            if (report.skippedCount > 0)
                              _StatChip(
                                label: '跳过',
                                value: report.skippedCount,
                                color: warning,
                              ),
                            if (report.failedCount > 0)
                              _StatChip(
                                label: '失败',
                                value: report.failedCount,
                                color: scheme.error,
                              ),
                          ],
                        ),
                        if (report.recycledBytes > 0) ...[
                          const SizedBox(height: 18),
                          _Notice(
                            icon: Icons.restore_from_trash_rounded,
                            text:
                                '已移到回收站 ${formatBytes(report.recycledBytes)}。可在 Windows 回收站恢复；清空回收站后才释放磁盘空间。',
                          ),
                        ],
                        if (report.failures.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: const Text('查看未处理项目'),
                            children: [
                              for (final failure in report.failures)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      failure,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                      if (journalError != null) ...[
                        const SizedBox(height: 14),
                        _Notice(
                          icon: Icons.info_outline_rounded,
                          text: journalError,
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, _report),
                        child: Text(
                          _error != null || report?.cancelled == true
                              ? '关闭'
                              : '完成',
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _progress(BuildContext context, Color accent) => Column(
    key: const ValueKey('cleanup-progress'),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _DialogHeading(
        icon: Icons.cleaning_services_rounded,
        accent: accent,
        title: _cancelling ? '正在取消…' : '正在清理',
        subtitle: '请稍候，正在处理已选项目',
      ),
      const SizedBox(height: 26),
      Row(
        children: [
          Text(
            '$_done / $_total 项',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          Text(
            _total == 0 || _ratio == 0 ? '准备中' : '${(_ratio * 100).round()}%',
            style: TextStyle(color: accent, fontWeight: FontWeight.w700),
          ),
        ],
      ),
      const SizedBox(height: 12),
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(
          value: _total == 0 || _ratio == 0 ? null : _ratio,
          color: accent,
          backgroundColor: accent.withValues(alpha: .12),
          minHeight: 10,
        ),
      ),
      const SizedBox(height: 18),
      _Notice(icon: Icons.folder_open_rounded, text: _current, maxLines: 3),
      if (_cancelling) ...[
        const SizedBox(height: 12),
        const Text('当前操作结束后停止，不再处理后续文件。', style: TextStyle(fontSize: 12)),
      ],
      const SizedBox(height: 24),
      OutlinedButton.icon(
        onPressed: _cancelling
            ? null
            : () {
                context.read<AppState>().cancelCleaning();
                setState(() => _cancelling = true);
              },
        icon: const Icon(Icons.stop_rounded, size: 18),
        label: Text(_cancelling ? '正在取消…' : '取消清理'),
      ),
    ],
  );
}

class _DialogHeading extends StatelessWidget {
  const _DialogHeading({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final Color accent;
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      TweenAnimationBuilder<double>(
        tween: Tween(begin: .82, end: 1),
        duration: _motion(context),
        curve: Curves.easeOutBack,
        builder: (_, value, child) =>
            Transform.scale(scale: value, child: child),
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withValues(alpha: .12),
            border: Border.all(color: accent.withValues(alpha: .45), width: 2),
          ),
          child: Icon(icon, color: accent, size: 34),
        ),
      ),
      const SizedBox(height: 18),
      Semantics(
        liveRegion: true,
        header: true,
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 23,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        subtitle,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
    ],
  );
}

class _SpaceCard extends StatelessWidget {
  const _SpaceCard({
    required this.label,
    required this.bytes,
    required this.accent,
  });
  final String label;
  final int bytes;
  final Color accent;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: accent.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: accent.withValues(alpha: .22), width: 1.5),
    ),
    child: Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          formatBytes(bytes),
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            color: accent,
          ),
        ),
      ],
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.maxLines});
  final IconData icon;
  final String text;
  final int? maxLines;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        icon,
        size: 17,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 9),
      Expanded(
        child: Tooltip(
          message: text,
          child: Text(
            text,
            maxLines: maxLines,
            overflow: maxLines == null ? null : TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    ],
  );
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final int value;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: .2)),
    ),
    child: Text(
      '$label $value',
      style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
    ),
  );
}

Future<CleanReport?> showCleanProgress(
  BuildContext context, {
  Set<CleanCategory>? categories,
}) => showDialog<CleanReport>(
  context: context,
  barrierDismissible: false,
  builder: (_) => CleanProgressDialog(categories: categories),
);
