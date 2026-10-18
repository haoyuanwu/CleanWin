import 'package:flutter/services.dart';

enum AdminScanResult { ready, alreadyElevated, cancelled, failed, timeout }

/// Only launches this application through Windows UAC; never changes ACLs.
class AdminScanService {
  const AdminScanService({
    this.channel = const MethodChannel('clean_windows/window'),
    this.pollInterval = const Duration(milliseconds: 200),
    this.maxPolls = 150,
  });

  final MethodChannel channel;
  final Duration pollInterval;
  final int maxPolls;

  Future<bool> isElevated() async {
    try {
      return await channel.invokeMethod<bool>('isElevated') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<AdminScanResult> request() async {
    try {
      final launch = await channel.invokeMethod<String>('restartForAdminScan');
      if (launch == 'cancelled') return AdminScanResult.cancelled;
      if (launch == 'alreadyElevated') return AdminScanResult.alreadyElevated;
      if (launch != 'launched') return AdminScanResult.failed;
      try {
        for (var attempt = 0; attempt < maxPolls; attempt++) {
          final status = await channel.invokeMethod<String>(
            'adminScanLaunchStatus',
          );
          if (status == 'ready') return AdminScanResult.ready;
          if (status != 'waiting') return AdminScanResult.failed;
          await Future<void>.delayed(pollInterval);
        }
        return AdminScanResult.timeout;
      } finally {
        await channel.invokeMethod<void>('releaseAdminScanLaunch');
      }
    } on PlatformException {
      return AdminScanResult.failed;
    } on MissingPluginException {
      return AdminScanResult.failed;
    }
  }
}
