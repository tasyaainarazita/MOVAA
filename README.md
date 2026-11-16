# Tugas Checi — Context, Feedback & Background

**Cakupan:** Activity/context → light → feedback → background monitoring

Bagian ini membuat aplikasi lebih peka terhadap konteks pengguna dan mampu
merespons dengan umpan balik, serta tetap bekerja di latar belakang.

## File yang dikerjakan
- `lib/core/posture/activity_estimator.dart` — menaksir aktivitas pengguna
  (diam, berjalan, di kendaraan) sebagai konteks penilaian posisi.
- `lib/core/feedback/haptic_feedback_service.dart` — memberi umpan balik getaran
  lembut sebagai pengingat.
- `lib/core/guidance/posture_guidance.dart` — menyusun kalimat arahan koreksi
  yang mudah dipahami pengguna.
- `lib/core/background/background_posture_service.dart` — menjaga pemantauan
  tetap berjalan saat aplikasi berada di latar belakang (foreground service).

## Catatan tentang "light" (deteksi cahaya)
Deteksi cahaya / low-light **belum diimplementasikan** dalam kode saat ini dan
masih menjadi rencana pengembangan lanjutan. Oleh karena itu belum ada file
untuk bagian tersebut.

## Pengujian
- `test/background_service_test.dart` — menguji layanan pemantauan latar.
- `test/posture_guidance_test.dart` — menguji penyusunan kalimat arahan koreksi.
