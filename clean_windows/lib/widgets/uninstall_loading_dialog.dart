import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/installed_app.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../services/uninstall_service.dart';

/// 卸载 loading 弹窗
class UninstallLoadingDialog extends StatefulWidget {
  const UninstallLoadingDialog({super.key, required this.app});

  final InstalledApp app;

  @override
  State<UninstallLoadingDialog> createState() => _UninstallLoadingDialogState();
}

class _UninstallLoadingDialogState extends State<UninstallLoadingDialog> {
  String _message = '正在启动卸载程序…';
  String? _resultMessage;
  bool _success = false;
  bool _running = true;
  UninstallStatus? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final state = context.read<AppState>();
    setState(() => _message = '正在卸载「${widget.app.displayName}」…');

    UninstallResult result;
    try {
      result = await state.uninstallApp(widget.app);
    } catch (_) {
      result = UninstallResult(
        success: false,
        message: '无法确认卸载结果，请刷新核对',
        status: UninstallStatus.unverified,
      );
    }

    if (!mounted) return;
    setState(() {
      _running = false;
      _success = result.success;
      _status = result.status;
      _resultMessage = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_running,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            if (_running)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            else
              Icon(
                _success ? Icons.check_circle_rounded : Icons.error_rounded,
                color: _success ? AppColors.success : AppColors.danger,
                size: 22,
              ),
            const SizedBox(width: 10),
            Text(
              _running
                  ? '正在卸载'
                  : switch (_status) {
                      UninstallStatus.cancelled => '已取消卸载',
                      UninstallStatus.restartRequired => '需要重新启动',
                      UninstallStatus.unverified => '等待核对',
                      _ => _success ? '卸载完成' : '卸载失败',
                    },
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '「${widget.app.displayName}」',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              if (_running) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: const LinearProgressIndicator(minHeight: 6),
                ),
                const SizedBox(height: 14),
                Text(
                  _message,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '若弹出卸载向导，请按提示完成。此窗口会等待卸载结束。',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _success
                        ? AppColors.successSoft
                        : AppColors.dangerSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _success
                            ? Icons.done_all_rounded
                            : Icons.warning_amber_rounded,
                        color: _success ? AppColors.success : AppColors.danger,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _resultMessage ?? '',
                          style: const TextStyle(fontSize: 13, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (!_running)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            ),
        ],
      ),
    );
  }
}

/// 显示卸载 loading
Future<void> showUninstallLoading(BuildContext context, InstalledApp app) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => UninstallLoadingDialog(app: app),
  );
}
