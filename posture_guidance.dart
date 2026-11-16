import 'dart:math' as math;

import '../sensors/sensor_sample.dart';
import '../posture/posture_baseline.dart';
import '../posture/posture_config.dart';
import '../posture/posture_state.dart';

/// Arah koreksi utama posisi ponsel.
enum CorrectionDirection {
  /// Posisi sudah berada di dalam target zona nyaman.
  optimal,

  /// Ponsel terlalu mendatar (layar menghadap langit, kepala menunduk).
  raisePhone,

  /// Ponsel terlalu tegak / mendongak ke belakang.
  lowerPhone,

  /// Ponsel miring ke kanan (perlu dimiringkan ke kiri agar tegak).
  tiltLeft,

  /// Ponsel miring ke kiri (perlu dimiringkan ke kanan agar tegak).
  tiltRight,
}

/// Rentang target sudut dan panduan koreksi real-time.
class PostureGuidance {
  const PostureGuidance({
    required this.targetMinTiltDeg,
    required this.targetMaxTiltDeg,
    required this.targetTiltDeg,
    required this.actualTiltDeg,
    required this.targetMinRotationDeg,
    required this.targetMaxRotationDeg,
    required this.targetRotationDeg,
    required this.actualRotationDeg,
    required this.tiltDeltaDeg,
    required this.rotationDeltaDeg,
    required this.tiltExcessDeg,
    required this.rotationExcessDeg,
    required this.primaryDirection,
    required this.instruction,
    required this.recoveryProgress,
    required this.isWithinComfort,
  });

  /// Batas bawah kemiringan yang masih nyaman (layar lebih mendatar dari baseline).
  final double targetMinTiltDeg;

  /// Batas atas kemiringan yang masih nyaman (layar lebih tegak dari baseline).
  final double targetMaxTiltDeg;

  /// Kemiringan acuan dari baseline.
  final double targetTiltDeg;

  /// Kemiringan aktual saat ini.
  final double actualTiltDeg;

  /// Batas minimum rotasi yang masih nyaman.
  final double targetMinRotationDeg;

  /// Batas maksimum rotasi yang masih nyaman.
  final double targetMaxRotationDeg;

  /// Sudut putar acuan dari baseline.
  final double targetRotationDeg;

  /// Sudut putar aktual saat ini.
  final double actualRotationDeg;

  /// Selisih kemiringan aktual terhadap baseline.
  /// Positif = aktual lebih mendatar (tiltDeg lebih kecil dari baseline).
  final double tiltDeltaDeg;

  /// Selisih sudut putar aktual terhadap baseline.
  final double rotationDeltaDeg;

  /// Kelebihan kemiringan di luar toleransi (0 bila nyaman).
  final double tiltExcessDeg;

  /// Kelebihan putaran di luar toleransi (0 bila nyaman).
  final double rotationExcessDeg;

  /// Arah koreksi dominan berdasarkan koordinat sensor.
  final CorrectionDirection primaryDirection;

  /// Kalimat instruksi koreksi yang presisi secara matematis.
  final String instruction;

  /// Progres pemulihan kembali ke rentang nyaman (0.0 = jauh, 1.0 = tercapai).
  final double recoveryProgress;

  /// True bila seluruh sumbu berada dalam rentang toleransi nyaman.
  final bool isWithinComfort;

  /// Menghitung panduan koreksi berdasarkan sampel sensor dan baseline personal.
  factory PostureGuidance.calculate({
    required SensorSample sample,
    required PostureBaseline baseline,
    PostureConfig config = const PostureConfig(),
    ActivityContext activity = ActivityContext.still,
  }) {
    final factor = switch (activity) {
      ActivityContext.walking => config.walkingToleranceFactor,
      ActivityContext.inVehicle => config.walkingToleranceFactor,
      _ => 1.0,
    };

    final downTol = config.downwardToleranceDeg * factor;
    final upTol = config.upwardToleranceDeg * factor;
    final rotTol = config.rotationToleranceDeg * factor;

    // Rentang target kemiringan:
    // tiltDeg = 0 (mendatar/langit) hingga 90 (tegak)
    // Menunduk: screenTiltDeg berkurang (downwardTol).
    // Menegakkan: screenTiltDeg bertambah (upwardTol).
    final targetMinTilt = math.max(0.0, baseline.tiltDeg - downTol);
    final targetMaxTilt = math.min(180.0, baseline.tiltDeg + upTol);

    // Rentang target rotasi:
    final targetMinRot = baseline.rotationDeg - rotTol;
    final targetMaxRot = baseline.rotationDeg + rotTol;

    // Hitung delta:
    // baseline.tiltDeg - sample.screenTiltDeg:
    // > 0 berarti ponsel lebih mendatar dari baseline (kepala menunduk)
    // < 0 berarti ponsel lebih tegak dari baseline
    final tiltDelta = baseline.tiltDeg - sample.screenTiltDeg;
    final rotDelta = AngleUtils.diffDeg(sample.rotationDeg, baseline.rotationDeg);

    final tiltExcess = tiltDelta >= 0
        ? math.max(0.0, tiltDelta - downTol)
        : math.max(0.0, -tiltDelta - upTol);

    final rotExcess = sample.orientation.isResolved
        ? math.max(0.0, rotDelta.abs() - rotTol)
        : 0.0;

    final isComfort = tiltExcess <= 0 && rotExcess <= 0;

    // Hitung progres pemulihan (0.0 .. 1.0)
    // Bila nyaman = 1.0. Bila menyimpang, berkurang sesuai rasio excess terhadap toleransi.
    double progress;
    if (isComfort) {
      progress = 1.0;
    } else {
      final maxExcessRatio = math.max(
        tiltExcess / (tiltDelta >= 0 ? downTol : upTol),
        rotExcess / rotTol,
      );
      progress = (1.0 - (maxExcessRatio * 0.5)).clamp(0.0, 0.95);
    }

    // Tentukan arah koreksi dominan
    CorrectionDirection direction = CorrectionDirection.optimal;
    String instruction = 'Posisi sudah nyaman dan optimal.';

    if (!isComfort) {
      if (tiltExcess >= rotExcess) {
        if (tiltDelta > 0) {
          direction = CorrectionDirection.raisePhone;
          final deg = tiltExcess.toStringAsFixed(0);
          instruction = 'Angkat HP sekitar $deg° agar kepala tidak menunduk.';
        } else {
          direction = CorrectionDirection.lowerPhone;
          final deg = tiltExcess.toStringAsFixed(0);
          instruction = 'Turunkan HP sekitar $deg° mendekati posisi awal.';
        }
      } else {
        if (rotDelta > 0) {
          direction = CorrectionDirection.tiltLeft;
          final deg = rotExcess.toStringAsFixed(0);
          instruction = 'Miringkan HP $deg° ke kiri agar layar tegak lurus.';
        } else {
          direction = CorrectionDirection.tiltRight;
          final deg = rotExcess.toStringAsFixed(0);
          instruction = 'Miringkan HP $deg° ke kanan agar layar tegak lurus.';
        }
      }
    }

    return PostureGuidance(
      targetMinTiltDeg: targetMinTilt,
      targetMaxTiltDeg: targetMaxTilt,
      targetTiltDeg: baseline.tiltDeg,
      actualTiltDeg: sample.screenTiltDeg,
      targetMinRotationDeg: targetMinRot,
      targetMaxRotationDeg: targetMaxRot,
      targetRotationDeg: baseline.rotationDeg,
      actualRotationDeg: sample.rotationDeg,
      tiltDeltaDeg: tiltDelta,
      rotationDeltaDeg: rotDelta,
      tiltExcessDeg: tiltExcess,
      rotationExcessDeg: rotExcess,
      primaryDirection: direction,
      instruction: instruction,
      recoveryProgress: progress,
      isWithinComfort: isComfort,
    );
  }
}
