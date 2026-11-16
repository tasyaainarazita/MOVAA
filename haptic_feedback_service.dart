import 'package:flutter/services.dart';

/// Layanan umpan balik getaran ringan (gentle haptic feedback) saat koreksi
/// postur diperlukan.
///
/// Karakteristik:
/// - Hanya memicu getaran ringan (`HapticFeedback.lightImpact`).
/// - Tidak memutar suara notifikasi apa pun.
/// - Menghormati timer durasi koreksi dan periode cooldown melalui sinyal
///   [PostureEvaluation.correctionTriggered].
class HapticFeedbackService {
  HapticFeedbackService({
    this.enabled = true,
    void Function()? onVibrate,
  }) : _onVibrate = onVibrate;

  /// Status apakah feedback haptic diaktifkan.
  bool enabled;

  /// Callback getaran kustom (berguna untuk pengujian unit/mocking).
  final void Function()? _onVibrate;

  int _triggerCount = 0;

  /// Jumlah getaran yang berhasil dipicu (untuk kebutuhan telemetry & testing).
  int get triggerCount => _triggerCount;

  /// Memicu getaran ringan bila [enabled] bernilai true.
  ///
  /// Tidak menghasilkan efek suara dan aman dipanggil di platform apa pun.
  Future<void> triggerCorrectionHaptic() async {
    if (!enabled) return;

    try {
      if (_onVibrate != null) {
        _onVibrate();
      } else {
        await HapticFeedback.lightImpact();
      }
      _triggerCount++;
    } catch (_) {
      // Menangani platform yang tidak mendukung haptic feedback secara aman.
    }
  }

  /// Reset counter pemanggilan.
  void reset() {
    _triggerCount = 0;
  }
}
