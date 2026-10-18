import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'common.dart';

/// 模块页面统一骨架：页头 + 工具栏 + 内容区
class ModulePageShell extends StatelessWidget {
  const ModulePageShell({
    super.key,
    required this.title,
    this.subtitle,
    this.toolbar,
    this.banner,
    required this.child,
    this.childPadding,
  });

  final String title;
  final String? subtitle;
  final Widget? toolbar;
  final Widget? banner;
  final Widget child;
  final EdgeInsets? childPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: kPagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ModuleHeader(title: title, subtitle: subtitle, toolbar: toolbar),
          if (banner != null) ...[const SizedBox(height: 14), banner!],
          const SizedBox(height: 16),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 宽窗口标题与操作同行，窄窗口分层，避免长说明和按钮争抢宽度。
class ModuleHeader extends StatelessWidget {
  const ModuleHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.toolbar,
  });
  final String title;
  final String? subtitle;
  final Widget? toolbar;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final heading = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -.5,
            ),
          ),
          if (subtitle != null) InfoHint(subtitle!),
        ],
      );
      if (toolbar != null && constraints.maxWidth >= 880) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: heading),
            const SizedBox(width: 24),
            SizedBox(
              width: constraints.maxWidth * .54,
              child: Align(alignment: Alignment.centerRight, child: toolbar!),
            ),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading,
          if (toolbar != null) ...[
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerLeft, child: toolbar!),
          ],
        ],
      );
    },
  );
}

/// 默认只显示搜索图标；收起时清空条件，避免隐藏的搜索影响列表。
class ModuleSearchField extends StatefulWidget {
  const ModuleSearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.controller,
    this.fieldKey,
  });
  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final Key? fieldKey;
  @override
  State<ModuleSearchField> createState() => _ModuleSearchFieldState();
}

class _ModuleSearchFieldState extends State<ModuleSearchField> {
  late final TextEditingController _controller;
  final _focus = FocusNode();
  bool _expanded = false;
  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _expanded = _controller.text.isNotEmpty;
    _controller.addListener(_textChanged);
  }

  void _textChanged() {
    if (mounted) setState(() {});
  }

  void _close() {
    _controller.clear();
    widget.onChanged('');
    _focus.unfocus();
    setState(() => _expanded = false);
  }

  @override
  void dispose() {
    _controller.removeListener(_textChanged);
    if (widget.controller == null) _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Align(
      alignment: Alignment.centerRight,
      widthFactor: 1,
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        width: _expanded ? math.min(300, constraints.maxWidth) : 40,
        height: 40,
        child: !_expanded
            ? IconButton.outlined(
                tooltip: '搜索',
                icon: const Icon(Icons.search_rounded, size: 20),
                onPressed: () {
                  setState(() => _expanded = true);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _expanded) _focus.requestFocus();
                  });
                },
              )
            : ClipRect(
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  minWidth: math.min(300, constraints.maxWidth),
                  maxWidth: math.min(300, constraints.maxWidth),
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.escape): _close,
                    },
                    child: TextField(
                      key: widget.fieldKey,
                      controller: _controller,
                      focusNode: _focus,
                      onChanged: widget.onChanged,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: widget.hint,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        prefixIcon: const Icon(Icons.search_rounded, size: 19),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_controller.text.isNotEmpty)
                              IconButton(
                                tooltip: '清空搜索',
                                icon: const Icon(
                                  Icons.backspace_outlined,
                                  size: 17,
                                ),
                                onPressed: () {
                                  _controller.clear();
                                  widget.onChanged('');
                                  _focus.requestFocus();
                                },
                              ),
                            IconButton(
                              tooltip: '收起搜索',
                              icon: const Icon(Icons.close_rounded, size: 17),
                              onPressed: _close,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    ),
  );
}

class ModuleSelectItem<T> {
  const ModuleSelectItem({required this.value, required this.child});
  final T value;
  final Widget child;
}

/// 统一的自定义选择器：圆角入口、选中标记、受限高度菜单和键盘导航。
class ModuleSelect<T> extends StatefulWidget {
  const ModuleSelect({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.label = '选择筛选条件',
  });
  final T? value;
  final List<ModuleSelectItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String label;
  @override
  State<ModuleSelect<T>> createState() => _ModuleSelectState<T>();
}

class _ModuleSelectState<T> extends State<ModuleSelect<T>> {
  bool _open = false;
  bool _hovered = false;
  T? get value => widget.value;
  List<ModuleSelectItem<T>> get items => widget.items;
  ValueChanged<T?>? get onChanged => widget.onChanged;
  String get label => widget.label;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final enabled = onChanged != null && items.isNotEmpty;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160);
    final selected = items.where((item) => item.value == value).firstOrNull;
    return Theme(
      // PopupMenuRoute paints initialValue with highlightColor. The rounded
      // selection below owns that background so there is only one layer.
      data: theme.copyWith(highlightColor: Colors.transparent),
      child: PopupMenuButton<T>(
        tooltip: label,
        enabled: onChanged != null && items.isNotEmpty,
        initialValue: value,
        position: PopupMenuPosition.under,
        offset: const Offset(0, 6),
        constraints: const BoxConstraints(
          minWidth: 200,
          maxWidth: 320,
          maxHeight: 360,
        ),
        color: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: theme.colorScheme.outlineVariant, width: 1.6),
        ),
        onOpened: () => setState(() => _open = true),
        onCanceled: () => setState(() => _open = false),
        onSelected: (value) {
          setState(() => _open = false);
          onChanged?.call(value);
        },
        itemBuilder: (context) => [
          for (final item in items)
            PopupMenuItem<T>(
              value: item.value,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Semantics(
                selected: item.value == value,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: item.value == value
                        ? accent.withValues(alpha: .1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: DefaultTextStyle.merge(
                          style: const TextStyle(fontSize: 13),
                          child: item.child,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.check_rounded,
                        size: 17,
                        color: item.value == value
                            ? accent
                            : Colors.transparent,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
        child: Semantics(
          button: true,
          enabled: onChanged != null && items.isNotEmpty,
          child: MouseRegion(
            cursor: enabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: AnimatedContainer(
              duration: duration,
              constraints: const BoxConstraints(maxWidth: 260, minHeight: 40),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: onChanged == null
                    ? AppColors.border.withValues(alpha: .3)
                    : _open || _hovered
                    ? Color.alphaBlend(
                        accent.withValues(alpha: .06),
                        theme.colorScheme.surface,
                      )
                    : theme.colorScheme.surface,
                border: Border.all(
                  width: _open ? 2 : 1.6,
                  color: _open || (_hovered && enabled)
                      ? accent.withValues(alpha: .6)
                      : theme.colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: DefaultTextStyle.merge(
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: onChanged == null
                            ? AppColors.textTertiary
                            : AppColors.textPrimary,
                      ),
                      child: selected?.child ?? Text(label),
                    ),
                  ),
                  const SizedBox(width: 12),
                  AnimatedRotation(
                    turns: _open ? .5 : 0,
                    duration: duration,
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 18,
                      color: _open ? accent : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 列表标题与查找、筛选同行；窄窗口按组换行。
class ListToolbar extends StatelessWidget {
  const ListToolbar({
    super.key,
    required this.title,
    required this.actions,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final heading = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (subtitle != null) InfoHint(subtitle!),
        ],
      );
      final controls = Toolbar(children: actions);
      if (constraints.maxWidth >= 720) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: heading),
            const SizedBox(width: 16),
            SizedBox(
              width: constraints.maxWidth * .60,
              child: Align(alignment: Alignment.centerRight, child: controls),
            ),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [heading, const SizedBox(height: 10), controls],
      );
    },
  );
}

/// 顶部操作条（按钮组）
class Toolbar extends StatelessWidget {
  const Toolbar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      alignment: WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}

/// 统一列表卡片（表头 + 列表）
class ListCard extends StatelessWidget {
  const ListCard({super.key, this.header, required this.child, this.height});

  final Widget? header;
  final Widget child;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final content = Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (header != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.45),
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.textTertiary.withValues(alpha: 0.2),
                  ),
                ),
              ),
              child: header!,
            ),
          Expanded(child: child),
        ],
      ),
    );
    if (height != null) {
      return SizedBox(height: height, child: content);
    }
    return Expanded(child: content);
  }
}

/// 表头单元格
class ListHeaderCell extends StatelessWidget {
  const ListHeaderCell(this.text, {super.key, this.width});

  final String text;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final t = Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    );
    if (width == null) return Expanded(child: t);
    return SizedBox(width: width, child: t);
  }
}

/// 状态胶囊
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
