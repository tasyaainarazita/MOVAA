/// Seluruh parameter yang bisa disetel untuk modul Sensor & Position Logic.
///
/// Nilai default di bawah adalah titik awal yang masuk akal; angka final
/// sebaiknya ditentukan lewat uji coba langsung di perangkat.
class PostureConfig {
  const PostureConfig({
    this.samplingPeriod = const Duration(milliseconds: 40),
    this.gravityFilterAlpha = 0.86,
    this.flatGravityThreshold = 2.5,
    this.orientationHysteresisDeg = 10.0,
    this.calibrationDuration = const Duration(seconds: 5),
    this.calibrationMaxAngularSpeed = 0.35,
    this.calibrationMaxJitter = 1.0,
    this.calibrationMaxTiltSpreadDeg = 7.0,
    this.calibrationMinSamples = 25,
    this.downwardToleranceDeg = 15.0,
    this.upwardToleranceDeg = 25.0,
    this.rotationToleranceDeg = 25.0,
    this.comfortHysteresisDeg = 3.0,
    this.correctionDwell = const Duration(seconds: 20),
    this.correctionCooldown = const Duration(seconds: 60),
    this.severeSeverity = 1.5,
    this.severeDwellFactor = 0.5,
    this.recoveryDecayFactor = 2.0,
    this.transientAngularSpeed = 1.2,
    this.maxSampleGap = const Duration(seconds: 1),
    this.walkingToleranceFactor = 1.6,
    this.pauseInVehicle = true,
    this.breakReminderAfter = const Duration(minutes: 30),
    this.autoRecalibrateOnLandscape = true,
    this.orientationSettlingDuration = const Duration(seconds: 1),
    this.autoCalibrationCooldown = const Duration(seconds: 15),
  });

  // ---------------------------------------------------------------- sensor --

  /// Laju pembacaan sensor. 40 ms (~25 Hz) sudah cukup untuk deteksi postur
  /// dan jauh lebih hemat baterai dibanding laju maksimum.
  final Duration samplingPeriod;

  /// Koefisien low-pass filter untuk memisahkan gravitasi dari accelerometer.
  /// Makin mendekati 1 makin halus, tapi makin lambat merespons perubahan.
  final double gravityFilterAlpha;

  /// Ambang komponen gravitasi pada bidang layar (m/s^2). Di bawah nilai ini
  /// perangkat dianggap mendatar dan portrait/landscape tidak dihitung.
  final double flatGravityThreshold;

  /// Margin tambahan agar orientasi tidak bolak-balik di sekitar batas 45 derajat.
  final double orientationHysteresisDeg;

  // ----------------------------------------------------------- kalibrasi ----

  /// Lama pengguna harus menahan HP pada posisi nyaman.
  final Duration calibrationDuration;

  /// Batas kecepatan sudut (rad/s) agar sampel dianggap "diam".
  final double calibrationMaxAngularSpeed;

  /// Batas guncangan linear (m/s^2) agar sampel dianggap "diam".
  final double calibrationMaxJitter;

  /// Sebaran kemiringan maksimum selama kalibrasi. Bila lebih besar dari ini,
  /// pengguna dianggap masih bergerak dan kalibrasi diulang.
  final double calibrationMaxTiltSpreadDeg;

  /// Jumlah sampel minimum agar baseline dianggap sah.
  final int calibrationMinSamples;

  // -------------------------------------------------------- zona nyaman -----

  /// Toleransi saat HP jadi LEBIH MENDATAR dari baseline (kepala menunduk).
  /// Dibuat lebih ketat karena arah inilah yang membebani leher.
  final double downwardToleranceDeg;

  /// Toleransi saat HP jadi LEBIH TEGAK dari baseline. Lebih longgar karena
  /// posisi ini umumnya masih nyaman.
  final double upwardToleranceDeg;

  /// Toleransi perputaran layar terhadap baseline (miring ke samping).
  final double rotationToleranceDeg;

  /// Histeresis agar status tidak berkedip persis di garis batas toleransi.
  final double comfortHysteresisDeg;

  // ------------------------------------------------------------- durasi -----

  /// Lama posisi harus bertahan di luar zona nyaman sebelum dianggap perlu
  /// dikoreksi. Inilah yang membuat gerakan sesaat tidak memicu peringatan.
  final Duration correctionDwell;

  /// Jeda minimum antar peringatan koreksi agar tidak mengganggu.
  final Duration correctionCooldown;

  /// Tingkat penyimpangan (kelipatan toleransi) yang dianggap parah.
  final double severeSeverity;

  /// Pengali dwell saat penyimpangan tergolong parah (0.5 = separuh waktu).
  final double severeDwellFactor;

  /// Kecepatan "pemulihan" timer saat posisi kembali nyaman. 2.0 berarti
  /// timer berkurang dua kali lebih cepat daripada saat bertambah.
  final double recoveryDecayFactor;

  /// Kecepatan sudut (rad/s) yang menandakan HP sedang digerakkan. Selama
  /// melewati ambang ini, timer dibekukan — bukan direset, bukan bertambah.
  final double transientAngularSpeed;

  /// Batas selisih waktu antar sampel. Selisih lebih besar (app ter-pause,
  /// layar mati) tidak ikut dihitung sebagai durasi.
  final Duration maxSampleGap;

  // ---------------------------------------------------------- konteks -------

  /// Pengali toleransi saat pengguna berjalan — sistem jadi lebih toleran.
  final double walkingToleranceFactor;

  /// Bila true, monitoring posisi dijeda saat pengguna berada di kendaraan.
  final bool pauseInVehicle;

  /// Durasi pemakaian sebelum pengingat istirahat dimunculkan.
  final Duration breakReminderAfter;

  /// Bila true, otomatis melakukan rekalibrasi saat beralih ke landscape.
  final bool autoRecalibrateOnLandscape;

  /// Durasi orientasi harus bertahan stabil sebelum rekalibrasi otomatis dimulai.
  final Duration orientationSettlingDuration;

  /// Jeda minimum antar percobaan rekalibrasi otomatis.
  final Duration autoCalibrationCooldown;

  PostureConfig copyWith({
    Duration? samplingPeriod,
    double? gravityFilterAlpha,
    double? flatGravityThreshold,
    double? orientationHysteresisDeg,
    Duration? calibrationDuration,
    double? calibrationMaxAngularSpeed,
    double? calibrationMaxJitter,
    double? calibrationMaxTiltSpreadDeg,
    int? calibrationMinSamples,
    double? downwardToleranceDeg,
    double? upwardToleranceDeg,
    double? rotationToleranceDeg,
    double? comfortHysteresisDeg,
    Duration? correctionDwell,
    Duration? correctionCooldown,
    double? severeSeverity,
    double? severeDwellFactor,
    double? recoveryDecayFactor,
    double? transientAngularSpeed,
    Duration? maxSampleGap,
    double? walkingToleranceFactor,
    bool? pauseInVehicle,
    Duration? breakReminderAfter,
    bool? autoRecalibrateOnLandscape,
    Duration? orientationSettlingDuration,
    Duration? autoCalibrationCooldown,
  }) {
    return PostureConfig(
      samplingPeriod: samplingPeriod ?? this.samplingPeriod,
      gravityFilterAlpha: gravityFilterAlpha ?? this.gravityFilterAlpha,
      flatGravityThreshold: flatGravityThreshold ?? this.flatGravityThreshold,
      orientationHysteresisDeg:
          orientationHysteresisDeg ?? this.orientationHysteresisDeg,
      calibrationDuration: calibrationDuration ?? this.calibrationDuration,
      calibrationMaxAngularSpeed:
          calibrationMaxAngularSpeed ?? this.calibrationMaxAngularSpeed,
      calibrationMaxJitter: calibrationMaxJitter ?? this.calibrationMaxJitter,
      calibrationMaxTiltSpreadDeg:
          calibrationMaxTiltSpreadDeg ?? this.calibrationMaxTiltSpreadDeg,
      calibrationMinSamples:
          calibrationMinSamples ?? this.calibrationMinSamples,
      downwardToleranceDeg: downwardToleranceDeg ?? this.downwardToleranceDeg,
      upwardToleranceDeg: upwardToleranceDeg ?? this.upwardToleranceDeg,
      rotationToleranceDeg: rotationToleranceDeg ?? this.rotationToleranceDeg,
      comfortHysteresisDeg: comfortHysteresisDeg ?? this.comfortHysteresisDeg,
      correctionDwell: correctionDwell ?? this.correctionDwell,
      correctionCooldown: correctionCooldown ?? this.correctionCooldown,
      severeSeverity: severeSeverity ?? this.severeSeverity,
      severeDwellFactor: severeDwellFactor ?? this.severeDwellFactor,
      recoveryDecayFactor: recoveryDecayFactor ?? this.recoveryDecayFactor,
      transientAngularSpeed:
          transientAngularSpeed ?? this.transientAngularSpeed,
      maxSampleGap: maxSampleGap ?? this.maxSampleGap,
      walkingToleranceFactor:
          walkingToleranceFactor ?? this.walkingToleranceFactor,
      pauseInVehicle: pauseInVehicle ?? this.pauseInVehicle,
      breakReminderAfter: breakReminderAfter ?? this.breakReminderAfter,
      autoRecalibrateOnLandscape:
          autoRecalibrateOnLandscape ?? this.autoRecalibrateOnLandscape,
      orientationSettlingDuration:
          orientationSettlingDuration ?? this.orientationSettlingDuration,
      autoCalibrationCooldown:
          autoCalibrationCooldown ?? this.autoCalibrationCooldown,
    );
  }
}
