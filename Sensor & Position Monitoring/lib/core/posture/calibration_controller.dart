import 'dart:async';

import '../sensors/sensor_sample.dart';
import 'posture_baseline.dart';
import 'posture_config.dart';

/// Tahapan proses kalibrasi.
enum CalibrationPhase {
  /// Belum dimulai.
  idle,

  /// Menunggu perangkat benar-benar diam sebelum mulai merekam.
  waitingForStillness,

  /// Sedang merekam sampel posisi nyaman.
  collecting,

  /// Baseline berhasil dibuat.
  success,

  /// Gagal — biasanya karena perangkat terus bergerak.
  failed,
}

/// Keadaan kalibrasi yang dikonsumsi UI.
class CalibrationState {
  const CalibrationState({
    required this.phase,
    this.progress = 0.0,
    this.remaining = Duration.zero,
    this.message = '',
    this.baseline,
  });

  final CalibrationPhase phase;

  /// 0.0 .. 1.0
  final double progress;

  /// Sisa waktu menahan posisi.
  final Duration remaining;

  /// Instruksi untuk pengguna.
  final String message;

  /// Terisi hanya saat [phase] == [CalibrationPhase.success].
  final PostureBaseline? baseline;

  bool get isFinished =>
      phase == CalibrationPhase.success || phase == CalibrationPhase.failed;
}

/// Mengubah aliran [SensorSample] menjadi satu [PostureBaseline].
///
/// Aturannya sederhana: pengguna memegang HP pada posisi yang paling nyaman,
/// sistem menunggu sampai perangkat benar-benar diam, lalu merekam selama
/// [PostureConfig.calibrationDuration]. Kalau di tengah jalan perangkat
/// digerakkan, hitungan diulang — bukan langsung gagal — supaya pengguna
/// tidak perlu menekan tombol lagi.
class CalibrationController {
  CalibrationController({
    required this.sampleStream,
    this.config = const PostureConfig(),
  });

  final Stream<SensorSample> sampleStream;
  final PostureConfig config;

  final StreamController<CalibrationState> _states =
      StreamController<CalibrationState>.broadcast();
  StreamSubscription<SensorSample>? _sub;
  Timer? _timeout;

  final List<double> _tilts = <double>[];
  final List<double> _rotations = <double>[];
  SensorSample? _lastSample;
  DateTime? _collectingSince;

  Stream<CalibrationState> get states => _states.stream;

  CalibrationState _state = const CalibrationState(
    phase: CalibrationPhase.idle,
    message: 'Siap melakukan kalibrasi.',
  );
  CalibrationState get state => _state;

  bool get isRunning => _sub != null;

  /// Mulai kalibrasi. [timeout] membatasi total waktu menunggu pengguna diam.
  void start({Duration timeout = const Duration(seconds: 30)}) {
    if (isRunning) return;

    _tilts.clear();
    _rotations.clear();
    _collectingSince = null;
    _lastSample = null;

    _emit(const CalibrationState(
      phase: CalibrationPhase.waitingForStillness,
      message: 'Pegang HP pada posisi yang paling nyaman, lalu tahan.',
    ));

    _sub = sampleStream.listen(_onSample);
    _timeout = Timer(timeout, () {
      _finishFailed('Kalibrasi gagal. Coba tahan HP lebih diam ya.');
    });
  }

  /// Batalkan kalibrasi yang sedang berjalan.
  void cancel() {
    _cleanup();
    _emit(const CalibrationState(
      phase: CalibrationPhase.idle,
      message: 'Kalibrasi dibatalkan.',
    ));
  }

  void dispose() {
    _cleanup();
    _states.close();
  }

  void _onSample(SensorSample sample) {
    _lastSample = sample;

    // Sampel hanya dipakai kalau perangkat memang sedang diam.
    final isStill = sample.angularSpeed <= config.calibrationMaxAngularSpeed &&
        sample.jitter <= config.calibrationMaxJitter &&
        sample.isGravityReliable;

    if (!isStill) {
      // Pengguna bergerak: buang rekaman dan minta ulang menahan posisi.
      if (_tilts.isNotEmpty || _collectingSince != null) {
        _tilts.clear();
        _rotations.clear();
        _collectingSince = null;
      }
      _emit(const CalibrationState(
        phase: CalibrationPhase.waitingForStillness,
        message: 'Tahan HP sebentar tanpa digerakkan...',
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
    final remaining = total - elapsed;

    if (elapsed < total) {
      _emit(CalibrationState(
        phase: CalibrationPhase.collecting,
        progress: progress,
        remaining: remaining.isNegative ? Duration.zero : remaining,
        message: 'Merekam posisi awal... tahan terus.',
      ));
      return;
    }

    _completeCollection();
  }

  void _completeCollection() {
    final sample = _lastSample;
    if (sample == null || _tilts.length < config.calibrationMinSamples) {
      _finishFailed('Data sensor kurang. Ulangi kalibrasi.');
      return;
    }

    // Median + circular mean dipilih karena tahan terhadap satu-dua sampel liar.
    final tilt = AngleUtils.median(_tilts);
    final rotation = AngleUtils.circularMeanDeg(_rotations);

    final spread = _spreadOf(_tilts);
    if (spread > config.calibrationMaxTiltSpreadDeg) {
      _finishFailed('Posisi masih berubah-ubah. Ulangi kalibrasi.');
      return;
    }

    final baseline = PostureBaseline(
      tiltDeg: tilt,
      rotationDeg: rotation,
      orientation: sample.stableOrientation,
      capturedAt: DateTime.now(),
      sampleCount: _tilts.length,
      tiltSpreadDeg: spread,
    );

    _cleanup();
    _emit(CalibrationState(
      phase: CalibrationPhase.success,
      progress: 1.0,
      message: 'Posisi awal tersimpan. Monitoring siap dimulai.',
      baseline: baseline,
    ));
  }

  /// Sebaran 5%-95% — lebih stabil dibanding (max - min) yang mudah dirusak
  /// oleh satu sampel ekstrem.
  double _spreadOf(List<double> values) {
    final sorted = List<double>.from(values)..sort();
    final lo = sorted[(sorted.length * 0.05).floor()];
    final hi = sorted[((sorted.length * 0.95).ceil() - 1).clamp(0, sorted.length - 1)];
    return (hi - lo).abs();
  }

  void _finishFailed(String message) {
    _cleanup();
    _emit(CalibrationState(
      phase: CalibrationPhase.failed,
      message: message,
    ));
  }

  void _cleanup() {
    _timeout?.cancel();
    _timeout = null;
    _sub?.cancel();
    _sub = null;
  }

  void _emit(CalibrationState state) {
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }
}
