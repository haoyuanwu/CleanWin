import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/clean_models.dart';
import '../models/workspace_structure.dart';
import '../services/path_utils.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/module_theme.dart';
import '../widgets/clean_progress_dialog.dart';
import '../widgets/common.dart';
import '../widgets/page_shell.dart';
import '../widgets/clean_overview.dart';
import '../widgets/cosmic_scene.dart';
import '../widgets/system_cleanup_panel.dart';

class CleanPage extends StatefulWidget {
  const CleanPage({super.key, this.onNavigate});
  final ValueChanged<int>? onNavigate;

  @override
  State<CleanPage> createState() => _CleanPageState();
}

class _CleanPageState extends State<CleanPage> {
  String _categoryQuery = '';
  CleanCategory? _focusedCategory;
  final _scroll = ScrollController();
  final _resultsKey = GlobalKey();
  final _heroKey = GlobalKey();
  ThemeData? _cosmicTheme;
  DateTime? _celebrationAt;
  bool _occupiedOperation = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _focusCategory(CleanCategory category) {
    setState(() {
      _focusedCategory = category;
      _categoryQuery = '';
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
    final results = _resultsKey.currentContext;
    if (results != null) {
      Scrollable.ensureVisible(
        results,
        duration: cleanMotion(context, 450),
        curve: Curves.easeOutCubic,
      );
      return;
    }
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
    if (state.scanning || state.cleaning || _occupiedOperation) return;
    setState(() => _focusedCategory = null);
    try {
      await state.scanOverview();
      if (mounted) await _offerOccupiedRescan(state);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('扫描未完成，请重试；已读取内容保留供查看')));
      }
    }
  }

  Future<void> _offerOccupiedRescan(AppState state) async {
    final paths = state.scannedInUsePaths;
    if (paths.isEmpty || !mounted) return;
    final session = await state.openScannedOccupiedSession();
    if (!mounted) {
      await session?.dispose();
      return;
    }
    if (session == null || session.applications.isEmpty) {
      await session?.dispose();
      return;
    }
    final processIds = await showDialog<Set<int>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Theme(
        data: _cosmicTheme ?? Theme.of(context),
        child: OccupiedAppsDialog(
          applications: session.applications,
          fileCount: paths.length,
          forCleanup: false,
          canCloseAndRestore: session.canCloseAndRestore,
        ),
      ),
    );
    if (processIds == null || processIds.isEmpty || !mounted) {
      await session.dispose();
      return;
    }
    setState(() => _occupiedOperation = true);
    var closed = false;
    try {
      closed = await session.close(processIds);
      if (!closed) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('软件没有正常退出，已保留占用文件')));
        }
        return;
      }
      await state.scanOverview();
    } finally {
      final restored = closed ? await session.restore() : true;
      if (!closed) await session.dispose();
      if (mounted) {
        setState(() => _occupiedOperation = false);
        if (!restored) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('扫描已完成，但部分软件未能自动重新打开')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final overviewCategories = state.categories
        .where((category) => cleanupOwner(category.category) == 0)
        .toList();
    final showResults =
        state.scanGeneration > 0 && overviewCategories.isNotEmpty;
    final busy =
        state.scanning ||
        state.cleaning ||
        state.systemCleanup.busy ||
        _occupiedOperation;
    final smartItems = state.categories
        .where((category) => cosmicSmartCategories.contains(category.category))
        .expand((category) => category.items)
        .where((item) => item.selected)
        .toList();
    final smartBytes = smartItems.fold<int>(
      0,
      (sum, item) => sum + item.sizeBytes,
    );
    final overviewItems = overviewCategories
        .expand((category) => category.items)
        .where((item) => item.selected)
        .toList();
    final selectedBytes = overviewItems.fold<int>(
      0,
      (sum, item) => sum + item.sizeBytes,
    );
    final selectedCount = overviewItems.length;
    final manualCount = selectedCount - smartItems.length;
    final manualBytes = selectedBytes - smartBytes;
    final cleanedSinceScan =
        state.lastCleanAt != null &&
        (state.lastScanAt == null ||
            !state.lastCleanAt!.isBefore(state.lastScanAt!));
    final visibleCategories =
        overviewCategories
            .where(
              (category) =>
                  (!cleanedSinceScan ||
                      category.items.isNotEmpty ||
                      category.category == CleanCategory.appCache ||
                      category.error != null) &&
                  (_focusedCategory == null ||
                      category.category == _focusedCategory) &&
                  category.category.title.toLowerCase().contains(
                    _categoryQuery.trim().toLowerCase(),
                  ),
            )
            .toList()
          ..sort((a, b) {
            final sectionOrder = CleanupSection.of(a.category).index
                .compareTo(CleanupSection.of(b.category).index);
            if (sectionOrder != 0) return sectionOrder;
            final order = CleanupSection.of(a.category).categories;
            return order
                .indexOf(a.category)
                .compareTo(order.indexOf(b.category));
          });
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
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: base.outlinedButtonTheme.style?.copyWith(
          foregroundColor: const WidgetStatePropertyAll(CosmicColors.cyan),
          backgroundColor: const WidgetStatePropertyAll(Color(0xFF233D4A)),
          side: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused)
                ? const BorderSide(color: CosmicColors.cyan, width: 2)
                : BorderSide.none,
          ),
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
    return ScrollConfiguration(
      behavior: const CleanScrollBehavior(showScrollbars: false),
      child: Theme(
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
                    Row(
                      children: [
                        const Icon(
                          Icons.auto_awesome_rounded,
                          size: 17,
                          color: CosmicColors.cyan,
                        ),
                        const SizedBox(width: 9),
                        const Text(
                          '概览与清理',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        const Text(
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
                              onSmartClean:
                                  busy || selectedCount == 0 || !showResults
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
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
                                          '${visibleCategories.length} 类',
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
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (visibleCategories.isEmpty)
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.all(26),
                                  child: Center(
                                    child: Text(
                                      cleanedSinceScan &&
                                              _categoryQuery.isEmpty &&
                                              _focusedCategory == null
                                          ? '已选项目已处理，暂无剩余内容'
                                          : '没有匹配的分类',
                                      style: TextStyle(
                                        color: CosmicColors.muted,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            SliverList.builder(
                              findChildIndexCallback: (key) {
                                final index = visibleCategories.indexWhere(
                                  (category) =>
                                      key ==
                                      ValueKey(
                                        '${state.scanGeneration}_${category.category.name}',
                                      ),
                                );
                                return index < 0 ? null : index;
                              },
                              itemCount: visibleCategories.length,
                              itemBuilder: (context, index) {
                                final category = visibleCategories[index];
                                return _ResultEntrance(
                                  key: ValueKey(
                                    '${state.scanGeneration}_${category.category.name}',
                                  ),
                                  index: index,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (index == 0 ||
                                          CleanupSection.of(
                                                visibleCategories[index - 1]
                                                    .category,
                                              ) !=
                                              CleanupSection.of(
                                                category.category,
                                              ))
                                        _CleanupSectionHeader(
                                          section: CleanupSection.of(
                                            category.category,
                                          ),
                                          categories: visibleCategories
                                              .where(
                                                (entry) =>
                                                    CleanupSection.of(
                                                      entry.category,
                                                    ) ==
                                                    CleanupSection.of(
                                                      category.category,
                                                    ),
                                              )
                                              .toList(),
                                        ),
                                      _CategoryCard(
                                        key: ValueKey(
                                          '${category.category.name}-${_focusedCategory == category.category}',
                                        ),
                                        category: category,
                                        initiallyExpanded:
                                            _focusedCategory ==
                                            category.category,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 18),
                              child: SystemCleanupPanel(state: state),
                            ),
                          ),
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
                                    '已选 · $selectedCount 项',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: CosmicColors.muted,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  AnimatedByteCount(
                                    key: const ValueKey('clean-selected-total'),
                                    bytes: selectedBytes,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      color: CosmicColors.cyan,
                                    ),
                                  ),
                                  if (manualCount > 0) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      '缓存 ${formatBytes(smartBytes)} · 其他所选 ${formatBytes(manualBytes)}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: CosmicColors.muted,
                                      ),
                                    ),
                                  ],
                                ],
                              );
                              final actions = Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: busy || selectedCount == 0
                                        ? null
                                        : () => _confirmClean(context),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: CosmicColors.cyan,
                                      foregroundColor: CosmicColors.background,
                                      disabledBackgroundColor: const Color(
                                        0xFF26364A,
                                      ),
                                      disabledForegroundColor:
                                          CosmicColors.muted,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 22,
                                        vertical: 19,
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.auto_awesome_rounded,
                                      size: 18,
                                    ),
                                    label: Text(
                                      state.cleaning ? '清理中…' : '智能清理',
                                    ),
                                  ),
                                ],
                              );
                              if (constraints.maxWidth < 440) {
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
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
      ),
    );
  }

  Future<void> _confirmClean(BuildContext context) async {
    final state = context.read<AppState>();
    if (state.scanning ||
        state.cleaning ||
        _occupiedOperation ||
        state.scanGeneration == 0) {
      return;
    }
    final items = state.categories
        .expand((category) => category.items)
        .where((item) => item.selected && cleanupOwner(item.category) == 0)
        .toList();
    final categories = items.map((item) => item.category).toSet();
    final requiresManualConfirmation = categories.any(
      (category) => !cosmicSmartCategories.contains(category),
    );
    if (items.isEmpty) return;
    final bytes = items.fold<int>(0, (sum, item) => sum + item.sizeBytes);
    final recycledBytes = items
        .where((item) => item.category == CleanCategory.downloads)
        .fold<int>(0, (sum, item) => sum + item.sizeBytes);
    if (state.options.confirmBeforeClean || requiresManualConfirmation) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => Theme(
          data: _cosmicTheme ?? Theme.of(context),
          child: CleanConfirmationDialog(
            title: '智能清理',
            count: items.length,
            bytes: bytes,
            recycledBytes: recycledBytes,
            description: categories.contains(CleanCategory.recycleBin)
                ? '勾选的已有回收站内容将永久删除；下载文件移入回收站后仍可恢复。'
                : recycledBytes > 0
                ? '下载文件移入回收站，可恢复；所选缓存删除后通常无法恢复。'
                : '仅处理本次已勾选的项目；缓存删除后通常无法恢复。',
          ),
        ),
      );
      if (ok != true || !context.mounted || state.scanning || state.cleaning) {
        return;
      }
    }
    if (context.mounted) {
      final occupied = await state.openSelectedOccupiedSession(
        categories: categories,
      );
      if (!mounted) {
        await occupied?.dispose();
        return;
      }
      var closed = false;
      if (occupied != null && occupied.applications.isNotEmpty) {
        final processIds = await showDialog<Set<int>>(
          context: this.context,
          barrierDismissible: false,
          builder: (_) => Theme(
            data: _cosmicTheme ?? Theme.of(this.context),
            child: OccupiedAppsDialog(
              applications: occupied.applications,
              fileCount: occupied.fileCount,
              forCleanup: true,
              canCloseAndRestore: occupied.canCloseAndRestore,
            ),
          ),
        );
        if (processIds != null && processIds.isNotEmpty && mounted) {
          setState(() => _occupiedOperation = true);
          closed = await occupied.close(processIds);
          if (!closed && mounted) {
            ScaffoldMessenger.of(this.context).showSnackBar(
              const SnackBar(content: Text('软件没有正常退出，占用文件将在清理时跳过')),
            );
          }
        }
      }
      final before = state.lastCleanAt;
      CleanReport? report;
      try {
        if (mounted) {
          report = await showDialog<CleanReport>(
            context: this.context,
            barrierDismissible: false,
            builder: (_) => Theme(
              data: _cosmicTheme ?? Theme.of(this.context),
              child: CleanProgressDialog(categories: categories),
            ),
          );
        }
      } finally {
        final restored = closed ? await occupied!.restore() : true;
        if (!closed) await occupied?.dispose();
        if (mounted) {
          setState(() => _occupiedOperation = false);
          if (!restored) {
            ScaffoldMessenger.of(this.context).showSnackBar(
              const SnackBar(content: Text('清理已完成，但部分软件未能自动重新打开')),
            );
          }
        }
      }
      if (mounted && state.lastCleanAt != before) {
        setState(() {
          if (_focusedCategory != null &&
              (state.results[_focusedCategory]?.items.isEmpty ?? true)) {
            _focusedCategory = null;
          }
          if (report?.cancelled != true) _celebrationAt = state.lastCleanAt;
        });
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
        ? CosmicColors.warning
        : category.items.isEmpty
        ? AppColors.success
        : !category.category.defaultSelected
        ? CosmicColors.warning
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
                onExpansionChanged: (value) {
                  if (_expanded != value) {
                    setState(() => _expanded = value);
                  }
                },
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
                        '${category.items.length} 项 · ${category.items.fold<int>(0, (n, i) => n + i.fileCount + i.blockedFileCount)} 个文件 · ${category.category.subtitle}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: CosmicColors.muted,
                        ),
                      ),
                      const SizedBox(height: 5),
                      if (category.error != null ||
                          category.items.isEmpty ||
                          !category.category.defaultSelected)
                        Row(
                          children: [
                            Icon(
                              category.error != null
                                  ? Icons.info_outline_rounded
                                  : category.items.isEmpty
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.circle,
                              size:
                                  category.items.isEmpty ||
                                      category.error != null
                                  ? 12
                                  : 6,
                              color: color,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                category.error != null
                                    ? category.diagnosticLabel
                                    : category.items.isEmpty
                                    ? '已检查，未发现可清理内容'
                                    : '需手动确认',
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: IconButton(
                              tooltip: '复制扫描诊断',
                              onPressed: () => Clipboard.setData(
                                ClipboardData(text: category.error!),
                              ),
                              icon: const Icon(
                                Icons.copy_all_outlined,
                                color: CosmicColors.cyan,
                                size: 18,
                              ),
                            ),
                          ),
                          SelectableText(
                            category.error!,
                            key: PageStorageKey(
                              'scan-diagnostics-${category.category.name}',
                            ),
                            style: const TextStyle(
                              color: CosmicColors.warning,
                              fontSize: 12,
                            ),
                          ),
                        ],
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
                        enabled: !busy && item.hasCleanableFiles,
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
        if (item.category != CleanCategory.registryJunk)
          const PopupMenuItem(
            value: 'reveal',
            child: _MenuRow(icon: Icons.folder_open_rounded, label: '打开所在位置'),
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
        try {
          await state.revealInExplorer(item.path);
        } on Exception {
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('无法打开所在位置，请检查路径和权限')));
          }
        }
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
                    if (item.blockedFileCount > 0)
                      Text(
                        '可清理 ${formatBytes(item.sizeBytes)} · 暂不可清理 ${formatBytes(item.blockedSizeBytes)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: CosmicColors.warning,
                        ),
                      ),
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
                  item.fileCount + item.blockedFileCount > 0
                      ? '${item.fileCount + item.blockedFileCount} 文件'
                      : '—',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 72, child: SizeText(item.detectedSizeBytes)),
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

/// Group totals describe discovered content; the bottom bar remains selected bytes.
class _CleanupSectionHeader extends StatelessWidget {
  const _CleanupSectionHeader({
    required this.section,
    required this.categories,
  });
  final CleanupSection section;
  final List<ScanCategory> categories;

  @override
  Widget build(BuildContext context) {
    final bytes = categories.fold<int>(
      0,
      (sum, entry) =>
          sum + entry.items.fold<int>(0, (size, item) => size + item.sizeBytes),
    );
    final icon = switch (section) {
      CleanupSection.caches => Icons.layers_outlined,
      CleanupSection.diagnostics => Icons.receipt_long_outlined,
      CleanupSection.personal => Icons.folder_open_rounded,
      CleanupSection.maintenance => Icons.build_outlined,
    };
    return Padding(
      key: ValueKey('cleanup-section-${section.name}'),
      padding: const EdgeInsets.only(top: 12, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: CosmicColors.cyan),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  section.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                formatBytes(bytes),
                style: const TextStyle(color: CosmicColors.muted, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
