import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'page_shell.dart';

/// 两个空间分析页面共用的盘符选择入口。
class DiskDriveSelect extends StatelessWidget {
  const DiskDriveSelect({
    super.key,
    required this.value,
    required this.roots,
    required this.onChanged,
  });

  final String? value;
  final List<String> roots;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 144,
    child: ModuleSelect<String>(
      label: '切换磁盘',
      value: value,
      items: [
        for (final root in roots)
          ModuleSelectItem(
            value: root,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.storage_rounded,
                  size: 17,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    root.length <= 3 ? '磁盘 ${root.replaceAll('\\', '')}' : root,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
      onChanged: onChanged,
    ),
  );
}

/// 范围选择在左，固定操作在右；左侧换行不会打乱操作顺序。
class DiskActionBar extends StatelessWidget {
  const DiskActionBar({
    super.key,
    required this.leading,
    required this.trailing,
  });
  final List<Widget> leading;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: Toolbar(children: leading)),
      const SizedBox(width: 12),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < trailing.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            trailing[i],
          ],
        ],
      ),
    ],
  );
}
