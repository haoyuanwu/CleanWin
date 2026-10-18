import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/clean_models.dart';
import '../services/path_utils.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/clean_progress_dialog.dart';
import '../widgets/common.dart';
import '../widgets/page_shell.dart';
import '../widgets/clean_overview.dart';
import '../widgets/cosmic_scene.dart';

class CleanPage extends StatefulWidget {
  const CleanPage({super.key});

  @override
  State<CleanPage> createState() => _CleanPageState();
}

class _CleanPageState extends State<CleanPage> {
  String _categoryQuery = '';
  bool _onlyWithResults = false;
  CleanCategory? _focusedCategory;
  final _scroll = ScrollController();
  final _resultsKey = GlobalKey();
  final _heroKey = GlobalKey();
  ThemeData? _cosmicTheme;
  DateTime? _celebrationAt;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _focusCategory(CleanCategory category) {
    setState(() {
      _focusedCategory = category;
      _categoryQuery = '';
      _onlyWithResults = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _resultsKey.currentContext;
      if (!mounted) return;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          duration: cleanMotion(context, 450),
          curve: Curves.easeOutCubic,
        );
      } else if (_scroll.hasClients) {
        _viewResults();
      }
    });
  }

  void _viewResults() {
    if (!_scroll.hasClients) return;
    final hero = _heroKey.currentContext?.findRenderObject() as RenderBox?;
    if (hero != null) {
      final offset = hero.size.height.clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(offset);
        return;
      }
      _scroll.animateTo(
        offset,
        duration: cleanMotion(context, 450),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _startScan() async {
    final state = context.read<AppState>();
    if (state.scanning || state.cleaning) return;
    setState(() => _focusedCategory = null);
    try {
      await state.scan(force: true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('扫描未完成，请重试；已读取内容保留供查看')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final showResults = state.scanGeneration > 0 && state.hasResults;
    final busy = state.scanning || state.cleaning;
    final smartItems = state.categories
        .where((category) => cosmicSmartCategories.contains(category.category))
        .expand((category) => category.items)
        .where((item) => item.selected)
        .toList();
    final smartBytes = smartItems.fold<int>(
      0,
      (sum, item) => sum + item.sizeBytes,
    );
    final manualCount = state.categories
        .where((category) => !cosmicSmartCategories.contains(category.category))
        .fold<int>(0, (sum, category) => sum + category.selectedCount);
    final visibleCategories = state.categories
        .where(
          (category) =>
              (_focusedCategory == null ||
                  category.category == _focusedCategory) &&
              (!_onlyWithResults || category.items.isNotEmpty) &&
              category.category.title.toLowerCase().contains(
                _categoryQuery.trim().toLowerCase(),
              ),
        )
        .toList();
    final base = Theme.of(context);
    final theme = base.copyWith(
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: CosmicColors.cyan,
        secondary: CosmicColors.violet,
        surface: CosmicColors.panel,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      iconTheme: const IconThemeData(color: CosmicColors.muted),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: CosmicColors.cyan,
          disabledForegroundColor: CosmicColors.muted,
        ),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: CosmicColors.panel,
        surfaceTintColor: Colors.transparent,
      ),
      dividerColor: CosmicColors.line,
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        fillColor: const Color(0xFF15213A),
        filled: true,
        hintStyle: const TextStyle(color: CosmicColors.muted, fontSize: 12),
        prefixIconColor: CosmicColors.cyan,
        suffixIconColor: CosmicColors.muted,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? CosmicColors.cyan
              : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(CosmicColors.background),
        side: const BorderSide(color: CosmicColors.muted),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: CosmicColors.panel,
        selectedColor: const Color(0xFF243D53),
        labelStyle: const TextStyle(
          color: CosmicColors.muted,
          fontSize: 12,
          fontFamily: 'Segoe UI',
        ),
        side: const BorderSide(color: CosmicColors.line),
      ),
    );
    _cosmicTheme = theme;
    return Theme(
      data: theme,
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: CosmicBackdrop(
            child: Padding(
              padding: kPagePadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 17,
                        color: CosmicColors.cyan,
                      ),
                      SizedBox(width: 9),
                      Text(
                        '概览与清理',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      Spacer(),
                      Text(
                        'COSMIC / 01',
                        style: TextStyle(
                          fontSize: 10,
                          color: CosmicColors.muted,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: CustomScrollView(
                      controller: _scroll,
                      key: const PageStorageKey('clean-workspace'),
                      slivers: [
                        SliverToBoxAdapter(
                          child: CleanOverview(
                            key: _heroKey,
                            state: state,
                            hasResults: showResults,
                            cleanedAt: _celebrationAt,
                            onScan: _startScan,
                            smartBytes: smartBytes,
                            onSmartClean:
                                busy || smartItems.isEmpty || !showResults
                                ? null
                                : () => _confirmClean(context),
                            onCategory: _focusCategory,
                            onViewResults: _viewResults,
                          ),
                        ),
                        if (showResults) ...[
                          SliverToBoxAdapter(
                            child: Padding(
                              key: _resultsKey,
                              padding: const EdgeInsets.only(
                                top: 24,
                                bottom: 14,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          '扫描结果',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '${state.results.length} 个星域',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: CosmicColors.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Toolbar(
                                    children: [
                                      if (_focusedCategory != null)
                                        OutlinedButton.icon(
                                          onPressed: () => setState(
                                            () => _focusedCategory = null,
                                          ),
                                          icon: const Icon(
                                            Icons.arrow_back_rounded,
                                            size: 16,
                                          ),
                                          label: const Text('全部星域'),
                                        ),
                                      ModuleSearchField(
                                        hint: '查找清理分类…',
                                        onChanged: (value) => setState(
                                          () => _categoryQuery = value,
                                        ),
                                      ),
                                      FilterChip(
                                        label: const Text('只看有结果'),
                                        selected: _onlyWithResults,
                                        onSelected: (value) => setState(
                                          () => _onlyWithResults = value,
                                        ),
                                      ),
                                      const Text(
                                        '点击分类查看文件',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: CosmicColors.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (visibleCategories.isEmpty)
                            const SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.all(26),
                                child: Center(
                                  child: Text(
                                    '没有匹配的分类',
                                    style: TextStyle(color: CosmicColors.muted),
                                  ),
                                ),
                              ),
                            ),
                          SliverList.builder(
                            itemCount: visibleCategories.length,
                            itemBuilder: (context, index) {
                              final category = visibleCategories[index];
                              return _ResultEntrance(
                                key: ValueKey(
                                  '${state.scanGeneration}_${category.category.name}',
                                ),
                                index: index,
                                child: _CategoryCard(
                                  key: ValueKey(
                                    '${category.category.name}-${_focusedCategory == category.category}',
                                  ),
                                  category: category,
                                  initiallyExpanded:
                                      _focusedCategory == category.category,
                                ),
                              );
                            },
                          ),
                        ],
                        const SliverToBoxAdapter(child: SizedBox(height: 18)),
                      ],
                    ),
                  ),
                  if (showResults)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: CosmicColors.panel,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: CosmicColors.cyan.withValues(alpha: .25),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: CosmicColors.cyan.withValues(alpha: .04),
                              blurRadius: 20,
                            ),
                          ],
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final amount = Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '智能推荐 · ${smartItems.length} 项',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: CosmicColors.muted,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                AnimatedByteCount(
                                  bytes: smartBytes,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: CosmicColors.cyan,
                                  ),
                                ),
                              ],
                            );
                            final actions = Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                if (manualCount > 0)
                                  TextButton(
                                    onPressed: busy
                                        ? null
                                        : () => _confirmClean(
                                            context,
                                            smart: false,
                                          ),
                                    child: const Text('清理其他所选'),
                                  ),
                                ElevatedButton.icon(
                                  onPressed: busy || smartItems.isEmpty
                                      ? null
                                      : () => _confirmClean(context),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: CosmicColors.cyan,
                                    foregroundColor: CosmicColors.background,
                                    disabledBackgroundColor: const Color(
                                      0xFF26364A,
                                    ),
                                    disabledForegroundColor: CosmicColors.muted,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 22,
                                      vertical: 19,
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.auto_awesome_rounded,
                                    size: 18,
                                  ),
                                  label: Text(state.cleaning ? '清理中…' : '智能清理'),
                                ),
                              ],
                            );
                            if (constraints.maxWidth < 440) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  amount,
                                  const SizedBox(height: 8),
                                  actions,
                                ],
                              );
                            }
                            return Row(
                              children: [
                                Expanded(child: amount),
                                const SizedBox(width: 10),
                                actions,
                              ],
                            );
                          },
                        ),
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

  Future<void> _confirmClean(BuildContext context, {bool smart = true}) async {
    final state = context.read<AppState>();
    if (state.scanning || state.cleaning || state.scanGeneration == 0) return;
    final categories = smart
        ? cosmicSmartCategories
        : CleanCategory.values
              .where((category) => !cosmicSmartCategories.contains(category))
              .toSet();
    final items = state.categories
        .where((category) => categories.contains(category.category))
        .expand((category) => category.items)
        .where((item) => item.selected)
        .toList();
    if (items.isEmpty) return;
    final bytes = items.fold<int>(0, (sum, item) => sum + item.sizeBytes);
    if (state.options.confirmBeforeClean) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => Theme(
          data: _cosmicTheme ?? Theme.of(context),
          child: AlertDialog(
            title: Text(smart ? '智能清理' : '清理其他所选'),
            content: Text(
              '将清理 ${items.length} 个已勾选项目，预计释放 ${formatBytes(bytes)}。\n\n${smart ? '本次仅处理系统、浏览器、软件及显卡缓存。' : '本次包含需要手动确认的内容。'}删除后通常无法恢复。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('确认清理'),
              ),
            ],
          ),
        ),
      );
      if (ok != true || !context.mounted || state.scanning || state.cleaning) {
        return;
      }
    }
    if (context.mounted) {
      final before = state.lastCleanAt;
      final report = await showDialog<CleanReport>(
        context: context,
        barrierDismissible: false,
        builder: (_) => Theme(
          data: _cosmicTheme ?? Theme.of(context),
          child: CleanProgressDialog(categories: categories),
        ),
      );
      if (mounted && report?.cancelled != true && state.lastCleanAt != before) {
        setState(() => _celebrationAt = state.lastCleanAt);
      }
    }
  }
}

class _ResultEntrance extends StatelessWidget {
  const _ResultEntrance({super.key, required this.index, required this.child});
  final int index;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final delay = (index % 6) * 35;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: cleanMotion(context, 320 + delay),
      curve: Interval(delay / (320 + delay), 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (_, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - value)),
          child: child,
        ),
      ),
    );
  }
}

class _CategoryCard extends StatefulWidget {
  const _CategoryCard({
    super.key,
    required this.category,
    this.initiallyExpanded = false,
  });
  final ScanCategory category;
  final bool initiallyExpanded;
  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  late bool _expanded = widget.initiallyExpanded;
  ScanCategory get category => widget.category;
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final busy = state.scanning || state.cleaning;
    final bool? selected = category.selectedCount == 0
        ? false
        : category.selectedCount == category.items.length
        ? true
        : null;
    final fraction = state.totalFoundBytes <= 0
        ? 0.0
        : (category.totalSizeBytes / state.totalFoundBytes).clamp(0.0, 1.0);
    final color = category.error != null
        ? AppColors.warning
        : category.items.isEmpty
        ? AppColors.success
        : !category.category.defaultSelected
        ? AppColors.warning
        : CosmicColors.cyan;
    return AnimatedContainer(
      duration: cleanMotion(context, 180),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: CosmicColors.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: category.selectedCount > 0
              ? CosmicColors.cyan.withValues(alpha: 0.2)
              : CosmicColors.line,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: PageStorageKey(
                  'category-${category.category.name}-${widget.initiallyExpanded}',
                ),
                initiallyExpanded: widget.initiallyExpanded,
                onExpansionChanged: (value) =>
                    setState(() => _expanded = value),
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                shape: const Border(),
                collapsedShape: const Border(),
                leading: CategoryIcon(category: category.category, size: 42),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        category.category.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedByteCount(
                      bytes: category.totalSizeBytes,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${category.items.length} 项 · ${category.category.subtitle}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: CosmicColors.muted,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Icon(
                            category.error != null
                                ? Icons.info_outline_rounded
                                : category.items.isEmpty
                                ? Icons.check_circle_outline_rounded
                                : Icons.circle,
                            size:
                                category.items.isEmpty || category.error != null
                                ? 12
                                : 6,
                            color: color,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              category.error != null
                                  ? '部分位置未读取，展开查看'
                                  : category.items.isEmpty
                                  ? '已检查，未发现可清理内容'
                                  : !category.category.defaultSelected
                                  ? '需手动确认'
                                  : '已就绪，可展开预览',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 10, color: color),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onSecondaryTapDown: busy
                          ? null
                          : (details) => _showCategoryMenu(
                              context,
                              state,
                              details.globalPosition,
                            ),
                      child: Checkbox(
                        value: selected,
                        tristate: true,
                        onChanged: busy || category.items.isEmpty
                            ? null
                            : (_) => state.toggleCategory(
                                category,
                                selected != true,
                              ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: cleanMotion(context, 180),
                      child: const Icon(
                        Icons.expand_more_rounded,
                        size: 20,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
                children: [
                  if (category.error != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        category.error!,
                        style: const TextStyle(
                          color: AppColors.warning,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  if (category.items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        category.error == null ? '未发现可清理内容' : '请检查提示后重新扫描',
                        style: const TextStyle(
                          color: CosmicColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    )
                  else
                    for (final item in category.items)
                      _ItemRow(
                        item: item,
                        enabled: !busy,
                        onToggle: () => state.toggleItem(item),
                        onShowMenu: (position) =>
                            _showItemMenu(context, state, item, position),
                      ),
                ],
              ),
            ),
            Tooltip(
              message: '占已发现内容的 ${(fraction * 100).toStringAsFixed(1)}%',
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: fraction),
                duration: cleanMotion(context, 400),
                builder: (_, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 3,
                  color: color.withValues(alpha: 0.45),
                  backgroundColor: AppColors.bg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCategoryMenu(
    BuildContext context,
    AppState state,
    Offset pos,
  ) async {
    final count = category.items.length;
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: const [
        PopupMenuItem(
          value: 'whitelist_all',
          child: _MenuRow(
            icon: Icons.verified_user_outlined,
            label: '整个分类加入白名单',
          ),
        ),
      ],
    );
    if (!context.mounted || result != 'whitelist_all') return;
    final saved = await state.addCategoryToWhitelist(category);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? '已将「${category.category.title}」下 $count 个路径加入白名单'
                : state.whitelistError ?? '保护路径未能保存',
          ),
        ),
      );
    }
  }

  Future<void> _showItemMenu(
    BuildContext context,
    AppState state,
    CleanItem item,
    Offset pos,
  ) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: [
        const PopupMenuItem(
          value: 'whitelist',
          child: _MenuRow(
            icon: Icons.verified_user_outlined,
            label: '加入白名单',
            color: AppColors.success,
          ),
        ),
        const PopupMenuItem(
          value: 'copy',
          child: _MenuRow(icon: Icons.copy_rounded, label: '复制路径'),
        ),
        const PopupMenuItem(
          value: 'reveal',
          child: _MenuRow(icon: Icons.folder_open_rounded, label: '在资源管理器中打开'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'toggle',
          child: _MenuRow(
            icon: item.selected
                ? Icons.check_box_outline_blank_rounded
                : Icons.check_box_rounded,
            label: item.selected ? '取消勾选' : '勾选此项',
          ),
        ),
      ],
    );
    if (!context.mounted) return;

    switch (result) {
      case 'whitelist':
        final saved = await state.addToWhitelist(item);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                saved
                    ? '已将「${item.name}」加入白名单'
                    : state.whitelistError ?? '保护路径未能保存',
              ),
            ),
          );
        }
      case 'copy':
        await state.copyToClipboard(item.path);
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('路径已复制到剪贴板')));
        }
      case 'reveal':
        await state.revealInExplorer(item.path);
      case 'toggle':
        state.toggleItem(item);
    }
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    this.enabled = true,
    required this.onToggle,
    required this.onShowMenu,
  });

  final CleanItem item;
  final bool enabled;
  final VoidCallback onToggle;
  final void Function(Offset globalPos) onShowMenu;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapDown: enabled ? (d) => onShowMenu(d.globalPosition) : null,
      child: InkWell(
        onTap: enabled ? onToggle : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Row(
            children: [
              Checkbox(
                value: item.selected,
                onChanged: enabled ? (_) => onToggle() : null,
              ),
              // 软件缓存显示 logo
              if (item.iconPath != null) ...[
                const SizedBox(width: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(
                    File(item.iconPath!),
                    width: 28,
                    height: 28,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const SizedBox(
                      width: 28,
                      height: 28,
                      child: Icon(Icons.apps_rounded, size: 18),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                    if (item.note != null)
                      Text(
                        item.note!,
                        style: const TextStyle(
                          color: AppColors.warning,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Tooltip(
                message:
                    '${item.appName ?? item.category.title}\n${item.cleanupImpact}',
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  item.fileCount > 0 ? '${item.fileCount} 文件' : '—',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 72, child: SizeText(item.sizeBytes)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color ?? CosmicColors.muted),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontSize: 13, color: color)),
      ],
    );
  }
}
