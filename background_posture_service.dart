import 'dart:async';
import 'package:flutter/services.dart';

/// Pengelola Background Posture Monitoring yang berkomunikasi dengan
/// Android Foreground Service melalui MethodChannel.
class BackgroundPostureService {
  BackgroundPostureService({
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel('com.kelompok6.mova/background_service');

  final MethodChannel _channel;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  DateTime? _lastNotificationAt;
  Duration notificationCooldown = const Duration(seconds: 60);

  /// Menyalakan Foreground Service di Android untuk terus memantau postur
  /// saat aplikasi berpindah ke latar belakang.
  Future<bool> startService({
    required double baselineTiltDeg,
    double downwardToleranceDeg = 15.0,
    int dwellSeconds = 20,
    int cooldownSeconds = 60,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('startForegroundService', {
        'baselineTiltDeg': baselineTiltDeg,
        'downwardToleranceDeg': downwardToleranceDeg,
        'dwellSeconds': dwellSeconds,
        'cooldownSeconds': cooldownSeconds,
      });
      _isRunning = result ?? false;
      return _isRunning;
    } catch (_) {
      // Platform selain Android atau service gagal
      _isRunning = false;
      return false;
    }
  }

  /// Menghentikan Foreground Service dan membersihkan notifikasi aktif.
  Future<bool> stopService() async {
    try {
      final result = await _channel.invokeMethod<bool>('stopForegroundService');
      _isRunning = !(result ?? true);
      return !_isRunning;
    } catch (_) {
      _isRunning = false;
      return true;
    }
  }

  /// Mengecek apakah service sedang aktif di sistem Android.
  Future<bool> isServiceActive() async {
    try {
      final result = await _channel.invokeMethod<bool>('isServiceRunning');
      _isRunning = result ?? false;
      return _isRunning;
    } catch (_) {
      _isRunning = false;
      return false;
    }
  }

  /// Mengirimkan notifikasi sistem Android langsung dari aplikasi.
  Future<bool> showNotification({
    required String title,
    required String message,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('showNotification', {
        'title': title,
        'message': message,
      });
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Mengecek apakah notifikasi pengingat boleh ditembakkan (menghormati cooldown).
  bool shouldTriggerNotification(DateTime now) {
    if (_lastNotificationAt == null) return true;
    return now.difference(_lastNotificationAt!) >= notificationCooldown;
  }

  /// Menandai bahwa notifikasi telah dikirim untuk memulai cooldown.
  void markNotificationSent(DateTime now) {
    _lastNotificationAt = now;
  }

  void reset() {
    _isRunning = false;
    _lastNotificationAt = null;
  }
}
