import 'package:flutter/services.dart';

/// 窗口控制（与原生 runner 的 clean_windows/window 通道通信）
class WindowControls {
  static const _channel = MethodChannel('clean_windows/window');

  static Future<void> minimize() async {
    try {
      await _channel.invokeMethod('minimize');
    } on PlatformException catch (_) {}
  }

  static Future<bool> maximize() async {
    try {
      final r = await _channel.invokeMethod<bool>('maximize');
      return r ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  static Future<void> restore() async {
    try {
      await _channel.invokeMethod('restore');
    } on PlatformException catch (_) {}
  }

  static Future<void> close() async {
    try {
      await _channel.invokeMethod('close'); // 实际：最小化到托盘
    } on PlatformException catch (_) {}
  }

  static Future<void> hideToTray() async {
    try {
      await _channel.invokeMethod('hideToTray');
    } on PlatformException catch (_) {}
  }

  static Future<void> showWindow() async {
    try {
      await _channel.invokeMethod('showWindow');
    } on PlatformException catch (_) {}
  }

  /// 真正退出进程（托盘菜单「退出」）
  static Future<void> exitApp() async {
    try {
      await _channel.invokeMethod('exitApp');
    } on PlatformException catch (_) {}
  }

  /// 拖动窗口（标题栏手势）
  static Future<void> startDrag() async {
    try {
      await _channel.invokeMethod('startDrag');
    } on PlatformException catch (_) {}
  }

  static Future<bool> isMaximized() async {
    try {
      return await _channel.invokeMethod<bool>('isMaximized') ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }
}
