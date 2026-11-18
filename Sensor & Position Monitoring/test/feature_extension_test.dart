import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/core/mova_core.dart';
import 'package:mova/ui/posture_demo_page.dart';

/// SensorSample buatan untuk mempermudah penulisan test.
SensorSample createSample({
  required double tiltDeg,
  required DateTime timestamp,
  double rotationDeg = 0,
  double angularSpeed = 0,
  double jitter = 0,
  ScreenOrientation orientation = ScreenOrientation.portrait,
  ScreenOrientation stableOrientation = ScreenOrientation.portrait,
}) {
  return SensorSample(
    timestamp: timestamp,
    rawAcceleration: const Vector3(0, 9.81, 0),
    gravity: const Vector3(0, 9.81, 0),
    gyroscope: Vector3(angularSpeed, 0, 0),
    screenTiltDeg: tiltDeg,
    rotationDeg: rotationDeg,
    orientation: orientation,
    stableOrientation: stableOrientation,
  );
}

void main() {
  group('Feature 1 — Automatic Recalibration on Landscape', () {
    test('transisi portrait ke landscape memicu fase settling', () {
      final controller = AutoRecalibrationController(
        config: const PostureConfig(
          orientationSettlingDuration: Duration(seconds: 1),
        ),
      );

      final t0 = DateTime(2026, 1, 1, 12, 0, 0);

      // Mulai di portrait
      controller.onSample(createSample(
        tiltDeg: 70,
        timestamp: t0,
        orientation: ScreenOrientation.portrait,
        stableOrientation: ScreenOrientation.portrait,
      ));
      expect(controller.state.phase, AutoRecalibrationPhase.idle);

      // Transisi ke landscape
      controller.onSample(createSample(
        tiltDeg: 70,
        timestamp: t0.add(const Duration(milliseconds: 100)),
        orientation: ScreenOrientation.landscapeLeft,
        stableOrientation: ScreenOrientation.landscapeLeft,
      ));

      expect(controller.state.phase, AutoRecalibrationPhase.settling);
      controller.dispose();
    });

    test('fluktuasi orientasi sesaat (< 1 detik) membatalkan rekalibrasi', () {
      final controller = AutoRecalibrationController(
        config: const PostureConfig(
          orientationSettlingDuration: Duration(seconds: 1),
        ),
      );

      final t0 = DateTime(2026, 1, 1, 12, 0, 0);

      controller.onSample(createSample(
        tiltDeg: 70,
        timestamp: t0,
        stableOrientation: ScreenOrientation.portrait,
      ));

      // Transisi ke landscape
      controller.onSample(createSample(
        tiltDeg: 70,
        timestamp: t0.add(const Duration(milliseconds: 100)),
        stableOrientation: ScreenOrientation.landscapeLeft,
      ));
      expect(controller.state.phase, AutoRecalibrationPhase.settling);

      // Cepat kembali ke portrait (fluktuasi tangan)
      controller.onSample(createSample(
        tiltDeg: 70,
        timestamp: t0.add(const Duration(milliseconds: 300)),
        stableOrientation: ScreenOrientation.portrait,
      ));

      expect(controller.state.phase, AutoRecalibrationPhase.idle);
      controller.dispose();
    });

    test('rekalibrasi otomatis berhasil mengumpulkan sampel dan menghasilkan baseline',
        () {
      PostureBaseline? calibrated;
      final controller = AutoRecalibrationController(
        config: const PostureConfig(
          orientationSettlingDuration: Duration(seconds: 1),
          calibrationDuration: Duration(seconds: 2),
          calibrationMinSamples: 5,
        ),
        onBaselineCalibrated: (b) => calibrated = b,
      );

      final t0 = DateTime(2026, 1, 1, 12, 0, 0);

      // Masuk portrait
      controller.onSample(createSample(
        tiltDeg: 70,
        timestamp: t0,
        stableOrientation: ScreenOrientation.portrait,
      ));

      // Putar ke landscape
      controller.onSample(createSample(
        tiltDeg: 75,
        timestamp: t0.add(const Duration(milliseconds: 100)),
        stableOrientation: ScreenOrientation.landscapeLeft,
      ));

      // Setelah 1 detik settling -> masuk waitingForStillness
      controller.onSample(createSample(
        tiltDeg: 75,
        timestamp: t0.add(const Duration(milliseconds: 1200)),
        stableOrientation: ScreenOrientation.landscapeLeft,
      ));
      expect(controller.state.phase, AutoRecalibrationPhase.waitingForStillness);

      // Kirim sampel stasioner selama durasi kalibrasi (2 detik)
      for (var i = 0; i < 10; i++) {
        controller.onSample(createSample(
          tiltDeg: 75.0 + (i % 2) * 0.2,
          timestamp: t0.add(Duration(milliseconds: 1300 + (i * 250))),
          stableOrientation: ScreenOrientation.landscapeLeft,
          angularSpeed: 0.05,
          jitter: 0.1,
        ));
      }

      // Validasi hasil
      expect(controller.state.phase, AutoRecalibrationPhase.success);
      expect(calibrated, isNotNull);
      expect(calibrated!.orientation, ScreenOrientation.landscapeLeft);
      expect(calibrated!.tiltDeg, closeTo(75.0, 1.0));
      controller.dispose();
    });

    test('kegagalan rekalibrasi landscape tidak menghapus baseline yang sudah valid',
        () {
      final store = OrientationBaselineStore(
        portrait: PostureBaseline(
          tiltDeg: 65,
          rotationDeg: 0,
          orientation: ScreenOrientation.portrait,
          capturedAt: DateTime(2026, 1, 1),
          sampleCount: 50,
          tiltSpreadDeg: 1.5,
        ),
        landscape: PostureBaseline(
          tiltDeg: 72,
          rotationDeg: 90,
          orientation: ScreenOrientation.landscapeLeft,
          capturedAt: DateTime(2026, 1, 1),
          sampleCount: 50,
          tiltSpreadDeg: 1.5,
        ),
      );

      final controller = AutoRecalibrationController(
        config: const PostureConfig(
          orientationSettlingDuration: Duration(seconds: 1),
          calibrationDuration: Duration(seconds: 2),
        ),
        onBaselineCalibrated: (b) => store.set(b),
      );

      final t0 = DateTime(2026, 1, 1, 12, 0, 0);

      controller.onSample(createSample(
        tiltDeg: 70,
        timestamp: t0,
        stableOrientation: ScreenOrientation.portrait,
      ));

      // Putar ke landscape
      controller.onSample(createSample(
        tiltDeg: 75,
        timestamp: t0.add(const Duration(milliseconds: 100)),
        stableOrientation: ScreenOrientation.landscapeLeft,
      ));

      // Settling selesai
      controller.onSample(createSample(
        tiltDeg: 75,
        timestamp: t0.add(const Duration(milliseconds: 1200)),
        stableOrientation: ScreenOrientation.landscapeLeft,
      ));

      // HP digerakkan secara berlebih (melewati timeout/gagal)
      controller.onSample(createSample(
        tiltDeg: 75,
        timestamp: t0.add(const Duration(seconds: 20)),
        stableOrientation: ScreenOrientation.landscapeLeft,
        angularSpeed: 2.0, // Terlalu cepat
      ));

      expect(controller.state.phase, AutoRecalibrationPhase.failed);
      // Baseline landscape lama tetap aman tersimpan!
      expect(store.landscape, isNotNull);
      expect(store.landscape!.tiltDeg, 72);
      controller.dispose();
    });
  });

  group('Feature 2 — Orientation-Specific Baseline', () {
    test('store menyimpan baseline portrait dan landscape secara terpisah', () {
      final store = OrientationBaselineStore();

      final portrait = PostureBaseline(
        tiltDeg: 60,
        rotationDeg: 0,
        orientation: ScreenOrientation.portrait,
        capturedAt: DateTime(2026, 1, 1),
        sampleCount: 40,
        tiltSpreadDeg: 2.0,
      );

      final landscape = PostureBaseline(
        tiltDeg: 75,
        rotationDeg: 90,
        orientation: ScreenOrientation.landscapeLeft,
        capturedAt: DateTime(2026, 1, 1),
        sampleCount: 40,
        tiltSpreadDeg: 2.0,
      );

      store.set(portrait);
      store.set(landscape);

      expect(store.get(ScreenOrientation.portrait)?.tiltDeg, 60);
      expect(store.get(ScreenOrientation.landscapeLeft)?.tiltDeg, 75);
      expect(store.get(ScreenOrientation.landscapeRight)?.tiltDeg, 75);
    });

    test('fallback ke baseline portrait jika landscape belum terkalibrasi', () {
      final store = OrientationBaselineStore();

      final portrait = PostureBaseline(
        tiltDeg: 62,
        rotationDeg: 0,
        orientation: ScreenOrientation.portrait,
        capturedAt: DateTime(2026, 1, 1),
        sampleCount: 40,
        tiltSpreadDeg: 2.0,
      );

      store.set(portrait);

      // Meminta landscape mengembalikan portrait sebagai fallback
      expect(store.get(ScreenOrientation.landscapeLeft)?.tiltDeg, 62);
      expect(store.hasFor(ScreenOrientation.portrait), isTrue);
      expect(store.hasFor(ScreenOrientation.landscapeLeft), isFalse);
    });

    test('serialisasi JSON mendukung format ganda dan kompatibel dengan format lama',
        () {
      final store = OrientationBaselineStore(
        portrait: PostureBaseline(
          tiltDeg: 61,
          rotationDeg: 0,
          orientation: ScreenOrientation.portrait,
          capturedAt: DateTime(2026, 1, 1),
          sampleCount: 30,
          tiltSpreadDeg: 1.0,
        ),
        landscape: PostureBaseline(
          tiltDeg: 74,
          rotationDeg: 90,
          orientation: ScreenOrientation.landscapeLeft,
          capturedAt: DateTime(2026, 1, 1),
          sampleCount: 30,
          tiltSpreadDeg: 1.0,
        ),
      );

      final json = store.toJson();
      final restored = OrientationBaselineStore.fromJson(json);

      expect(restored.portrait?.tiltDeg, 61);
      expect(restored.landscape?.tiltDeg, 74);

      // Cek kompatibilitas format lama (single PostureBaseline JSON)
      final legacyJson = store.portrait!.toJson();
      final fromLegacy = OrientationBaselineStore.fromJson(legacyJson);
      expect(fromLegacy.portrait?.tiltDeg, 61);
    });
  });

  group('Feature 3 — Gentle Haptic Feedback', () {
    test('haptic service memicu callback getaran ringan saat koreksi diperlukan',
        () async {
      var vibrateCount = 0;
      final service = HapticFeedbackService(
        onVibrate: () => vibrateCount++,
      );

      await service.triggerCorrectionHaptic();
      expect(vibrateCount, 1);
      expect(service.triggerCount, 1);

      // Tidak bergetar saat dinonaktifkan
      service.enabled = false;
      await service.triggerCorrectionHaptic();
      expect(vibrateCount, 1);
    });

    test('analyzer hanya menghasilkan correctionTriggered saat cooldown terpenuhi',
        () {
      final analyzer = PostureAnalyzer(
        config: const PostureConfig(
          correctionDwell: Duration(seconds: 5),
          correctionCooldown: Duration(seconds: 20),
        ),
      );

      final baseline = PostureBaseline(
        tiltDeg: 70,
        rotationDeg: 0,
        orientation: ScreenOrientation.portrait,
        capturedAt: DateTime(2026, 1, 1),
        sampleCount: 30,
        tiltSpreadDeg: 1.0,
      );

      final t0 = DateTime(2026, 1, 1, 10, 0, 0);

      // Posisi buruk (tilt 40 vs baseline 70)
      PostureEvaluation? lastEval;
      var triggerCount = 0;

      for (var i = 0; i <= 20; i++) {
        lastEval = analyzer.evaluate(
          sample: createSample(
            tiltDeg: 40,
            timestamp: t0.add(Duration(seconds: i)),
          ),
          baseline: baseline,
        );
        if (lastEval.correctionTriggered) triggerCount++;
      }

      // Tepat pada detik ke-5 dwell terlewati dan terpicu 1 kali
      expect(triggerCount, 1);
      expect(lastEval?.status, PostureStatus.needsCorrection);
    });
  });

  group('Feature 4 — Break Reminder Integration', () {
    test('break reminder terpicu saat waktu penggunaan mencapai batas', () {
      final analyzer = PostureAnalyzer(
        config: const PostureConfig(
          breakReminderAfter: Duration(seconds: 3),
        ),
      );

      final baseline = PostureBaseline(
        tiltDeg: 70,
        rotationDeg: 0,
        orientation: ScreenOrientation.portrait,
        capturedAt: DateTime(2026, 1, 1),
        sampleCount: 30,
        tiltSpreadDeg: 1.0,
      );

      final t0 = DateTime(2026, 1, 1, 10, 0, 0);

      // Jalankan sampel dengan interval 500ms (di bawah maxSampleGap 1 detik)
      final evaluations = <PostureEvaluation>[];
      for (var i = 0; i <= 10; i++) {
        evaluations.add(analyzer.evaluate(
          sample: createSample(
            tiltDeg: 70,
            timestamp: t0.add(Duration(milliseconds: 500 * i)),
          ),
          baseline: baseline,
        ));
      }

      // Pada 3 detik (langkah ke-6), breakReminderDue menjadi true tepat satu kali
      final triggeredList = evaluations.where((e) => e.breakReminderDue).toList();
      expect(triggeredList.length, 1);
      expect(evaluations.last.stats.usageDuration, greaterThanOrEqualTo(const Duration(seconds: 3)));
    });

    testWidgets('UI demo page menampilkan komponen demo dan dialog istirahat',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: PostureDemoPage()));
      await tester.pump();

      expect(find.text('Belum dikalibrasi'), findsOneWidget);
      expect(find.text('Pembacaan Sensor'), findsOneWidget);
      expect(find.text('Kalibrasi Personal'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
