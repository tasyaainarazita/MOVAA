import 'dart:math' as math;

/// Vektor 3 sumbu sederhana untuk data accelerometer / gyroscope.
///
/// Sengaja dibuat sendiri (bukan pakai package vector_math) supaya modul
/// Sensor & Position Logic ini tidak menambah dependency dan gampang diuji.
class Vector3 {
  const Vector3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  static const Vector3 zero = Vector3(0, 0, 0);

  double get magnitude => math.sqrt(x * x + y * y + z * z);

  /// Besar komponen yang sejajar bidang layar (sumbu X dan Y perangkat).
  double get horizontalMagnitude => math.sqrt(x * x + y * y);

  Vector3 operator +(Vector3 other) =>
      Vector3(x + other.x, y + other.y, z + other.z);

  Vector3 operator -(Vector3 other) =>
      Vector3(x - other.x, y - other.y, z - other.z);

  Vector3 operator *(double scalar) =>
      Vector3(x * scalar, y * scalar, z * scalar);

  /// Vektor satuan. Mengembalikan [zero] bila panjangnya nol.
  Vector3 normalized() {
    final m = magnitude;
    if (m == 0) return zero;
    return Vector3(x / m, y / m, z / m);
  }

  @override
  String toString() =>
      'Vector3(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)}, ${z.toStringAsFixed(2)})';
}
