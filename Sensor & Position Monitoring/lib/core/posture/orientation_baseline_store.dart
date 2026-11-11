import '../sensors/device_orientation.dart';
import 'posture_baseline.dart';

/// Penyimpanan baseline kalibrasi personal terpisah untuk orientasi
/// portrait dan landscape.
///
/// Memastikan pengguna memiliki acuan postur yang akurat baik saat memegang
/// ponsel tegak (portrait) maupun menyamping (landscape), dengan fallback
/// otomatis jika salah satu orientasi belum dikalibrasi.
class OrientationBaselineStore {
  OrientationBaselineStore({
    this.portrait,
    this.landscape,
  });

  PostureBaseline? portrait;
  PostureBaseline? landscape;

  /// Mengambil baseline yang paling sesuai untuk [orientation].
  ///
  /// Bila orientasi spesifik belum dikalibrasi, sistem otomatis menggunakan
  /// orientasi lain yang tersedia sebagai fallback agar monitoring tetap berjalan.
  PostureBaseline? get(ScreenOrientation orientation) {
    if (orientation.isLandscape) {
      return landscape ?? portrait;
    }
    if (orientation.isPortrait) {
      return portrait ?? landscape;
    }
    return portrait ?? landscape;
  }

  /// Menyimpan baseline ke slot yang tepat sesuai [PostureBaseline.orientation].
  void set(PostureBaseline baseline) {
    if (baseline.orientation.isLandscape) {
      landscape = baseline;
    } else {
      portrait = baseline;
    }
  }

  /// True bila sudah ada setidaknya satu baseline yang tersimpan.
  bool get hasAny => portrait != null || landscape != null;

  /// True bila orientasi spesifik sudah memiliki baseline sendiri.
  bool hasFor(ScreenOrientation orientation) {
    if (orientation.isLandscape) return landscape != null;
    if (orientation.isPortrait) return portrait != null;
    return hasAny;
  }

  /// Menghapus baseline. Bila [orientation] tidak diberikan, hapus keduanya.
  void clear({ScreenOrientation? orientation}) {
    if (orientation == null) {
      portrait = null;
      landscape = null;
    } else if (orientation.isLandscape) {
      landscape = null;
    } else {
      portrait = null;
    }
  }

  Map<String, dynamic> toJson() => {
        'portrait': portrait?.toJson(),
        'landscape': landscape?.toJson(),
      };

  /// Mendukung parsing format multi-baseline baru dan tetap kompatibel
  /// dengan format JSON single [PostureBaseline] lama.
  factory OrientationBaselineStore.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('portrait') || json.containsKey('landscape')) {
      return OrientationBaselineStore(
        portrait: json['portrait'] != null
            ? PostureBaseline.fromJson(json['portrait'] as Map<String, dynamic>)
            : null,
        landscape: json['landscape'] != null
            ? PostureBaseline.fromJson(json['landscape'] as Map<String, dynamic>)
            : null,
      );
    }

    // Kompatibilitas ke belakang untuk data JSON baseline tunggal lama.
    final single = PostureBaseline.fromJson(json);
    final store = OrientationBaselineStore();
    store.set(single);
    return store;
  }
}
