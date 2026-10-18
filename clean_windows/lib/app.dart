import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';

import 'pages/clean_page.dart';
import 'pages/disk_pages.dart';
import 'pages/downloads_page.dart';
import 'pages/performance_page.dart';
import 'pages/settings_page.dart';
import 'pages/startup_registry_pages.dart';
import 'pages/uninstall_page.dart';
import 'pages/whitelist_page.dart';
import 'services/window_controls.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'theme/module_theme.dart';
import 'widgets/activity_center.dart';

class CleanWindowsApp extends StatelessWidget {
  const CleanWindowsApp({super.key, this.initialIndex = 0});
  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CleanWin',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const CleanScrollBehavior(),
      theme: AppTheme.light().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
        cardColor: Colors.transparent,
      ),
      home: AppShell(initialIndex: initialIndex),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.initialIndex = 0});
  final int initialIndex;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  // Keep legacy index 1 as an alias for the merged workspace.
  late int _index = widget.initialIndex == 1 ? 0 : widget.initialIndex;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = context.read<AppState>();
      if (!state.consumeStartupScanRequest()) return;
      setState(() => _index = 0);
      unawaited(_runStartupScan(state));
    });
  }

  Future<void> _runStartupScan(AppState state) async {
    try {
      await state.scan(force: true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('自动扫描未完成，请点击「重新扫描」重试')));
      }
    }
  }

  static const _titles = [
    '概览与清理',
    '', // Reserved legacy index; no second navigation entry.
    '磁盘分析',
    '大文件',
    '运行监控',
    '软件卸载',
    '启动项',
    '注册表',
    '下载管理',
    '白名单',
    '设置',
  ];
  static const _icons = [
    Icons.dashboard_rounded,
    Icons.cleaning_services_rounded,
    Icons.donut_small_rounded,
    Icons.file_copy_rounded,
    Icons.speed_rounded,
    Icons.delete_sweep_rounded,
    Icons.rocket_launch_rounded,
    Icons.health_and_safety_rounded,
    Icons.download_rounded,
    Icons.verified_user_outlined,
    Icons.settings_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [
      TickerMode(enabled: _index == 0, child: const CleanPage()),
      const SizedBox.shrink(),
      ModuleSurface(index: 2, child: DiskAnalysisPage(active: _index == 2)),
      const ModuleSurface(index: 3, child: LargeFilesPage()),
      ModuleSurface(index: 4, child: PerformancePage(active: _index == 4)),
      ModuleSurface(index: 5, child: UninstallPage(active: _index == 5)),
      ModuleSurface(index: 6, child: StartupPage(active: _index == 6)),
      const ModuleSurface(index: 7, child: RegistryCleanPage()),
      const ModuleSurface(index: 8, child: DownloadsPage()),
      const ModuleSurface(index: 9, child: WhitelistPage()),
      const ModuleSurface(index: 10, child: SettingsPage()),
    ];

    // 1) 透明底  2) 主页面圆角层  3) 侧边栏深色毛玻璃层
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const SizedBox.expand(),

          // ===== 主页面（独立背景 + 圆角）=====
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.only(
                // 主页面从侧栏中线开始，形成半叠放效果。
                left: 124,
                top: 12,
                bottom: 12,
                right: 12,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _index == 0
                          ? const [Color(0xFF070C20), Color(0xFF101632)]
                          : [
                              ModulePalette.forIndex(_index).background,
                              ModulePalette.forIndex(_index).end,
                            ],
                    ),
                  ),
                  child: Consumer<AppState>(
                    builder: (context, state, _) {
                      return _TopWindowDragRegion(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 顶部仅保留可拖动窗口的窄条，无标题栏
                            GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onPanStart: (_) => WindowControls.startDrag(),
                              onDoubleTap: () => WindowControls.maximize(),
                              child: const SizedBox(height: 12),
                            ),
                            Expanded(
                              // 保持页面状态：扫描不因切页中断
                              child: Padding(
                                // 内容避开叠放区域，维持原有可读宽度。
                                padding: const EdgeInsets.only(left: 120),
                                child: IndexedStack(
                                  index: _index,
                                  children: pages,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),

          // ===== 侧边栏：深色多彩渐变毛玻璃 =====
          Positioned(
            left: 14,
            top: 16,
            bottom: 16,
            width: 220,
            child: _SidebarShell(
              titles: _titles,
              icons: _icons,
              index: _index,
              onNavigate: (i) => setState(() => _index = i),
            ),
          ),
        ],
      ),
    );
  }
}

/// Adds hit handling without adding a title bar or changing page geometry.
class _TopWindowDragRegion extends StatelessWidget {
  const _TopWindowDragRegion({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Builder(
    builder: (regionContext) {
      return RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: {
          _TopWindowPanRecognizer:
              GestureRecognizerFactoryWithHandlers<_TopWindowPanRecognizer>(
                _TopWindowPanRecognizer.new,
                (recognizer) {
                  recognizer.acceptsPosition = (position) {
                    final box = regionContext.findRenderObject() as RenderBox?;
                    if (box == null || !box.attached) return false;
                    final local = box.globalToLocal(position);
                    // Align with the existing sidebar caption row (y = 16–62).
                    return local.dy >= 0 && local.dy <= 50;
                  };
                  recognizer.onStart = (_) => WindowControls.startDrag();
                },
              ),
        },
        child: child,
      );
    },
  );
}

class _TopWindowPanRecognizer extends PanGestureRecognizer {
  bool Function(Offset position)? acceptsPosition;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      (acceptsPosition?.call(event.position) ?? false) &&
      super.isPointerAllowed(event);
}

/// 深色多彩渐变毛玻璃侧边栏（不透明实色，不透桌面）
class _SidebarShell extends StatefulWidget {
  const _SidebarShell({
    required this.titles,
    required this.icons,
    required this.index,
    required this.onNavigate,
  });

  final List<String> titles;
  final List<IconData> icons;
  final int index;
  final ValueChanged<int> onNavigate;

  @override
  State<_SidebarShell> createState() => _SidebarShellState();
}

class _SidebarShellState extends State<_SidebarShell> {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    _syncMax();
  }

  Future<void> _syncMax() async {
    final m = await WindowControls.isMaximized();
    if (mounted) setState(() => _maximized = m);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (_) => WindowControls.startDrag(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 深色基底 + 多彩光斑（毛玻璃观感，整体不透明）
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0F172A),
                    Color(0xFF1E1B4B),
                    Color(0xFF0F2A4A),
                    Color(0xFF1A1030),
                  ],
                ),
              ),
            ),
            const _Glow(
              color: Color(0xFF6366F1),
              offset: Offset(-40, -30),
              size: 180,
            ),
            const _Glow(
              color: Color(0xFF22D3EE),
              offset: Offset(140, -20),
              size: 150,
            ),
            const _Glow(
              color: Color(0xFFA78BFA),
              offset: Offset(-30, 220),
              size: 160,
            ),
            const _Glow(
              color: Color(0xFF34D399),
              offset: Offset(120, 320),
              size: 140,
            ),
            const _Glow(
              color: Color(0xFFF472B6),
              offset: Offset(20, 480),
              size: 130,
            ),
            // 轻微雾面，毛玻璃质感
            ColoredBox(color: Colors.white.withValues(alpha: 0.06)),

            // 内容
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 46,
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        Image.asset(
                          'assets/icon/cleanwin_icon.png',
                          width: 28,
                          height: 28,
                          semanticLabel: 'CleanWin Logo',
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'CleanWin',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        _CaptionBtn(
                          tooltip: '最小化',
                          icon: Icons.remove_rounded,
                          onTap: () => WindowControls.minimize(),
                        ),
                        _CaptionBtn(
                          tooltip: _maximized ? '还原' : '最大化',
                          icon: _maximized
                              ? Icons.filter_none_rounded
                              : Icons.crop_square_rounded,
                          onTap: () async {
                            final m = await WindowControls.maximize();
                            if (mounted) setState(() => _maximized = m);
                          },
                        ),
                        _CaptionBtn(
                          tooltip: '关闭',
                          icon: Icons.close_rounded,
                          hoverColor: const Color(0xFFE81123),
                          hoverFg: Colors.white,
                          onTap: () => WindowControls.close(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: ListView(
                      key: const ValueKey('sidebar-navigation'),
                      padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                      children: [
                        for (final group in const [
                          (title: '工作台', items: [0]),
                          (title: '空间清理', items: [2, 3, 8]),
                          (title: '系统管理', items: [4, 5, 6, 7]),
                          (title: '偏好与保护', items: [9, 10]),
                        ]) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 16, 0, 8),
                            child: Text(
                              group.title,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF94A3B8),
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          for (final i in group.items)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: _SidebarItem(
                                key: ValueKey('nav-$i'),
                                icon: widget.icons[i],
                                label: widget.titles[i],
                                selected: widget.index == i,
                                onTap: () => widget.onNavigate(i),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.16),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.shield_outlined,
                          color: Color(0xFF6EE7B7),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            '安全清理 · 可预览',
                            style: TextStyle(
                              color: Color(0xFFCBD5E1),
                              fontSize: 11,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '任务与记录',
                          onPressed: () => showActivityCenter(context),
                          icon: const Icon(
                            Icons.history_rounded,
                            color: Color(0xFFCBD5E1),
                            size: 18,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.offset, required this.size});

  final Color color;
  final Offset offset;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: offset.dx,
      top: offset.dy,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: 0.45),
              color.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final bg = selected
        ? Colors.white.withValues(alpha: 0.18)
        : _hover
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.transparent;
    final fg = selected ? Colors.white : const Color(0xFFCBD5E1);

    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          onHover: (v) => setState(() => _hover = v),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: selected
                  ? Border.all(color: Colors.white.withValues(alpha: 0.22))
                  : null,
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: 18, color: fg),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CaptionBtn extends StatefulWidget {
  const _CaptionBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.hoverColor,
    this.hoverFg,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? hoverColor;
  final Color? hoverFg;

  @override
  State<_CaptionBtn> createState() => _CaptionBtnState();
}

class _CaptionBtnState extends State<_CaptionBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = _hover
        ? (widget.hoverColor ?? Colors.white.withValues(alpha: 0.16))
        : Colors.transparent;
    final fg = _hover
        ? (widget.hoverFg ?? Colors.white)
        : const Color(0xFF94A3B8);

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 30,
            height: 32,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(widget.icon, size: 13, color: fg),
          ),
        ),
      ),
    );
  }
}
