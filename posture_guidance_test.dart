import 'package:flutter_test/flutter_test.dart';
import 'package:mova/core/mova_core.dart';

SensorSample createSample({
  required double tiltDeg,
  double rotationDeg = 0,
  ScreenOrientation orientation = ScreenOrientation.portrait,
}) {
  return SensorSample(
    timestamp: DateTime(2026, 1, 1, 10, 0, 0),
    rawAcceleration: const Vector3(0, 9.81, 0),
    gravity: const Vector3(0, 9.81, 0),
    gyroscope: Vector3.zero,
    screenTiltDeg: tiltDeg,
    rotationDeg: rotationDeg,
    orientation: orientation,
    stableOrientation: orientation,
  );
}

void main() {
  group('Real-time Posture Correction Guidance', () {
    final baseline = PostureBaseline(
      tiltDeg: 70.0,
      rotationDeg: 0.0,
      orientation: ScreenOrientation.portrait,
      capturedAt: DateTime(2026, 1, 1),
      sampleCount: 50,
      tiltSpreadDeg: 1.5,
    );

    const config = PostureConfig(
      downwardToleranceDeg: 15.0, // rentang 55..70 (mendatar)
      upwardToleranceDeg: 25.0,   // rentang 70..95 (tegak)
      rotationToleranceDeg: 20.0, // rentang -20..20
    );

    test('posisi di dalam rentang target menghasilkan status optimal', () {
      final sample = createSample(tiltDeg: 68.0, rotationDeg: 5.0);
      final guidance = PostureGuidance.calculate(
        sample: sample,
        baseline: baseline,
        config: config,
      );

      expect(guidance.isWithinComfort, isTrue);
      expect(guidance.primaryDirection, CorrectionDirection.optimal);
      expect(guidance.recoveryProgress, 1.0);
      expect(guidance.targetMinTiltDeg, 55.0);
      expect(guidance.targetMaxTiltDeg, 95.0);
    });

    test('posisi terlalu mendatar (tilt < 55) menghasilkan instruksi angkat HP', () {
      // tilt 45 vs baseline 70 -> selisih 25 derajat (melewati toleransi 15)
      final sample = createSample(tiltDeg: 45.0, rotationDeg: 0.0);
      final guidance = PostureGuidance.calculate(
        sample: sample,
        baseline: baseline,
        config: config,
      );

      expect(guidance.isWithinComfort, isFalse);
      expect(guidance.primaryDirection, CorrectionDirection.raisePhone);
      expect(guidance.instruction, contains('Angkat HP'));
      expect(guidance.tiltExcessDeg, closeTo(10.0, 0.1));
      expect(guidance.recoveryProgress, lessThan(1.0));
    });

    test('posisi terlalu tegak (tilt > 95) menghasilkan instruksi turunkan HP', () {
      // tilt 105 vs baseline 70 -> kelebihan 10 derajat di atas batas 95
      final sample = createSample(tiltDeg: 105.0, rotationDeg: 0.0);
      final guidance = PostureGuidance.calculate(
        sample: sample,
        baseline: baseline,
        config: config,
      );

      expect(guidance.isWithinComfort, isFalse);
      expect(guidance.primaryDirection, CorrectionDirection.lowerPhone);
      expect(guidance.instruction, contains('Turunkan HP'));
      expect(guidance.tiltExcessDeg, closeTo(10.0, 0.1));
    });

    test('posisi miring ke samping menghasilkan instruksi putar matematis yang benar', () {
      // Rotasi +35 derajat (miring ke kanan) vs toleransi 20 -> instruksi miringkan ke kiri
      final sampleRight = createSample(tiltDeg: 70.0, rotationDeg: 35.0);
      final guidanceRight = PostureGuidance.calculate(
        sample: sampleRight,
        baseline: baseline,
        config: config,
      );

      expect(guidanceRight.primaryDirection, CorrectionDirection.tiltLeft);
      expect(guidanceRight.instruction, contains('ke kiri'));

      // Rotasi -35 derajat (miring ke kiri) -> instruksi miringkan ke kanan
      final sampleLeft = createSample(tiltDeg: 70.0, rotationDeg: -35.0);
      final guidanceLeft = PostureGuidance.calculate(
        sample: sampleLeft,
        baseline: baseline,
        config: config,
      );

      expect(guidanceLeft.primaryDirection, CorrectionDirection.tiltRight);
      expect(guidanceLeft.instruction, contains('ke kanan'));
    });

    test('progres pemulihan meningkat mendekati 1.0 saat posisi mendekati target', () {
      // Jauh dari target (tilt 30)
      final far = PostureGuidance.calculate(
        sample: createSample(tiltDeg: 30.0),
        baseline: baseline,
        config: config,
      );

      // Lebih dekat ke target (tilt 50)
      final closer = PostureGuidance.calculate(
        sample: createSample(tiltDeg: 50.0),
        baseline: baseline,
        config: config,
      );

      // Tepat di dalam target (tilt 65)
      final inTarget = PostureGuidance.calculate(
        sample: createSample(tiltDeg: 65.0),
        baseline: baseline,
        config: config,
      );

      expect(far.recoveryProgress, lessThan(closer.recoveryProgress));
      expect(closer.recoveryProgress, lessThan(inTarget.recoveryProgress));
      expect(inTarget.recoveryProgress, 1.0);
    });
  });
}
