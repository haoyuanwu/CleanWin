import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../models/scan_options.dart';

import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/page_shell.dart';
import '../widgets/module_insights.dart';
import '../widgets/activity_center.dart';
import '../widgets/duplicate_dialog.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _scanSection = GlobalKey();
  final _behaviorSection = GlobalKey();

  void _showSection(GlobalKey key) {
    final section = key.currentContext;
    if (section == null) return;
    Scrollable.ensureVisible(
      section,
      alignment: .1,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 300),
    );
  }

  Future<void> _save(
    String label,
    ScanOptions Function(ScanOptions) change, {
    String? feedback,
  }) async {
    final state = context.read<AppState>();
    final saved = await state.updateOptions(change(state.options));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? feedback ?? '$label设置已保存'
                : state.optionsSaveError ?? '当前任务完成后可修改扫描范围',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final options = state.options;
    final scanEnabled = [
      options.cleanBrowserCache,
      options.cleanGpuCache,
    ].where((value) => value).length;
    final behaviorEnabled = [
      options.confirmBeforeClean,
      options.autoScanOnStart,
    ].where((value) => value).length;
    return SingleChildScrollView(
      padding: kPagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ModuleHeader(
            title: '设置',
            subtitle: '更改自动保存 · 扫描范围下次扫描生效，启动行为下次启动生效',
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ModuleInsights(
              label: '当前配置',
              value: '${scanEnabled + behaviorEnabled} 项已开启',

              icon: Icons.tune_rounded,
              segments: [
                InsightSegment(
                  label: '扫描范围',
                  amount: scanEnabled.toDouble(),
                  value: '$scanEnabled / 2',
                  color: AppColors.primary,
                  onTap: () => _showSection(_scanSection),
                ),
                InsightSegment(
                  label: '行为设置',
                  amount: behaviorEnabled.toDouble(),
                  value: '$behaviorEnabled / 2',
                  color: AppColors.accent,
                  onTap: () => _showSection(_behaviorSection),
                ),
                InsightSegment(
                  label: '已关闭',
                  amount: (4 - scanEnabled - behaviorEnabled).toDouble(),
                  value: '${4 - scanEnabled - behaviorEnabled}',
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          StatusChip(
            label: state.savingOptions
                ? '正在保存…'
                : state.optionsSaveError == null
                ? '设置自动保存'
                : '保存失败',
            color: state.optionsSaveError == null
                ? AppColors.success
                : AppColors.danger,
            icon: state.optionsSaveError == null
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
          ),
          if (state.optionsSaveError != null) ...[
            const SizedBox(height: 12),
            GlassBanner(
              icon: Icons.error_outline_rounded,
              text: state.optionsSaveError!,
              color: AppColors.danger,
            ),
          ],
          const SizedBox(height: 20),
          if (state.scanning || state.cleaning) ...[
            const GlassBanner(
              icon: Icons.hourglass_top_rounded,
              text: '扫描范围开关在当前任务完成后可修改；行为设置仍可保存。',
              color: AppColors.primary,
            ),
            const SizedBox(height: 16),
          ],
          Text(
            '扫描范围',
            key: _scanSection,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ModuleSelect<bool>(
            label: '扫描模式',
            value: options.deepScan,
            items: const [
              ModuleSelectItem(value: false, child: Text('快速扫描 · 已知缓存')),
              ModuleSelectItem(value: true, child: Text('深度扫描 · 发现更多候选缓存')),
            ],
            onChanged: state.scanning || state.cleaning || state.savingOptions
                ? null
                : (value) => _save(
                    '扫描模式',
                    (current) => current.copyWith(deepScan: value),
                    feedback: '已保存，下次扫描生效；深度结果仍需手动确认',
                  ),
          ),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _SwitchTile(
                  icon: Icons.public_rounded,
                  title: '扫描浏览器缓存',
                  subtitle: '仅扫描可操作文件，默认不勾选；清理后网页可能重新加载',
                  value: options.cleanBrowserCache,
                  onChanged:
                      state.scanning || state.cleaning || state.savingOptions
                      ? null
                      : (v) => _save(
                          '浏览器缓存',
                          (current) => current.copyWith(cleanBrowserCache: v),
                          feedback: '扫描范围已保存，请重新扫描应用更改',
                        ),
                ),
                const Divider(height: 1, indent: 72, endIndent: 16),
                _SwitchTile(
                  icon: Icons.memory_rounded,
                  title: '扫描显卡缓存',
                  subtitle: '默认不勾选，避免着色器重建影响游戏流畅度',
                  value: options.cleanGpuCache,
                  onChanged:
                      state.scanning || state.cleaning || state.savingOptions
                      ? null
                      : (v) => _save(
                          '显卡缓存',
                          (current) => current.copyWith(cleanGpuCache: v),
                          feedback: '扫描范围已保存，请重新扫描应用更改',
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text(
            '行为',
            key: _behaviorSection,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _SwitchTile(
                  icon: Icons.verified_user_outlined,
                  title: '清理前二次确认',
                  subtitle: '显示将释放的空间与项目数量',
                  value: options.confirmBeforeClean,
                  onChanged: state.savingOptions
                      ? null
                      : (v) => _save(
                          '清理确认',
                          (current) => current.copyWith(confirmBeforeClean: v),
                        ),
                ),
                const Divider(height: 1, indent: 72, endIndent: 16),
                _SwitchTile(
                  icon: Icons.manage_search_rounded,
                  title: '启动时自动扫描',
                  subtitle: '下次启动软件进入一键清理并显示扫描进度；只扫描，不自动清理',
                  value: options.autoScanOnStart,
                  onChanged: state.savingOptions
                      ? null
                      : (v) => _save(
                          '启动扫描',
                          (current) => current.copyWith(autoScanOnStart: v),
                          feedback: v
                              ? '已保存：下次启动软件自动进入一键清理并扫描'
                              : '已保存：下次启动软件不自动扫描',
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            '安全说明',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => showActivityCenter(context),
                icon: const Icon(Icons.task_alt_rounded),
                label: const Text('任务与记录'),
              ),
              OutlinedButton.icon(
                onPressed: () => showActivityCenter(context, tab: 1),
                icon: const Icon(Icons.history_rounded),
                label: const Text('清理历史'),
              ),
              OutlinedButton.icon(
                onPressed: () => showActivityCenter(context, tab: 2),
                icon: const Icon(Icons.restore_rounded),
                label: const Text('注册表备份'),
              ),
              OutlinedButton.icon(
                onPressed: () => showDuplicateFiles(context),
                icon: const Icon(Icons.find_in_page_outlined),
                label: const Text('重复文件检查'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              leading: const Icon(
                Icons.shield_outlined,
                color: AppColors.success,
              ),
              title: const Text(
                '清理保护规则',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                '个人文件保护 · 默认保守勾选',
                style: TextStyle(fontSize: 11),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              children: const [
                Text(
                  '1. 不清理「文档 / 图片 / 桌面 / 视频 / 音乐」等个人目录。\n'
                  '2. 不清理浏览器的 Cookie、密码、书签、历史中的登录态。\n'
                  '3. 下载目录默认不勾选任何文件。\n'
                  '4. 被占用的文件自动跳过，不会强制结束进程。\n'
                  '5. 仅处理明确列出的缓存、日志与手动勾选项目，不删除系统程序文件。',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.7,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            '关于',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Image.asset(
                'assets/icon/cleanwin_icon.png',
                width: 40,
                height: 40,
                semanticLabel: 'CleanWin Logo',
              ),
              title: const Text(
                'CleanWin',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Flutter Windows · v1.0.0'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final IconData icon;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: subtitle,
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        selected: value,
        selectedTileColor: AppColors.primary.withValues(alpha: 0.035),
        secondary: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: value ? AppColors.primarySoft : AppColors.bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            size: 20,
            color: onChanged == null
                ? AppColors.textTertiary
                : value
                ? AppColors.primary
                : AppColors.textSecondary,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        value: value,
        onChanged: onChanged,
        activeThumbColor: Colors.white,
        activeTrackColor: AppColors.primary,
        inactiveThumbColor: Colors.white,
        inactiveTrackColor: AppColors.border,
        thumbIcon: WidgetStateProperty.resolveWith(
          (states) => Icon(
            states.contains(WidgetState.selected)
                ? Icons.check_rounded
                : Icons.remove_rounded,
            size: 16,
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.textTertiary,
          ),
        ),
      ),
    );
  }
}
