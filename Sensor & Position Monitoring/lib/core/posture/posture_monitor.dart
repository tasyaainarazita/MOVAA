import 'dart:async';

import '../sensors/device_orientation.dart';
import '../sensors/sensor_sample.dart';
import '../sensors/sensor_service.dart';
import 'activity_estimator.dart';
import 'auto_recalibration_controller.dart';
import 'calibration_controller.dart';
import 'orientation_baseline_store.dart';
import 'posture_analyzer.dart';
import 'posture_baseline.dart';
import 'posture_config.dart';
import 'posture_state.dart';

/// Titik masuk tunggal modul Sensor & Position Logic.
///
/// Menyatukan tiga bagian:
///   * [SensorService]          — membaca accelerometer + gyroscope
///   * [CalibrationController]  — membentuk baseline personal
///   * [PostureAnalyzer]        — menilai posisi terhadap baseline
///
/// Bagian UI cukup memakai kelas ini:
///
/// ```dart
/// final monitor = PostureMonitor();
/// monitor.startSensors();
/// await monitor.calibrate();          // pengguna menahan posisi nyaman
/// monitor.startMonitoring();
/// monitor.evaluations.listen((e) { ... });
/// ```
class PostureMonitor {
  PostureMonitor({PostureConfig? config, SensorService? sensorService})
      : config = config ?? const PostureConfig(),
        _sensors = sensorService ??
            SensorService(config: config ?? const PostureConfig()) {
    _analyzer = PostureAnalyzer(config: this.config);
    _autoRecalibrator = AutoRecalibrationController(
      config: this.config,
      onBaselineCalibrated: (landscapeBaseline) {
        _baselineStore.landscape = landscapeBaseline;
        _analyzer.reset();
      },
    );
  }

  final PostureConfig config;
  final SensorService _sensors;
  late final PostureAnalyzer _analyzer;
  final ActivityEstimator _activityEstimator = ActivityEstimator();

  final StreamController<PostureEvaluation> _evaluations =
      StreamController<PostureEvaluation>.broadcast();

  StreamSubscription<SensorSample>? _sub;
  CalibrationController? _calibration;

  final OrientationBaselineStore _baselineStore = OrientationBaselineStore();
  late final AutoRecalibrationController _autoRecalibrator;

  ActivityContext? _manualActivity;
  bool _monitoring = false;
  DateTime? _sessionStartedAt;

  // ------------------------------------------------------------- getters --

  /// Aliran hasil evaluasi posisi, satu per sampel sensor.
  Stream<PostureEvaluation> get evaluations => _evaluations.stream;

  /// Aliran sampel sensor mentah yang sudah diolah (untuk debug / visualisasi).
  Stream<SensorSample> get samples => _sensors.samples;

  Stream<Object> get sensorErrors => _sensors.errors;

  /// Baseline aktif sesuai orientasi sampel terakhir (atau fallback yang tersedia).
  PostureBaseline? get baseline =>
      _baselineStore.get(_sensors.lastSample?.stableOrientation ?? ScreenOrientation.portrait);

  /// Baseline khusus orientasi portrait.
  PostureBaseline? get portraitBaseline => _baselineStore.portrait;

  /// Baseline khusus orientasi landscape.
  PostureBaseline? get landscapeBaseline => _baselineStore.landscape;

  /// Mengambil baseline untuk orientasi tertentu dengan fallback otomatis.
  PostureBaseline? baselineFor(ScreenOrientation orientation) =>
      _baselineStore.get(orientation);

  /// True bila sudah ada setidaknya satu baseline (portrait atau landscape).
  bool get isCalibrated => _baselineStore.hasAny;

  /// True bila orientasi spesifik sudah memiliki baseline sendiri.
  bool isCalibratedFor(ScreenOrientation orientation) =>
      _baselineStore.hasFor(orientation);

  /// Aliran status rekalibrasi otomatis saat orientasi berpindah ke landscape.
  Stream<AutoRecalibrationState> get autoRecalibrationStates =>
      _autoRecalibrator.states;

  AutoRecalibrationState get autoRecalibrationState => _autoRecalibrator.state;

  bool get isMonitoring => _monitoring;
  PostureSessionStats get stats => _analyzer.stats;
  DateTime? get sessionStartedAt => _sessionStartedAt;

  /// Aktivitas yang sedang dipakai analyzer.
  ActivityContext get activity => _manualActivity ?? _activityEstimator.current;

  // ------------------------------------------------------------- sensor ---

  /// Nyalakan sensor. Perlu dipanggil sebelum kalibrasi maupun monitoring.
  void startSensors() => _sensors.start();

  /// Matikan sensor agar tidak boros baterai.
  Future<void> stopSensors() => _sensors.stop();

  // ---------------------------------------------------------- kalibrasi ---

  /// Mulai kalibrasi dan kembalikan aliran progresnya untuk ditampilkan di UI.
  Stream<CalibrationState> calibrationStream({
    Duration timeout = const Duration(seconds: 30),
  }) {
    _calibration?.dispose();
    final controller = CalibrationController(
      sampleStream: _sensors.samples,
      config: config,
    );
    _calibration = controller;

    controller.states.listen((state) {
      if (state.phase == CalibrationPhase.success && state.baseline != null) {
        _baselineStore.set(state.baseline!);
        _analyzer.reset();
      }
    });

    controller.start(timeout: timeout);
    return controller.states;
  }

  /// Versi ringkas: tunggu sampai kalibrasi selesai, kembalikan baseline-nya.
  /// Mengembalikan null bila gagal.
  Future<PostureBaseline?> calibrate({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final stream = calibrationStream(timeout: timeout);
    final done = await stream.firstWhere((s) => s.isFinished);
    return done.baseline;
  }

  /// Pasang baseline yang sudah tersimpan sebelumnya (mis. dari SharedPreferences).
  /// Otomatis dimasukkan ke slot portrait atau landscape sesuai nilai orientasinya.
  void restoreBaseline(PostureBaseline baseline) {
    _baselineStore.set(baseline);
    _analyzer.reset();
  }

  /// Memulihkan baseline portrait dan landscape secara bersamaan.
  void restoreBaselines({
    PostureBaseline? portrait,
    PostureBaseline? landscape,
  }) {
    if (portrait != null) _baselineStore.portrait = portrait;
    if (landscape != null) _baselineStore.landscape = landscape;
    _analyzer.reset();
  }

  /// Hapus baseline. Bila [orientation] tidak ditentukan, hapus keduanya.
  void clearBaseline({ScreenOrientation? orientation}) {
    _baselineStore.clear(orientation: orientation);
    _analyzer.reset();
  }

  // --------------------------------------------------------- monitoring ---

  /// Mulai sesi monitoring. Wajib sudah terkalibrasi.
  ///
  /// Throws [StateError] bila belum ada baseline.
  void startMonitoring() {
    if (!isCalibrated) {
      throw StateError('Belum ada baseline. Jalankan calibrate() dulu.');
    }
    if (_monitoring) return;

    if (!_sensors.isRunning) _sensors.start();

    _analyzer.reset();
    _activityEstimator.reset();
    _autoRecalibrator.reset();
    _sessionStartedAt = DateTime.now();
    _monitoring = true;

    _sub = _sensors.samples.listen((sample) {
      // Periksa dan jalankan proses rekalibrasi landscape otomatis bila relevan
      _autoRecalibrator.onSample(sample);

      // Gunakan baseline sesuai orientasi sampel terkini (dengan fallback)
      final current = _baselineStore.get(sample.stableOrientation);
      if (!_monitoring || current == null) return;

      // Aktivitas manual (dari modul Activity Recognition) diutamakan;
      // kalau belum diset, pakai taksiran internal.
      final estimated = _activityEstimator.update(sample);
      final activity = _manualActivity ?? estimated;

      final evaluation = _analyzer.evaluate(
        sample: sample,
        baseline: current,
        activity: activity,
      );

      if (!_evaluations.isClosed) _evaluations.add(evaluation);
    });
  }

  /// Hentikan sesi monitoring dan kembalikan ringkasan sesinya.
  PostureSessionStats stopMonitoring() {
    _monitoring = false;
    _sub?.cancel();
    _sub = null;
    _autoRecalibrator.reset();
    return _analyzer.stats;
  }

  /// Suntikkan aktivitas dari modul Activity Recognition.
  /// Berikan null untuk kembali memakai taksiran internal.
  void setActivity(ActivityContext? activity) => _manualActivity = activity;

  /// Evaluasi sekali terhadap sampel terakhir — berguna untuk menampilkan
  /// pratinjau posisi di layar kalibrasi tanpa memulai sesi.
  PostureDeviation? previewDeviation() {
    final sample = _sensors.lastSample;
    if (sample == null) return null;
    final current = _baselineStore.get(sample.stableOrientation);
    if (current == null) return null;
    return _analyzer.computeDeviation(
      sample: sample,
      baseline: current,
      activity: activity,
    );
  }

  Future<void> dispose() async {
    stopMonitoring();
    _autoRecalibrator.dispose();
    _calibration?.dispose();
    await _sensors.dispose();
    await _evaluations.close();
  }
}
