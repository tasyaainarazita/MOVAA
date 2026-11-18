import 'package:flutter_test/flutter_test.dart';
import 'package:mova/core/mova_core.dart';

/// Pembuat sampel sensor buatan, supaya logika posisi bisa diuji tanpa HP.
SensorSample sampleAt({
  required double tiltDeg,
  required DateTime timestamp,
  double rotationDeg = 0,
  double angularSpeed = 0,
  ScreenOrientation orientation = ScreenOrientation.portrait,
}) {
  return SensorSample(
    timestamp: timestamp,
    rawAcceleration: const Vector3(0, 9.81, 0),
    // Panjang vektor 9.81 agar dianggap pembacaan yang sah.
    gravity: const Vector3(0, 9.81, 0),
    gyroscope: Vector3(angularSpeed, 0, 0),
    screenTiltDeg: tiltDeg,
    rotationDeg: rotationDeg,
    orientation: orientation,
    stableOrientation: orientation,
  );
}

PostureBaseline baselineAt(double tiltDeg, {double rotationDeg = 0}) {
  return PostureBaseline(
    tiltDeg: tiltDeg,
    rotationDeg: rotationDeg,
    orientation: ScreenOrientation.portrait,
    capturedAt: DateTime(2026, 1, 1),
    sampleCount: 120,
    tiltSpreadDeg: 2.0,
  );
}

/// Jalankan analyzer selama [seconds] detik dengan posisi tetap.
List<PostureEvaluation> run(
  PostureAnalyzer analyzer, {
  required PostureBaseline baseline,
  required double tiltDeg,
  required int seconds,
  double angularSpeed = 0,
  ActivityContext activity = ActivityContext.still,
  DateTime? startAt,
}) {
  final start = startAt ?? DateTime(2026, 1, 1, 10);
  final results = <PostureEvaluation>[];
  // 500 ms per langkah, masih di bawah PostureConfig.maxSampleGap.
  for (var i = 0; i <= seconds * 2; i++) {
    results.add(analyzer.evaluate(
      sample: sampleAt(
        tiltDeg: tiltDeg,
        timestamp: start.add(Duration(milliseconds: 500 * i)),
        angularSpeed: angularSpeed,
      ),
      baseline: baseline,
      activity: activity,
    ));
  }
  return results;
}

void main() {
  group('Orientasi perangkat', () {
    final service = SensorService();

    test('HP tegak portrait -> tilt 90 derajat, orientasi portrait', () {
      final s = service.debugBuildSample(gravity: const Vector3(0, 9.81, 0));
      expect(s.screenTiltDeg, closeTo(90, 1));
      expect(s.orientation, ScreenOrientation.portrait);
    });

    test('HP mendatar menghadap atas -> tilt 0 dan orientasi flat', () {
      final s = service.debugBuildSample(gravity: const Vector3(0, 0, 9.81));
      expect(s.screenTiltDeg, closeTo(0, 1));
      expect(s.orientation, ScreenOrientation.flat);
    });

    test('HP menyamping -> landscape', () {
      final s = service.debugBuildSample(gravity: const Vector3(9.81, 0, 0));
      expect(s.orientation, ScreenOrientation.landscapeLeft);
      expect(s.screenTiltDeg, closeTo(90, 1));
    });

    test('orientasi bertahan saat HP sempat mendatar', () {
      service.debugBuildSample(gravity: const Vector3(0, 9.81, 0));
      final flat = service.debugBuildSample(gravity: const Vector3(0, 0, 9.81));
      expect(flat.orientation, ScreenOrientation.flat);
      // Orientasi terakhir yang valid tetap dilaporkan.
      expect(flat.stableOrientation, ScreenOrientation.portrait);
    });
  });

  group('Zona nyaman terhadap baseline', () {
    final baseline = baselineAt(70);

    test('posisi sama dengan baseline dianggap nyaman', () {
      final analyzer = PostureAnalyzer();
      final results =
          run(analyzer, baseline: baseline, tiltDeg: 70, seconds: 30);
      expect(results.last.status, PostureStatus.good);
      expect(results.last.deviation.isOutOfComfort, isFalse);
    });

    test('lebih tegak dari baseline masih ditoleransi (toleransi asimetris)',
        () {
      final analyzer = PostureAnalyzer();
      // 20 derajat lebih tegak, di bawah upwardToleranceDeg = 25.
      final results =
          run(analyzer, baseline: baseline, tiltDeg: 90, seconds: 30);
      expect(results.last.status, PostureStatus.good);
    });

    test('lebih mendatar 20 derajat sudah keluar zona nyaman', () {
      final analyzer = PostureAnalyzer();
      // downwardToleranceDeg = 15, jadi selisih 20 derajat sudah kelebihan.
      final first = analyzer.evaluate(
        sample: sampleAt(tiltDeg: 50, timestamp: DateTime(2026, 1, 1, 10)),
        baseline: baseline,
      );
      expect(first.deviation.isOutOfComfort, isTrue);
      expect(first.deviation.tiltExcessDeg, closeTo(5, 0.01));
    });
  });

  group('Ambang durasi sebelum koreksi', () {
    final baseline = baselineAt(70);

    test('gerakan sesaat tidak memicu koreksi', () {
      final analyzer = PostureAnalyzer();
      // Menunduk hanya 5 detik, jauh di bawah correctionDwell = 20 detik.
      final results =
          run(analyzer, baseline: baseline, tiltDeg: 40, seconds: 5);
      expect(results.last.status, PostureStatus.drifting);
      expect(results.any((e) => e.correctionTriggered), isFalse);
    });

    test('posisi buruk yang bertahan memicu koreksi tepat satu kali', () {
      final analyzer = PostureAnalyzer();
      final results =
          run(analyzer, baseline: baseline, tiltDeg: 40, seconds: 40);

      expect(results.last.status, PostureStatus.needsCorrection);
      expect(results.where((e) => e.correctionTriggered).length, 1);
      expect(analyzer.stats.correctionCount, 1);
    });

    test('penyimpangan parah memperpendek ambang durasi', () {
      final analyzer = PostureAnalyzer();
      // tilt 20 vs baseline 70 -> severity di atas severeSeverity.
      final results =
          run(analyzer, baseline: baseline, tiltDeg: 20, seconds: 1);
      expect(
        results.last.requiredDwell,
        const Duration(seconds: 10),
      );
    });

    test('timer dibekukan selama HP sedang digerakkan', () {
      final analyzer = PostureAnalyzer();
      final results = run(
        analyzer,
        baseline: baseline,
        tiltDeg: 40,
        seconds: 40,
        // Di atas transientAngularSpeed = 1.2 rad/s.
        angularSpeed: 2.5,
      );
      expect(results.last.isMotionTransient, isTrue);
      expect(results.last.outOfComfortFor, Duration.zero);
      expect(results.any((e) => e.correctionTriggered), isFalse);
    });

    test('kembali ke posisi nyaman membuat timer meluruh', () {
      final analyzer = PostureAnalyzer();
      final start = DateTime(2026, 1, 1, 10);
      run(analyzer,
          baseline: baseline, tiltDeg: 40, seconds: 10, startAt: start);
      final drifted = analyzer.outOfComfortFor;
      expect(drifted, greaterThan(Duration.zero));

      run(analyzer,
          baseline: baseline,
          tiltDeg: 70,
          seconds: 10,
          startAt: start.add(const Duration(seconds: 11)));
      expect(analyzer.outOfComfortFor, Duration.zero);
    });
  });

  group('Konteks aktivitas', () {
    final baseline = baselineAt(70);

    test('berjalan membuat toleransi lebih longgar', () {
      final still = PostureAnalyzer().computeDeviation(
        sample: sampleAt(tiltDeg: 48, timestamp: DateTime(2026, 1, 1, 10)),
        baseline: baseline,
      );
      final walking = PostureAnalyzer().computeDeviation(
        sample: sampleAt(tiltDeg: 48, timestamp: DateTime(2026, 1, 1, 10)),
        baseline: baseline,
        activity: ActivityContext.walking,
      );
      // Selisih 22 derajat: bermasalah saat diam, masih aman saat berjalan
      // (15 * 1.6 = 24 derajat).
      expect(still.isOutOfComfort, isTrue);
      expect(walking.isOutOfComfort, isFalse);
    });

    test('di kendaraan monitoring posisi dijeda', () {
      final analyzer = PostureAnalyzer();
      final results = run(
        analyzer,
        baseline: baseline,
        tiltDeg: 10,
        seconds: 60,
        activity: ActivityContext.inVehicle,
      );
      expect(results.last.status, PostureStatus.paused);
      expect(results.any((e) => e.correctionTriggered), isFalse);
      expect(analyzer.stats.pausedDuration, greaterThan(Duration.zero));
    });
  });

  group('Statistik sesi', () {
    test('position score mencerminkan proporsi posisi baik', () {
      final analyzer = PostureAnalyzer();
      final baseline = baselineAt(70);
      final start = DateTime(2026, 1, 1, 10);

      run(analyzer,
          baseline: baseline, tiltDeg: 70, seconds: 30, startAt: start);
      run(analyzer,
          baseline: baseline,
          tiltDeg: 40,
          seconds: 10,
          startAt: start.add(const Duration(seconds: 31)));

      final stats = analyzer.stats;
      expect(stats.activeDuration, greaterThan(Duration.zero));
      expect(stats.positionScore, greaterThan(60));
      expect(stats.positionScore, lessThan(100));
    });

    test('baseline bisa disimpan dan dimuat kembali', () {
      final original = baselineAt(63.5, rotationDeg: -4.2);
      final restored = PostureBaseline.fromJson(original.toJson());
      expect(restored.tiltDeg, original.tiltDeg);
      expect(restored.rotationDeg, original.rotationDeg);
      expect(restored.orientation, original.orientation);
    });
  });
}
