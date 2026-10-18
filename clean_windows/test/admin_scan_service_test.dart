import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clean_windows/services/admin_scan_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/admin-scan');
  const service = AdminScanService(
    channel: channel,
    pollInterval: Duration.zero,
    maxPolls: 3,
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('cancelled UAC does not poll or close the original window', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return 'cancelled';
    });
    expect(await service.request(), AdminScanResult.cancelled);
    expect(calls, ['restartForAdminScan']);
  });

  test('waits for a ready window and releases launch tracking', () async {
    var polls = 0;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'restartForAdminScan') return 'launched';
      if (call.method == 'adminScanLaunchStatus') {
        return ++polls == 2 ? 'ready' : 'waiting';
      }
      return null;
    });
    expect(await service.request(), AdminScanResult.ready);
    expect(polls, 2);
    expect(calls.last, 'releaseAdminScanLaunch');
    expect(calls, isNot(contains('exitApp')));
  });

  for (final status in ['failed', 'waiting']) {
    test('handles $status without exiting the current app', () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return call.method == 'restartForAdminScan' ? 'launched' : status;
      });
      expect(
        await service.request(),
        status == 'failed' ? AdminScanResult.failed : AdminScanResult.timeout,
      );
      expect(calls.last, 'releaseAdminScanLaunch');
      expect(calls, isNot(contains('exitApp')));
    });
  }

  test('already elevated requires no second launch', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => 'alreadyElevated',
    );
    expect(await service.request(), AdminScanResult.alreadyElevated);
  });

  test('launch errors become a recoverable result', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'LAUNCH');
    });
    expect(await service.request(), AdminScanResult.failed);
    expect(await service.isElevated(), false);
  });
}
