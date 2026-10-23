import 'package:clean_windows/models/clean_models.dart';
import 'package:clean_windows/models/workspace_structure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'every scan category has exactly one home, personal data stays separate',
    () {
      final all = CleanupSection.values
          .expand((group) => group.categories)
          .toList();
      expect(
        all.toSet(),
        CleanCategory.values
            .where((category) => category != CleanCategory.memoryDumps)
            .toSet(),
      );
      expect(all.length, all.toSet().length);
      expect(
        CleanupSection.of(CleanCategory.downloads),
        CleanupSection.personal,
      );
      expect(
        CleanupSection.of(CleanCategory.recycleBin),
        CleanupSection.personal,
      );
      expect(
        CleanupSection.of(CleanCategory.nvidiaCache),
        CleanupSection.caches,
      );
      expect(cleanupOwner(CleanCategory.memoryDumps), -1);
      expect(
        CleanupSection.of(CleanCategory.registryJunk),
        CleanupSection.maintenance,
      );
    },
  );

  test(
    'navigation exposes each active module once and omits retired aliases',
    () {
      final routes = workspaceNavigation
          .expand((group) => group.items)
          .toList();
      expect(routes.toSet(), {0, 2, 4, 5, 7, 9, 10});
      expect(routes.length, routes.toSet().length);
      expect(workspaceRoute(8), 2);
      expect(workspaceTab(8), 2);
      expect(workspaceRoute(6), 5);
      expect(workspaceTab(6), 1);
      expect(workspaceRoute(13), 4);
      expect(workspaceTab(13), 2);
      expect(workspaceRoute(16), 4);
      expect(workspaceTab(16), 3);
    },
  );
}
