import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/core/mova_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Background Monitoring & Notification Service', () {
    const channel = MethodChannel('com.kelompok6.mova/background_service');
    late BackgroundPostureService service;
    final log = <String>[];

    setUp(() {
      log.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        log.add(methodCall.method);
        switch (methodCall.method) {
          case 'startForegroundService':
            return true;
          case 'stopForegroundService':
            return true;
          case 'isServiceRunning':
            return true;
          case 'showNotification':
            return true;
          default:
            return null;
        }
      });

      service = BackgroundPostureService(channel: channel);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('startService memanggil method startForegroundService dan mengaktifkan status', () async {
      final success = await service.startService(
        baselineTiltDeg: 72.0,
        downwardToleranceDeg: 15.0,
      );

      expect(success, isTrue);
      expect(service.isRunning, isTrue);
      expect(log, contains('startForegroundService'));
    });

    test('stopService memanggil method stopForegroundService dan mematikan status', () async {
      await service.startService(baselineTiltDeg: 70.0);
      final stopped = await service.stopService();

      expect(stopped, isTrue);
      expect(service.isRunning, isFalse);
      expect(log, contains('stopForegroundService'));
    });

    test('cooldown notifikasi mencegah pengiriman berulang sebelum jeda selesai', () {
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);

      // Awal mula boleh kirim
      expect(service.shouldTriggerNotification(t0), isTrue);

      // Notifikasi dikirimkan pada t0
      service.markNotificationSent(t0);

      // Setelah 30 detik (di bawah cooldown 60 detik) -> tidak boleh kirim
      final t30s = t0.add(const Duration(seconds: 30));
      expect(service.shouldTriggerNotification(t30s), isFalse);

      // Setelah 60 detik (cooldown selesai) -> boleh kirim kembali
      final t60s = t0.add(const Duration(seconds: 60));
      expect(service.shouldTriggerNotification(t60s), isTrue);
    });
  });
}
