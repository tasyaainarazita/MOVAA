import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

import '../posture/posture_config.dart';
import 'device_orientation.dart';
import 'sensor_sample.dart';
import 'vector3.dart';

/// Membaca accelerometer + gyroscope, lalu mengubahnya menjadi aliran
/// [SensorSample] yang sudah difilter dan siap dipakai logika postur.
///
/// Alur pengolahan:
///   1. Accelerometer mentah masuk (termasuk gravitasi).
///   2. Low-pass filter memisahkan komponen gravitasi dari guncangan.
///   3. Gravitasi diubah jadi sudut kemiringan layar + sudut putar layar.
///   4. Sudut putar diklasifikasikan jadi portrait / landscape (dengan histeresis).
///   5. Gyroscope terakhir ikut dilampirkan sebagai indikator gerakan.
///
/// Accelerometer yang menjadi pemicu emisi; gyroscope hanya di-cache karena
/// kedua sensor tidak pernah tiba pada waktu yang persis sama.
class SensorService {
  SensorService({this.config = const PostureConfig()});

  final PostureConfig config;

  final StreamController<SensorSample> _controller =
      StreamController<SensorSample>.broadcast();
  final StreamController<Object> _errors =
      StreamController<Object>.broadcast();

  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;

  /// Estimasi gravitasi berjalan. Nilai awal = HP mendatar menghadap atas.
  Vector3 _gravity = const Vector3(0, 0, 9.81);
  Vector3 _gyroscope = Vector3.zero;
  bool _filterPrimed = false;

  ScreenOrientation _stableOrientation = ScreenOrientation.unknown;

  /// Aliran sampel sensor yang sudah diolah.
  Stream<SensorSample> get samples => _controller.stream;

  /// Aliran error sensor (mis. perangkat tidak punya gyroscope).
  Stream<Object> get errors => _errors.stream;

  bool get isRunning => _accelSub != null;

  /// Sampel terakhir yang diemit, berguna untuk menampilkan nilai awal di UI.
  SensorSample? get lastSample => _lastSample;
  SensorSample? _lastSample;

  /// Mulai berlangganan kedua sensor.
  void start() {
    if (isRunning) return;

    _filterPrimed = false;
    _gyroscope = Vector3.zero;

    _gyroSub = gyroscopeEventStream(samplingPeriod: config.samplingPeriod)
        .listen(
      (event) => _gyroscope = Vector3(event.x, event.y, event.z),
      onError: _errors.add,
      cancelOnError: false,
    );

    _accelSub = accelerometerEventStream(samplingPeriod: config.samplingPeriod)
        .listen(
      _onAccelerometer,
      onError: _errors.add,
      cancelOnError: false,
    );
  }

  /// Hentikan langganan sensor (wajib dipanggil agar baterai tidak terkuras).
  Future<void> stop() async {
    await _accelSub?.cancel();
    await _gyroSub?.cancel();
    _accelSub = null;
    _gyroSub = null;
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
    await _errors.close();
  }

  void _onAccelerometer(AccelerometerEvent event) {
    final raw = Vector3(event.x, event.y, event.z);

    // Low-pass filter: sisakan komponen yang berubah lambat (gravitasi).
    if (!_filterPrimed) {
      _gravity = raw;
      _filterPrimed = true;
    } else {
      final a = config.gravityFilterAlpha;
      _gravity = _gravity * a + raw * (1 - a);
    }

    final sample = _buildSample(raw, _gravity, _gyroscope, DateTime.now());
    _lastSample = sample;
    if (!_controller.isClosed) _controller.add(sample);
  }

  /// Dipisah agar bisa dipanggil langsung dari unit test tanpa perangkat.
  SensorSample _buildSample(
    Vector3 raw,
    Vector3 gravity,
    Vector3 gyroscope,
    DateTime timestamp,
  ) {
    final unit = gravity.normalized();

    // Kemiringan layar: sudut antara normal layar (+Z) dan arah atas.
    final tilt =
        math.acos(unit.z.clamp(-1.0, 1.0)) * AngleUtils.radToDeg;

    // Sudut putar layar terhadap gravitasi di bidang layar.
    final rotation = math.atan2(unit.x, unit.y) * AngleUtils.radToDeg;

    final orientation =
        _classifyOrientation(rotation, gravity.horizontalMagnitude);

    if (orientation.isResolved) _stableOrientation = orientation;

    return SensorSample(
      timestamp: timestamp,
      rawAcceleration: raw,
      gravity: gravity,
      gyroscope: gyroscope,
      screenTiltDeg: tilt,
      rotationDeg: rotation,
      orientation: orientation,
      stableOrientation:
          _stableOrientation.isResolved ? _stableOrientation : orientation,
    );
  }

  /// Ubah sudut putar jadi portrait/landscape.
  ///
  /// Batas normalnya tiap 45 derajat, tapi sektor orientasi yang sedang aktif
  /// diperlebar sebesar [PostureConfig.orientationHysteresisDeg] supaya tidak
  /// bolak-balik ketika pengguna memegang HP tepat di perbatasan.
  ScreenOrientation _classifyOrientation(double rotationDeg, double horizontalG) {
    if (horizontalG < config.flatGravityThreshold) {
      return ScreenOrientation.flat;
    }

    const sectors = <ScreenOrientation, double>{
      ScreenOrientation.portrait: 0.0,
      ScreenOrientation.landscapeLeft: 90.0,
      ScreenOrientation.portraitUpsideDown: 180.0,
      ScreenOrientation.landscapeRight: -90.0,
    };

    // Pertahankan orientasi sekarang selama masih di dalam sektor yang diperlebar.
    final current = sectors[_stableOrientation];
    if (current != null) {
      final d = AngleUtils.diffDeg(rotationDeg, current).abs();
      if (d <= 45.0 + config.orientationHysteresisDeg) return _stableOrientation;
    }

    var best = ScreenOrientation.portrait;
    var bestDiff = double.infinity;
    sectors.forEach((orientation, center) {
      final d = AngleUtils.diffDeg(rotationDeg, center).abs();
      if (d < bestDiff) {
        bestDiff = d;
        best = orientation;
      }
    });
    return best;
  }

  /// Hanya untuk pengujian: suntikkan nilai sensor buatan tanpa perangkat fisik.
  SensorSample debugBuildSample({
    required Vector3 gravity,
    Vector3 gyroscope = Vector3.zero,
    Vector3? rawAcceleration,
    DateTime? timestamp,
  }) {
    return _buildSample(
      rawAcceleration ?? gravity,
      gravity,
      gyroscope,
      timestamp ?? DateTime.now(),
    );
  }
}
