import 'dart:math' as math;

import '../sensors/sensor_sample.dart';
import 'posture_baseline.dart';
import 'posture_config.dart';
import 'posture_state.dart';

/// Otak dari modul Position Logic.
///
/// Kelas ini murni logika — tidak menyentuh sensor, Stream, maupun Flutter —
/// sehingga bisa diuji sepenuhnya lewat unit test dengan data buatan.
///
/// Cara kerja tiap evaluasi:
///   1. Hitung selisih posisi sekarang terhadap baseline personal.
///   2. Lebarkan toleransi sesuai konteks aktivitas (diam / berjalan / kendaraan).
///   3. Kalau di luar zona nyaman, jalankan timer; kalau nyaman, timer meluruh.
///   4. Timer DIBEKUKAN saat HP sedang digerakkan, supaya gerakan sesaat
///      (ganti posisi duduk, ambil barang) tidak ikut terhitung.
///   5. Begitu timer melewati threshold, status jadi `needsCorrection` sekali,
///      lalu masuk masa cooldown agar tidak memberi peringatan bertubi-tubi.
class PostureAnalyzer {
  PostureAnalyzer({this.config = const PostureConfig()});

  final PostureConfig config;

  Duration _outOfComfortFor = Duration.zero;
  DateTime? _lastTimestamp;
  DateTime? _lastCorrectionAt;
  bool _wasOutOfComfort = false;
  bool _breakReminderSent = false;
  PostureSessionStats _stats = const PostureSessionStats();

  PostureSessionStats get stats => _stats;
  Duration get outOfComfortFor => _outOfComfortFor;

  /// Kosongkan seluruh timer dan statistik — panggil saat sesi baru dimulai
  /// atau setelah pengguna melakukan kalibrasi ulang.
  void reset() {
    _outOfComfortFor = Duration.zero;
    _lastTimestamp = null;
    _lastCorrectionAt = null;
    _wasOutOfComfort = false;
    _breakReminderSent = false;
    _stats = const PostureSessionStats();
  }

  /// Evaluasi satu sampel sensor terhadap baseline personal.
  PostureEvaluation evaluate({
    required SensorSample sample,
    required PostureBaseline baseline,
    ActivityContext activity = ActivityContext.still,
  }) {
    final now = sample.timestamp;
    final step = _stepSince(now);
    _lastTimestamp = now;

    // -- Kondisi yang membuat evaluasi posisi ditangguhkan ------------------
    final isPaused =
        config.pauseInVehicle && activity == ActivityContext.inVehicle;
    if (isPaused) {
      _stats = _stats.copyWith(pausedDuration: _stats.pausedDuration + step);
      _outOfComfortFor = Duration.zero;
      _wasOutOfComfort = false;
      return _build(
        sample: sample,
        status: PostureStatus.paused,
        deviation: PostureDeviation.none,
        activity: activity,
        requiredDwell: config.correctionDwell,
        correctionTriggered: false,
        isMotionTransient: false,
      );
    }

    if (!sample.isGravityReliable) {
      // Sudut tidak bisa dipercaya: bekukan timer, jangan hitung durasi.
      return _build(
        sample: sample,
        status: PostureStatus.unreliable,
        deviation: PostureDeviation.none,
        activity: activity,
        requiredDwell: config.correctionDwell,
        correctionTriggered: false,
        isMotionTransient: true,
      );
    }

    // -- Hitung penyimpangan terhadap baseline -----------------------------
    final deviation = computeDeviation(
      sample: sample,
      baseline: baseline,
      activity: activity,
      currentlyOutOfComfort: _wasOutOfComfort,
    );

    final isTransient = sample.angularSpeed > config.transientAngularSpeed;
    _stats = _stats.copyWith(activeDuration: _stats.activeDuration + step);

    if (deviation.isOutOfComfort) {
      _wasOutOfComfort = true;
      _stats = _stats.copyWith(badDuration: _stats.badDuration + step);
      // Saat HP sedang digerakkan, timer dibekukan (tidak nambah, tidak reset).
      if (!isTransient) _outOfComfortFor += step;
    } else {
      _wasOutOfComfort = false;
      _stats = _stats.copyWith(goodDuration: _stats.goodDuration + step);
      // Timer meluruh perlahan, bukan langsung nol, agar posisi yang
      // bolak-balik keluar-masuk zona nyaman tetap tercatat.
      final decay = step * config.recoveryDecayFactor;
      _outOfComfortFor =
          _outOfComfortFor > decay ? _outOfComfortFor - decay : Duration.zero;
    }

    // -- Tentukan apakah sudah waktunya memberi koreksi ---------------------
    final requiredDwell = _requiredDwellFor(deviation.severity);
    var status =
        deviation.isOutOfComfort ? PostureStatus.drifting : PostureStatus.good;
    var triggered = false;

    if (deviation.isOutOfComfort && _outOfComfortFor >= requiredDwell) {
      status = PostureStatus.needsCorrection;
      if (_isCooldownOver(now)) {
        triggered = true;
        _lastCorrectionAt = now;
        _stats = _stats.copyWith(correctionCount: _stats.correctionCount + 1);
      }
    }

    return _build(
      sample: sample,
      status: status,
      deviation: deviation,
      activity: activity,
      requiredDwell: requiredDwell,
      correctionTriggered: triggered,
      isMotionTransient: isTransient,
    );
  }

  /// Perbandingan posisi sekarang dengan baseline. Dipisah agar bisa dipakai
  /// langsung (mis. untuk preview live di layar kalibrasi) tanpa mengubah
  /// state timer.
  PostureDeviation computeDeviation({
    required SensorSample sample,
    required PostureBaseline baseline,
    ActivityContext activity = ActivityContext.still,
    bool currentlyOutOfComfort = false,
  }) {
    final factor = _toleranceFactor(activity);

    // Histeresis: begitu dinyatakan keluar zona, pengguna harus kembali lebih
    // dalam dari batas untuk dianggap nyaman lagi. Mencegah status berkedip.
    final hysteresis = currentlyOutOfComfort ? config.comfortHysteresisDeg : 0.0;

    final downTol =
        math.max(1.0, config.downwardToleranceDeg * factor - hysteresis);
    final upTol = math.max(1.0, config.upwardToleranceDeg * factor - hysteresis);
    final rotTol =
        math.max(1.0, config.rotationToleranceDeg * factor - hysteresis);

    // Positif = layar lebih mendatar dari baseline = kepala lebih menunduk.
    final tiltDelta = baseline.tiltDeg - sample.screenTiltDeg;
    final rotationDelta =
        AngleUtils.diffDeg(sample.rotationDeg, baseline.rotationDeg);

    // Toleransi sengaja asimetris: menunduk lebih cepat dianggap bermasalah
    // daripada menegakkan HP.
    final tiltExcess = tiltDelta >= 0
        ? math.max(0.0, tiltDelta - downTol)
        : math.max(0.0, -tiltDelta - upTol);

    // Perputaran hanya dinilai bila orientasi layar masih terbaca; saat HP
    // mendatar, sudut putar memang tidak bermakna.
    final rotationExcess = sample.orientation.isResolved
        ? math.max(0.0, rotationDelta.abs() - rotTol)
        : 0.0;

    final severity = math.max(
      tiltExcess / (tiltDelta >= 0 ? downTol : upTol),
      rotationExcess / rotTol,
    );

    return PostureDeviation(
      tiltDeltaDeg: tiltDelta,
      rotationDeltaDeg: rotationDelta,
      tiltExcessDeg: tiltExcess,
      rotationExcessDeg: rotationExcess,
      severity: severity,
    );
  }

  /// Pengali toleransi menurut konteks aktivitas.
  double _toleranceFactor(ActivityContext activity) => switch (activity) {
        ActivityContext.walking => config.walkingToleranceFactor,
        ActivityContext.inVehicle => config.walkingToleranceFactor,
        _ => 1.0,
      };

  /// Penyimpangan yang parah tidak perlu ditunggu selama penyimpangan ringan.
  Duration _requiredDwellFor(double severity) {
    if (severity >= config.severeSeverity) {
      return config.correctionDwell * config.severeDwellFactor;
    }
    return config.correctionDwell;
  }

  bool _isCooldownOver(DateTime now) {
    final last = _lastCorrectionAt;
    if (last == null) return true;
    return now.difference(last) >= config.correctionCooldown;
  }

  /// Selisih waktu antar sampel, dengan penjagaan terhadap lompatan besar
  /// (app sempat di background) dan jam yang mundur.
  Duration _stepSince(DateTime now) {
    final last = _lastTimestamp;
    if (last == null) return Duration.zero;
    final d = now.difference(last);
    if (d.isNegative || d > config.maxSampleGap) return Duration.zero;
    return d;
  }

  PostureEvaluation _build({
    required SensorSample sample,
    required PostureStatus status,
    required PostureDeviation deviation,
    required ActivityContext activity,
    required Duration requiredDwell,
    required bool correctionTriggered,
    required bool isMotionTransient,
  }) {
    final breakDue = _stats.usageDuration >= config.breakReminderAfter;
    final breakTriggered = breakDue && !_breakReminderSent;
    if (breakTriggered) _breakReminderSent = true;

    return PostureEvaluation(
      timestamp: sample.timestamp,
      status: status,
      deviation: deviation,
      sample: sample,
      orientation: sample.stableOrientation,
      activity: activity,
      outOfComfortFor: _outOfComfortFor,
      requiredDwell: requiredDwell,
      stats: _stats,
      correctionTriggered: correctionTriggered,
      breakReminderDue: breakTriggered,
      isMotionTransient: isMotionTransient,
    );
  }
}
