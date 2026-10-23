import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';

import 'models/workspace_structure.dart';
import 'pages/clean_page.dart';
import 'pages/app_leftovers_page.dart';
import 'pages/health_check_page.dart';
import 'widgets/workspace_tabs.dart';
import 'pages/disk_pages.dart';
import 'pages/downloads_page.dart';
import 'pages/performance_page.dart';
import 'pages/hardware_dashboard_page.dart';
import 'pages/windows_settings_page.dart';
import 'pages/settings_page.dart';
import 'pages/startup_registry_pages.dart';
import 'pages/uninstall_page.dart';
import 'pages/whitelist_page.dart';
import 'services/window_controls.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'theme/module_theme.dart';

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
  late int _index = workspaceRoute(widget.initialIndex);
  late int _fileTab = _index == 2 ? workspaceTab(widget.initialIndex) : 0;
  late int _systemTab = _index == 4 ? workspaceTab(widget.initialIndex) : 0;
  late int _appTab = _index == 5 ? workspaceTab(widget.initialIndex) : 0;
  late int _maintenanceTab = _index == 7
      ? workspaceTab(widget.initialIndex)
      : 0;

  void _navigate(int route) => setState(() {
    _index = workspaceRoute(route);
    // Clicking the workspace itself preserves its current tab.
    if (route != _index) {
      switch (_index) {
        case 2:
          _fileTab = workspaceTab(route);
        case 4:
          _systemTab = workspaceTab(route);
        case 5:
          _appTab = workspaceTab(route);
        case 7:
          _maintenanceTab = workspaceTab(route);
      }
    }
  });

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = context.read<AppState>();
      // Local inspection is silent and does not depend on cleanup preferences.
      unawaited(_readStartupSystemInfo(state));
      if (!state.consumeStartupScanRequest()) return;
      setState(() => _index = 0);
      unawaited(_runStartupScan(state));
    });
  }

  Future<void> _readStartupSystemInfo(AppState state) async {
    try {
      await state.healthChecks.readOnStartup();
    } catch (_) {
      // Keep startup quiet. The feature pages retain partial results and refresh.
    }
  }

  Future<void> _runStartupScan(AppState state) async {
    try {
      await state.scanOverview();
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
    '文件管理',
    '大文件',
    '系统监控',
    '应用管理',
    '启动项',
    '系统维护',
    '下载管理',
    '白名单',
    '设置',
    '全面体检',
  ];
  static const _icons = [
    Icons.dashboard_rounded,
    Icons.cleaning_services_rounded,
    Icons.folder_open_rounded,
    Icons.file_copy_rounded,
    Icons.monitor_heart_outlined,
    Icons.apps_rounded,
    Icons.rocket_launch_rounded,
    Icons.build_outlined,
    Icons.download_rounded,
    Icons.verified_user_outlined,
    Icons.settings_rounded,
    Icons.fact_check_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    HealthCheckPage inspection(String id, String title) => HealthCheckPage(
      key: ValueKey('system-inspection-$id'),
      controller: state.healthChecks,
      sectionIds: {id},
      title: title,
      onNavigate: _navigate,
      onScanTraces: () async => false,
    );
    final pages = [
      TickerMode(
        enabled: _index == 0,
        child: CleanPage(onNavigate: _navigate),
      ),
      const SizedBox.shrink(),
      ModuleSurface(
        index: 2,
        child: WorkspaceTabs(
          active: _index == 2,
          index: _fileTab,
          onChanged: (i) => setState(() => _fileTab = i),
          tabs: const [
            (label: '磁盘分析', icon: Icons.donut_small_rounded),
            (label: '大文件', icon: Icons.file_copy_outlined),
            (label: '下载审查', icon: Icons.download_outlined),
          ],
          builder: (i, active) => switch (i) {
            0 => DiskAnalysisPage(active: active),
            1 => const LargeFilesPage(),
            _ => const DownloadsPage(),
          },
        ),
      ),
      const SizedBox.shrink(),
      ModuleSurface(
        index: 4,
        child: WorkspaceTabs(
          active: _index == 4,
          index: _systemTab,
          onChanged: (i) => setState(() => _systemTab = i),
          tabs: const [
            (label: '运行监控', icon: Icons.speed_rounded),
            (label: '硬件信息', icon: Icons.memory_rounded),
            (label: '网络诊断', icon: Icons.hub_outlined),
            (label: '进程管理', icon: Icons.view_list_rounded),
          ],
          builder: (i, active) => switch (i) {
            0 => PerformancePage(active: active),
            1 => HardwareDashboardPage(controller: state.healthChecks),
            2 => inspection('network', '网络诊断'),
            _ => PerformancePage(active: active, processesOnly: true),
          },
        ),
      ),
      ModuleSurface(
        index: 5,
        child: WorkspaceTabs(
          active: _index == 5,
          index: _appTab,
          onChanged: (i) => setState(() => _appTab = i),
          tabs: const [
            (label: '软件卸载', icon: Icons.apps_outlined),
            (label: '启动项', icon: Icons.rocket_launch_outlined),
            (label: '应用残留', icon: Icons.folder_off_outlined),
          ],
          builder: (i, active) => switch (i) {
            0 => UninstallPage(active: active),
            1 => StartupPage(active: active),
            _ => const AppLeftoversPage(),
          },
        ),
      ),
      const SizedBox.shrink(),
      ModuleSurface(
        index: 7,
        child: WorkspaceTabs(
          active: _index == 7,
          index: _maintenanceTab,
          onChanged: (i) => setState(() => _maintenanceTab = i),
          tabs: const [
            (label: '注册表', icon: Icons.tune_rounded),
            (label: 'Windows 设置', icon: Icons.settings_suggest_outlined),
          ],
          builder: (i, active) =>
              i == 0 ? const RegistryCleanPage() : const WindowsSettingsPage(),
        ),
      ),
      const SizedBox.shrink(),
      const ModuleSurface(index: 9, child: WhitelistPage()),
      const ModuleSurface(index: 10, child: SettingsPage()),
      const SizedBox.shrink(),
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
                          ? const [Color(0xFF101F2B), Color(0xFF192E3B)]
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
              onNavigate: _navigate,
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
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.sidebar, Color(0xFF1B3540)],
                ),
              ),
            ),
            const Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _SidebarOrbitPainter()),
              ),
            ),
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
                        for (final group in workspaceNavigation) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 16, 0, 8),
                            child: Text(
                              group.title,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF94A3B8),
                                letterSpacing: .2,
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
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.09),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.shield_outlined,
                          color: AppColors.sidebarActive,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            '白名单保护',
                            style: TextStyle(
                              color: Color(0xFFCBD5E1),
                              fontSize: 11,
                            ),
                          ),
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

/// Quiet orbital arcs tie navigation to the overview without animated glows.
class _SidebarOrbitPainter extends CustomPainter {
  const _SidebarOrbitPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 1.18, size.height * .62);
    final paint = Paint()
      ..color = AppColors.sidebarActive.withValues(alpha: .07)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final radius in [130.0, 190.0, 250.0]) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        math.pi * .55,
        math.pi * 1.2,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SidebarOrbitPainter oldDelegate) => false;
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
        ? AppColors.sidebarActive.withValues(alpha: 0.12)
        : _hover
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.transparent;
    final fg = selected ? Colors.white : AppColors.sidebarText;

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
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? AppColors.sidebarActive.withValues(alpha: .22)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: 18,
                  color: selected ? AppColors.sidebarActive : fg,
                ),
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
                const SizedBox(width: 6),
                AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 140),
                  width: 4,
                  height: 16,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.sidebarActive
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
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
