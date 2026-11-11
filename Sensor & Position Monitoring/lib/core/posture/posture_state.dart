import '../sensors/device_orientation.dart';
import '../sensors/sensor_sample.dart';

/// Konteks aktivitas pengguna.
///
/// Modul Activity Recognition yang sebenarnya berada di luar file ini; nilai
/// ini cukup disuntikkan lewat `PostureMonitor.setActivity()`.
enum ActivityContext {
  still,
  walking,
  inVehicle,
  unknown;

  String get label => switch (this) {
        ActivityContext.still => 'Diam',
        ActivityContext.walking => 'Berjalan',
        ActivityContext.inVehicle => 'Di kendaraan',
        ActivityContext.unknown => 'Tidak diketahui',
      };
}

/// Status posisi hasil evaluasi.
enum PostureStatus {
  /// Posisi masih di dalam zona nyaman.
  good,

  /// Di luar zona nyaman, tapi belum cukup lama untuk ditegur.
  /// Inilah yang membuat gerakan sesaat tidak langsung dianggap masalah.
  drifting,

  /// Sudah bertahan melewati threshold — saatnya memberi arahan koreksi.
  needsCorrection,

  /// Monitoring dijeda (mis. sedang di kendaraan).
  paused,

  /// Pembacaan sensor tidak bisa dipercaya (perangkat diguncang keras).
  unreliable;

  String get label => switch (this) {
        PostureStatus.good => 'Posisi nyaman',
        PostureStatus.drifting => 'Mulai bergeser',
        PostureStatus.needsCorrection => 'Perlu dikoreksi',
        PostureStatus.paused => 'Dijeda',
        PostureStatus.unreliable => 'Sensor tidak stabil',
      };
}

/// Rincian seberapa jauh posisi sekarang menyimpang dari baseline.
class PostureDeviation {
  const PostureDeviation({
    required this.tiltDeltaDeg,
    required this.rotationDeltaDeg,
    required this.tiltExcessDeg,
    required this.rotationExcessDeg,
    required this.severity,
  });

  /// Selisih kemiringan terhadap baseline.
  /// Positif = HP lebih MENDATAR dari baseline (kepala lebih menunduk).
  /// Negatif = HP lebih TEGAK dari baseline.
  final double tiltDeltaDeg;

  /// Selisih sudut putar terhadap baseline (-180..180).
  final double rotationDeltaDeg;

  /// Kelebihan kemiringan di luar toleransi. 0 bila masih di zona nyaman.
  final double tiltExcessDeg;

  /// Kelebihan perputaran di luar toleransi. 0 bila masih di zona nyaman.
  final double rotationExcessDeg;

  /// Tingkat penyimpangan relatif terhadap toleransi.
  /// 0 = tepat di batas, 1 = kelebihan sebesar satu kali toleransi.
  final double severity;

  bool get isOutOfComfort => tiltExcessDeg > 0 || rotationExcessDeg > 0;

  /// Arah koreksi utama yang perlu disampaikan ke pengguna.
  String get hint {
    if (!isOutOfComfort) return 'Posisi sudah sesuai.';
    if (tiltExcessDeg > 0 && tiltDeltaDeg > 0) {
      return 'HP terlalu mendatar. Angkat sedikit supaya kepala tidak menunduk.';
    }
    if (tiltExcessDeg > 0 && tiltDeltaDeg < 0) {
      return 'HP terlalu tegak dibanding posisi awal. Turunkan sedikit.';
    }
    return 'HP miring ke samping. Luruskan kembali seperti posisi awal.';
  }

  static const PostureDeviation none = PostureDeviation(
    tiltDeltaDeg: 0,
    rotationDeltaDeg: 0,
    tiltExcessDeg: 0,
    rotationExcessDeg: 0,
    severity: 0,
  );
}

/// Akumulasi statistik satu sesi monitoring.
class PostureSessionStats {
  const PostureSessionStats({
    this.activeDuration = Duration.zero,
    this.goodDuration = Duration.zero,
    this.badDuration = Duration.zero,
    this.pausedDuration = Duration.zero,
    this.correctionCount = 0,
  });

  /// Total durasi yang benar-benar dievaluasi (tidak termasuk jeda).
  final Duration activeDuration;

  /// Durasi posisi berada di zona nyaman.
  final Duration goodDuration;

  /// Durasi posisi berada di luar zona nyaman.
  final Duration badDuration;

  /// Durasi monitoring dijeda.
  final Duration pausedDuration;

  /// Berapa kali arahan koreksi dipicu.
  final int correctionCount;

  /// Position Score 0..100 — salah satu output utama MOVA.
  double get positionScore {
    if (activeDuration.inMilliseconds == 0) return 100.0;
    return (goodDuration.inMilliseconds / activeDuration.inMilliseconds * 100)
        .clamp(0.0, 100.0);
  }

  /// Total durasi pemakaian termasuk jeda — dipakai pengingat istirahat.
  Duration get usageDuration => activeDuration + pausedDuration;

  PostureSessionStats copyWith({
    Duration? activeDuration,
    Duration? goodDuration,
    Duration? badDuration,
    Duration? pausedDuration,
    int? correctionCount,
  }) {
    return PostureSessionStats(
      activeDuration: activeDuration ?? this.activeDuration,
      goodDuration: goodDuration ?? this.goodDuration,
      badDuration: badDuration ?? this.badDuration,
      pausedDuration: pausedDuration ?? this.pausedDuration,
      correctionCount: correctionCount ?? this.correctionCount,
    );
  }
}

/// Hasil satu kali evaluasi posisi.
class PostureEvaluation {
  const PostureEvaluation({
    required this.timestamp,
    required this.status,
    required this.deviation,
    required this.sample,
    required this.orientation,
    required this.activity,
    required this.outOfComfortFor,
    required this.requiredDwell,
    required this.stats,
    required this.correctionTriggered,
    required this.breakReminderDue,
    required this.isMotionTransient,
  });

  final DateTime timestamp;
  final PostureStatus status;
  final PostureDeviation deviation;

  /// Sampel sensor yang menghasilkan evaluasi ini.
  final SensorSample sample;

  /// Orientasi efektif saat evaluasi.
  final ScreenOrientation orientation;

  final ActivityContext activity;

  /// Sudah berapa lama posisi bertahan di luar zona nyaman.
  final Duration outOfComfortFor;

  /// Ambang durasi yang harus dilewati sebelum koreksi dipicu.
  /// Nilainya memendek otomatis bila penyimpangan tergolong parah.
  final Duration requiredDwell;

  final PostureSessionStats stats;

  /// True TEPAT pada evaluasi yang memicu arahan koreksi. Pakai flag ini
  /// untuk menembakkan notifikasi/haptic agar tidak berulang tiap frame.
  final bool correctionTriggered;

  /// True saat durasi pemakaian melewati ambang pengingat istirahat.
  final bool breakReminderDue;

  /// True saat HP sedang digerakkan — timer dibekukan sementara.
  final bool isMotionTransient;

  /// Progres menuju peringatan, 0..1. Cocok untuk progress bar di UI.
  double get dwellProgress {
    if (requiredDwell.inMilliseconds == 0) return 0;
    return (outOfComfortFor.inMilliseconds / requiredDwell.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  /// Pesan singkat siap tampil.
  String get message => switch (status) {
        PostureStatus.good => 'Posisi kamu masih nyaman.',
        PostureStatus.drifting => 'Posisi mulai bergeser dari posisi awal.',
        PostureStatus.needsCorrection => deviation.hint,
        PostureStatus.paused =>
          'Monitoring posisi dijeda karena kamu sedang ${activity.label.toLowerCase()}.',
        PostureStatus.unreliable => 'Sensor belum stabil, menunggu sebentar.',
      };
}
