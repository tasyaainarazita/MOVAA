import 'dart:math' as math;

import 'device_orientation.dart';
import 'vector3.dart';

/// Utilitas sudut yang dipakai lintas modul.
class AngleUtils {
  const AngleUtils._();

  static const double radToDeg = 180.0 / math.pi;

  /// Selisih sudut terpendek (hasil dalam rentang -180..180 derajat).
  static double diffDeg(double a, double b) {
    var d = (a - b) % 360.0;
    if (d > 180.0) d -= 360.0;
    if (d < -180.0) d += 360.0;
    return d;
  }

  /// Rata-rata sudut secara melingkar, aman untuk data di sekitar +-180.
  static double circularMeanDeg(List<double> anglesDeg) {
    if (anglesDeg.isEmpty) return 0;
    var sx = 0.0;
    var sy = 0.0;
    for (final a in anglesDeg) {
      final r = a / radToDeg;
      sx += math.cos(r);
      sy += math.sin(r);
    }
    return math.atan2(sy, sx) * radToDeg;
  }

  /// Nilai tengah (median) — lebih tahan outlier dibanding rata-rata biasa.
  static double median(List<double> values) {
    if (values.isEmpty) return 0;
    final sorted = List<double>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2.0;
  }
}

/// Satu titik data hasil gabungan accelerometer + gyroscope yang sudah diolah
/// menjadi besaran posisi yang siap dipakai logika postur.
class SensorSample {
  const SensorSample({
    required this.timestamp,
    required this.rawAcceleration,
    required this.gravity,
    required this.gyroscope,
    required this.screenTiltDeg,
    required this.rotationDeg,
    required this.orientation,
    required this.stableOrientation,
  });

  final DateTime timestamp;

  /// Accelerometer mentah (termasuk gravitasi), satuan m/s^2.
  final Vector3 rawAcceleration;

  /// Komponen gravitasi hasil low-pass filter, satuan m/s^2.
  final Vector3 gravity;

  /// Kecepatan sudut dari gyroscope, satuan rad/s.
  final Vector3 gyroscope;

  /// Kemiringan layar terhadap arah atas: sudut antara normal layar (+Z)
  /// dan lawan arah gravitasi.
  ///
  ///   *   0 derajat  -> layar menghadap langit (HP mendatar, kepala paling menunduk)
  ///   *  90 derajat  -> layar tegak lurus (posisi paling netral untuk leher)
  ///   * 180 derajat  -> layar menghadap lantai
  ///
  /// Nilai ini tidak terpengaruh portrait/landscape, sehingga satu baseline
  /// bisa dipakai untuk kedua orientasi.
  final double screenTiltDeg;

  /// Sudut putar layar terhadap gravitasi (-180..180).
  /// 0 = portrait tegak, +90 = landscape kiri, +-180 = portrait terbalik,
  /// -90 = landscape kanan. Tidak andal saat perangkat mendatar.
  final double rotationDeg;

  /// Orientasi sesaat, bisa bernilai [ScreenOrientation.flat].
  final ScreenOrientation orientation;

  /// Orientasi terakhir yang valid — dipakai saat perangkat mendatar supaya
  /// tampilan tidak berkedip antar orientasi.
  final ScreenOrientation stableOrientation;

  /// Percepatan murni tanpa gravitasi (indikator guncangan/gerakan linear).
  Vector3 get linearAcceleration => rawAcceleration - gravity;

  /// Besar guncangan linear, m/s^2.
  double get jitter => linearAcceleration.magnitude;

  /// Besar kecepatan sudut, rad/s. Ini indikator utama "HP sedang digerakkan".
  double get angularSpeed => gyroscope.magnitude;

  /// True bila pembacaan gravitasi masuk akal (mendekati 9.81 m/s^2).
  /// Saat perangkat diguncang keras, nilai ini menyimpang dan sudut jadi tidak
  /// bisa dipercaya.
  bool get isGravityReliable {
    final m = gravity.magnitude;
    return m > 7.0 && m < 12.5;
  }

  @override
  String toString() => 'SensorSample(tilt: ${screenTiltDeg.toStringAsFixed(1)}, '
      'rot: ${rotationDeg.toStringAsFixed(1)}, ${orientation.name}, '
      'gyro: ${angularSpeed.toStringAsFixed(2)})';
}
