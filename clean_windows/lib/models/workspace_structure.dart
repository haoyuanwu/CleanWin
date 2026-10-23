import 'clean_models.dart';

/// Stable routes: navigation groups never change page identity or scan ownership.
const workspaceNavigation = [
  (title: '空间与文件', items: [0, 2]),
  (title: '系统与应用', items: [4, 5, 7]),
  (title: '保护与偏好', items: [9, 10]),
];

/// A deep link selects a workspace and its local tab, never a duplicate page.
int workspaceRoute(int route) => switch (route) {
  1 || 11 => 0,
  3 || 8 => 2,
  12 || 13 || 16 => 4,
  6 || 14 => 5,
  15 => 7,
  _ => route,
};

int workspaceTab(int route) => switch (route) {
  3 || 6 || 12 || 15 => 1,
  8 || 13 || 14 => 2,
  16 => 3,
  _ => 0,
};

/// Single owner for each scan family. Presentation groups are not scan scopes.
int cleanupOwner(CleanCategory category) => switch (category) {
  CleanCategory.downloads => 8,
  CleanCategory.appLeftovers => 14,
  CleanCategory.registryJunk => 7,
  CleanCategory.memoryDumps => -1,
  _ => 0,
};

const inspectionOwners = {
  'hardware': 12,
  'network': 13,
  'connectivity': 13,
  'preferences': 15,
  // Superseded aggregate inspections: use the existing specialist data sources.
  'storage': 2,
  'applications': 5,
};

/// Presentation only. Scanner IDs, snapshots and manual selections stay intact.
enum CleanupSection {
  caches('缓存与临时文件', [
    CleanCategory.systemCache,
    CleanCategory.browserCache,
    CleanCategory.appCache,
    CleanCategory.nvidiaCache,
    CleanCategory.windowsUpdate,
  ]),
  diagnostics('日志与痕迹', [
    CleanCategory.systemLogs,
    CleanCategory.usageTraces,
    CleanCategory.softwareUsage,
  ]),
  personal('个人文件', [CleanCategory.downloads, CleanCategory.recycleBin]),
  maintenance('应用与注册表', [
    CleanCategory.appLeftovers,
    CleanCategory.registryJunk,
  ]);

  const CleanupSection(this.title, this.categories);
  final String title;
  final List<CleanCategory> categories;

  static CleanupSection of(CleanCategory category) =>
      values.firstWhere((section) => section.categories.contains(category));
}
