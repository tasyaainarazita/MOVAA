import 'dart:collection';
import 'dart:math' as math;

import '../sensors/sensor_sample.dart';
import 'posture_state.dart';

/// Penaksir aktivitas sederhana berbasis getaran accelerometer + gyroscope.
///
/// CATATAN: ini sengaja dibuat ringan sebagai pengisi sementara supaya modul
/// posisi bisa diuji utuh. Modul Activity Recognition yang sebenarnya
/// (mis. lewat Activity Recognition API) nantinya tinggal menggantikan kelas
/// ini — [PostureMonitor.setActivity] menerima nilai dari sumber mana pun.
///
/// Aturan kasar yang dipakai:
///   * getaran sangat kecil            -> diam
///   * getaran berirama & kuat         -> berjalan
///   * getaran sedang tapi rotasi kecil-> di kendaraan
class ActivityEstimator {
  ActivityEstimator({this.windowSize = 50});

  /// Banyak sampel yang dipakai untuk menghitung rata-rata bergerak.
  final int windowSize;

  final Queue<double> _jitter = Queue<double>();
  final Queue<double> _angular = Queue<double>();

  ActivityContext _current = ActivityContext.still;
  ActivityContext get current => _current;

  void reset() {
    _jitter.clear();
    _angular.clear();
    _current = ActivityContext.still;
  }

  /// Masukkan satu sampel, dapatkan taksiran aktivitas terkini.
  ActivityContext update(SensorSample sample) {
    _push(_jitter, sample.jitter);
    _push(_angular, sample.angularSpeed);

    if (_jitter.length < windowSize ~/ 2) return _current;

    final jitterRms = _rms(_jitter);
    final angularMean = _mean(_angular);

    if (jitterRms < 0.35 && angularMean < 0.15) {
      _current = ActivityContext.still;
    } else if (jitterRms >= 1.6 && angularMean >= 0.35) {
      // Langkah kaki menghasilkan guncangan besar disertai ayunan tangan.
      _current = ActivityContext.walking;
    } else if (jitterRms >= 0.35 && angularMean < 0.25) {
      // Bergetar terus tapi perangkat nyaris tidak diputar: ciri kendaraan.
      _current = ActivityContext.inVehicle;
    } else {
      _current = ActivityContext.walking;
    }

    return _current;
  }

  void _push(Queue<double> q, double value) {
    q.addLast(value);
    while (q.length > windowSize) {
      q.removeFirst();
    }
  }

  double _mean(Queue<double> q) {
    if (q.isEmpty) return 0;
    return q.reduce((a, b) => a + b) / q.length;
  }

  double _rms(Queue<double> q) {
    if (q.isEmpty) return 0;
    final sum = q.fold<double>(0, (acc, v) => acc + v * v);
    return math.sqrt(sum / q.length);
  }
}
