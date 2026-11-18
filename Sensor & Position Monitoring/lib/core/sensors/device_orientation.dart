/// Orientasi fisik perangkat, ditentukan dari arah gravitasi pada bidang layar.
///
/// Catatan konvensi sumbu (Android / iOS via sensors_plus):
///   * +X = sisi kanan layar
///   * +Y = sisi atas layar
///   * +Z = keluar dari permukaan layar (menghadap pengguna)
/// Saat diam, accelerometer membaca +9.81 pada sumbu yang mengarah ke ATAS.
enum ScreenOrientation {
  /// Tegak normal, sisi atas layar di atas (gravitasi pada +Y).
  portrait,

  /// Terbalik, sisi atas layar di bawah (gravitasi pada -Y).
  portraitUpsideDown,

  /// Menyamping, sisi kanan layar di atas (gravitasi pada +X).
  landscapeLeft,

  /// Menyamping, sisi kiri layar di atas (gravitasi pada -X).
  landscapeRight,

  /// Perangkat nyaris mendatar, orientasi layar tidak bisa ditentukan.
  flat,

  /// Belum ada data sensor yang valid.
  unknown;

  bool get isPortrait =>
      this == ScreenOrientation.portrait ||
      this == ScreenOrientation.portraitUpsideDown;

  bool get isLandscape =>
      this == ScreenOrientation.landscapeLeft ||
      this == ScreenOrientation.landscapeRight;

  /// True bila orientasi ini benar-benar terbaca (bukan flat / unknown).
  bool get isResolved => isPortrait || isLandscape;

  String get label => switch (this) {
        ScreenOrientation.portrait => 'Portrait',
        ScreenOrientation.portraitUpsideDown => 'Portrait terbalik',
        ScreenOrientation.landscapeLeft => 'Landscape kiri',
        ScreenOrientation.landscapeRight => 'Landscape kanan',
        ScreenOrientation.flat => 'Mendatar',
        ScreenOrientation.unknown => 'Tidak diketahui',
      };
}
