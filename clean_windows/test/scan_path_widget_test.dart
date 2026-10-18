import 'package:clean_windows/models/clean_models.dart';
import 'package:clean_windows/pages/clean_page.dart';
import 'package:clean_windows/services/process_utils.dart';
import 'package:clean_windows/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _ScanningState extends AppState {
  var active = true;
  var path = r'D:\AppData\应用缓存\正在检查的文件.bin';
  @override
  bool get scanning => active;
  @override
  ScanProgress get progress => ScanProgress(
    currentCategory: CleanCategory.appCache,
    totalCategories: 13,
    completedCategories: 3,
    message: '正在扫描软件缓存…',
    currentPath: path,
  );
  void updatePath(String value) {
    path = value;
    notifyListeners();
  }

  void finish() {
    active = false;
    notifyListeners();
  }
}

void main() {
  testWidgets(
    'clean page updates current path, clips long paths and hides it when finished',
    (tester) async {
      AppState.debugSkipProcess = true;
      ProcessUtils.debugSkip = true;
      final state = _ScanningState();
      addTearDown(() {
        state.dispose();
        AppState.debugSkipProcess = false;
        ProcessUtils.debugSkip = false;
      });
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: const MaterialApp(home: Scaffold(body: CleanPage())),
        ),
      );
      const key = ValueKey('scan-current-path');
      expect(tester.widget<Text>(find.byKey(key)).data, state.path);
      final longPath = 'D:\\${List.filled(20, '较长目录').join('\\')}\\缓存.bin';
      state.updatePath(longPath);
      await tester.pump();
      final label = tester.widget<Text>(find.byKey(key));
      expect(label.data, longPath);
      expect(label.maxLines, 1);
      expect(label.overflow, TextOverflow.ellipsis);
      expect(find.byTooltip(longPath), findsOneWidget);
      expect(tester.takeException(), isNull);
      state.finish();
      await tester.pump();
      expect(find.byKey(key), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
