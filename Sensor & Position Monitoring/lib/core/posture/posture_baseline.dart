import '../sensors/device_orientation.dart';

/// Posisi acuan personal hasil kalibrasi.
///
/// Sesuai konsep MOVA, tidak ada satu sudut ideal yang berlaku untuk semua
/// orang. Baseline ini direkam dari posisi yang dinyatakan nyaman oleh
/// pengguna itu sendiri, lalu dipakai sebagai pembanding saat monitoring.
class PostureBaseline {
  const PostureBaseline({
    required this.tiltDeg,
    required this.rotationDeg,
    required this.orientation,
    required this.capturedAt,
    required this.sampleCount,
    required this.tiltSpreadDeg,
  });

  /// Kemiringan layar acuan, dalam derajat.
  /// 0 = layar menghadap langit, 90 = layar tegak lurus.
  final double tiltDeg;

  /// Sudut putar layar acuan.
  final double rotationDeg;

  /// Orientasi saat kalibrasi diambil.
  final ScreenOrientation orientation;

  final DateTime capturedAt;

  /// Jumlah sampel yang dipakai membentuk baseline.
  final int sampleCount;

  /// Sebaran kemiringan selama kalibrasi — makin kecil makin stabil.
  final double tiltSpreadDeg;

  /// Skor kestabilan 0..1, dipakai UI untuk menilai kualitas kalibrasi.
  double get stabilityScore {
    final s = 1.0 - (tiltSpreadDeg / 10.0);
    return s.clamp(0.0, 1.0);
  }

  /// True bila posisi yang dikalibrasi sendiri sudah tergolong menunduk dalam.
  /// UI bisa menyarankan pengguna mengangkat HP sedikit lalu kalibrasi ulang.
  bool get isRiskyBaseline => tiltDeg < 35.0;

  /// Deskripsi singkat posisi acuan untuk ditampilkan ke pengguna.
  String get description {
    if (tiltDeg < 35) return 'Cenderung menunduk';
    if (tiltDeg < 70) return 'Agak condong';
    if (tiltDeg < 110) return 'Tegak dan netral';
    return 'Condong ke belakang';
  }

  Map<String, dynamic> toJson() => {
        'tiltDeg': tiltDeg,
        'rotationDeg': rotationDeg,
        'orientation': orientation.name,
        'capturedAt': capturedAt.toIso8601String(),
        'sampleCount': sampleCount,
        'tiltSpreadDeg': tiltSpreadDeg,
      };

  factory PostureBaseline.fromJson(Map<String, dynamic> json) {
    return PostureBaseline(
      tiltDeg: (json['tiltDeg'] as num).toDouble(),
      rotationDeg: (json['rotationDeg'] as num).toDouble(),
      orientation: ScreenOrientation.values.firstWhere(
        (o) => o.name == json['orientation'],
        orElse: () => ScreenOrientation.portrait,
      ),
      capturedAt: DateTime.parse(json['capturedAt'] as String),
      sampleCount: (json['sampleCount'] as num).toInt(),
      tiltSpreadDeg: (json['tiltSpreadDeg'] as num).toDouble(),
    );
  }

  @override
  String toString() => 'PostureBaseline(tilt: ${tiltDeg.toStringAsFixed(1)}, '
      'rot: ${rotationDeg.toStringAsFixed(1)}, ${orientation.name})';
}
