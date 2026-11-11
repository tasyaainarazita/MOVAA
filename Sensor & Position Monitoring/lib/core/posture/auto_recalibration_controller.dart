import 'dart:async';

import '../sensors/device_orientation.dart';
import '../sensors/sensor_sample.dart';
import 'posture_baseline.dart';
import 'posture_config.dart';

/// Fase rekalibrasi otomatis saat orientasi berpindah ke landscape.
enum AutoRecalibrationPhase {
  /// Tidak ada proses rekalibrasi yang aktif.
  idle,

  /// Orientasi baru terbaca landscape, menunggu durasi stabilisasi (settling).
  settling,

  /// Orientasi sudah stabil, menunggu perangkat diam/stasioner sebelum merekam.
  waitingForStillness,

  /// Sedang mengumpulkan sampel sensor posisi landscape.
  collecting,

  /// Rekalibrasi otomatis berhasil dan baseline landscape baru divalidasi.
  success,

  /// Rekalibrasi otomatis gagal (mis. timeout atau gerakan berlebih).
  /// Baseline sebelumnya tetap dipertahankan.
  failed,
}

/// Status rekalibrasi otomatis untuk observasi UI / pengujian.
class AutoRecalibrationState {
  const AutoRecalibrationState({
    required this.phase,
    this.progress = 0.0,
    this.message = '',
    this.baseline,
  });

  final AutoRecalibrationPhase phase;
  final double progress;
  final String message;
  final PostureBaseline? baseline;

  bool get isActive =>
      phase == AutoRecalibrationPhase.settling ||
      phase == AutoRecalibrationPhase.waitingForStillness ||
      phase == AutoRecalibrationPhase.collecting;
}

/// Pengontrol rekalibrasi otomatis saat ponsel bertransisi dari portrait ke landscape.
///
/// Aturan kerja:
/// 1. Mendeteksi transisi dari portrait ke landscape.
/// 2. Menunggu orientasi bertahan stabil selama [PostureConfig.orientationSettlingDuration].
/// 3. Memastikan perangkat cukup diam (angular speed & jitter rendah).
/// 4. Mengumpulkan sampel dan memvalidasi sebaran kemiringan.
/// 5. Mengirimkan baseline landscape baru bila valid.
/// 6. Menjaga agar tidak memicu rekalibrasi berulang kali saat sudah di landscape.
/// 7. Tidak menimpa baseline lama bila proses gagal.
class AutoRecalibrationController {
  AutoRecalibrationController({
    this.config = const PostureConfig(),
    this.onBaselineCalibrated,
  });

  final PostureConfig config;
  final void Function(PostureBaseline baseline)? onBaselineCalibrated;

  final StreamController<AutoRecalibrationState> _states =
      StreamController<AutoRecalibrationState>.broadcast();

  Stream<AutoRecalibrationState> get states => _states.stream;

  AutoRecalibrationState _state = const AutoRecalibrationState(
    phase: AutoRecalibrationPhase.idle,
    message: 'Standby',
  );
  AutoRecalibrationState get state => _state;

  ScreenOrientation _lastOrientation = ScreenOrientation.unknown;
  DateTime? _settlingSince;
  DateTime? _waitingSince;
  DateTime? _collectingSince;
  DateTime? _lastAttemptAt;

  final List<double> _tilts = <double>[];
  final List<double> _rotations = <double>[];

  void reset() {
    _tilts.clear();
    _rotations.clear();
    _settlingSince = null;
    _waitingSince = null;
    _collectingSince = null;
    _emit(const AutoRecalibrationState(
      phase: AutoRecalibrationPhase.idle,
      message: 'Standby',
    ));
  }

  void cancel() {
    reset();
  }

  void dispose() {
    reset();
    _states.close();
  }

  /// Masukkan satu sampel sensor untuk dievaluasi oleh controller ini.
  void onSample(SensorSample sample) {
    if (!config.autoRecalibrateOnLandscape) return;

    final currentOrientation = sample.stableOrientation;

    // Deteksi transisi dari portrait ke landscape
    final isTransitionToLandscape = _lastOrientation.isPortrait &&
        currentOrientation.isLandscape;

    if (currentOrientation.isResolved) {
      // Periksa bila orientasi berpindah kembali ke portrait saat sedang proses
      if (currentOrientation.isPortrait && _state.isActive) {
        reset();
        _lastOrientation = currentOrientation;
        return;
      }
    }

    // Inisiasi settling jika ada transisi baru dan cooldown terpenuhi
    if (isTransitionToLandscape && !_state.isActive) {
      final now = sample.timestamp;
      final inCooldown = _lastAttemptAt != null &&
          now.difference(_lastAttemptAt!) < config.autoCalibrationCooldown;

      if (!inCooldown) {
        _settlingSince = sample.timestamp;
        _emit(const AutoRecalibrationState(
          phase: AutoRecalibrationPhase.settling,
          message: 'Orientasi landscape terdeteksi, menstabilkan...',
        ));
      }
    }

    _lastOrientation = currentOrientation;

    // Evaluasi tahapan aktif
    switch (_state.phase) {
      case AutoRecalibrationPhase.settling:
        _handleSettling(sample);
        break;
      case AutoRecalibrationPhase.waitingForStillness:
      case AutoRecalibrationPhase.collecting:
        _handleCollection(sample);
        break;
      case AutoRecalibrationPhase.idle:
      case AutoRecalibrationPhase.success:
      case AutoRecalibrationPhase.failed:
        break;
    }
  }

  void _handleSettling(SensorSample sample) {
    if (!sample.stableOrientation.isLandscape) {
      // Orientasi berfluktuasi/batal landscape
      reset();
      return;
    }

    final settlingTime =
        sample.timestamp.difference(_settlingSince ?? sample.timestamp);
    if (settlingTime >= config.orientationSettlingDuration) {
      // Orientasi sudah stabil di landscape
      _waitingSince = sample.timestamp;
      _tilts.clear();
      _rotations.clear();
      _collectingSince = null;
      _emit(const AutoRecalibrationState(
        phase: AutoRecalibrationPhase.waitingForStillness,
        message: 'Tahan HP diam pada posisi landscape nyaman...',
      ));
    }
  }

  void _handleCollection(SensorSample sample) {
    if (!sample.stableOrientation.isLandscape) {
      _fail('Orientasi berubah saat kalibrasi otomatis.');
      return;
    }

    // Cek batas timeout menunggu diam (maksimal 15 detik)
    if (_state.phase == AutoRecalibrationPhase.waitingForStillness &&
        _waitingSince != null &&
        sample.timestamp.difference(_waitingSince!) > const Duration(seconds: 15)) {
      _fail('Waktu kalibrasi otomatis habis. HP terus bergerak.');
      return;
    }

    final isStill = sample.angularSpeed <= config.calibrationMaxAngularSpeed &&
        sample.jitter <= config.calibrationMaxJitter &&
        sample.isGravityReliable;

    if (!isStill) {
      // Perangkat bergerak saat pengumpulan
      if (_tilts.isNotEmpty || _collectingSince != null) {
        _tilts.clear();
        _rotations.clear();
        _collectingSince = null;
      }
      _emit(const AutoRecalibrationState(
        phase: AutoRecalibrationPhase.waitingForStillness,
        message: 'Perangkat bergerak, tahan posisi landscape...',
      ));
      return;
    }

    _collectingSince ??= sample.timestamp;
    _tilts.add(sample.screenTiltDeg);
    _rotations.add(sample.rotationDeg);

    final elapsed = sample.timestamp.difference(_collectingSince!);
    final total = config.calibrationDuration;
    final progress =
        (elapsed.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

    if (elapsed < total) {
      _emit(AutoRecalibrationState(
        phase: AutoRecalibrationPhase.collecting,
        progress: progress,
        message: 'Merekam posisi landscape otomatis...',
      ));
      return;
    }

    // Selesai pengumpulan, validasi baseline
    _completeCollection(sample);
  }

  void _completeCollection(SensorSample sample) {
    if (_tilts.length < config.calibrationMinSamples) {
      _fail('Data sensor landscape kurang memadai.');
      return;
    }

    final spread = _spreadOf(_tilts);
    if (spread > config.calibrationMaxTiltSpreadDeg) {
      _fail('Posisi landscape belum cukup stabil.');
      return;
    }

    final tilt = AngleUtils.median(_tilts);
    final rotation = AngleUtils.circularMeanDeg(_rotations);

    final baseline = PostureBaseline(
      tiltDeg: tilt,
      rotationDeg: rotation,
      orientation: sample.stableOrientation,
      capturedAt: sample.timestamp,
      sampleCount: _tilts.length,
      tiltSpreadDeg: spread,
    );

    _lastAttemptAt = sample.timestamp;
    _emit(AutoRecalibrationState(
      phase: AutoRecalibrationPhase.success,
      progress: 1.0,
      message: 'Rekalibrasi landscape otomatis selesai.',
      baseline: baseline,
    ));

    onBaselineCalibrated?.call(baseline);
  }

  void _fail(String message) {
    _lastAttemptAt = DateTime.now();
    _tilts.clear();
    _rotations.clear();
    _settlingSince = null;
    _waitingSince = null;
    _collectingSince = null;

    _emit(AutoRecalibrationState(
      phase: AutoRecalibrationPhase.failed,
      message: message,
    ));
  }

  double _spreadOf(List<double> values) {
    final sorted = List<double>.from(values)..sort();
    final lo = sorted[(sorted.length * 0.05).floor()];
    final hi = sorted[
        ((sorted.length * 0.95).ceil() - 1).clamp(0, sorted.length - 1)];
    return (hi - lo).abs();
  }

  void _emit(AutoRecalibrationState state) {
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }
}
