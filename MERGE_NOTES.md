# PBL Semester 5 — LatihIsyarat

Aplikasi Flutter untuk latihan ejaan jari ASL. Project aktif berada langsung
di root repository `D:\PBL_SEMESTER5`. Repository ini menggabungkan beranda,
navigasi, dan riwayat dari `rhmau1/PBL_SEMESTER5` dengan kamera, crop tangan,
model, dan kamus foto dari project `PBL-BAHASA-ISYARAT`.

## Menjalankan

```powershell
cd D:\PBL_SEMESTER5
flutter pub get
flutter devices
flutter run
```

Gunakan HP Android nyata untuk pengujian kamera. Flutter, JDK 17, dan Android
SDK dipasang di komputer, di luar repository. Remote `origin` adalah
`https://github.com/rhmau1/PBL_SEMESTER5.git`.

## Dokumentasi tim

- [Fitur, alur deteksi, dan kontrak model](README.md)
- [Kebutuhan software, versi dependency, dan cara menjalankan](REQUIREMENTS.md)
- [Panduan validasi kamera dan fitur pada HP](CAMERA_VALIDATION.md)

Model yang dipakai tetap model ensemble float16 berukuran 5,268 MiB dengan
hasil eksperimen dataset 99,30%. Angka tersebut bukan akurasi kamera nyata.
Pengujian langsung pada HP diperlukan setelah perubahan integrasi.

## Validasi hasil merge

Validasi lokal pada 12 Oktober 2026: `flutter analyze` bersih, seluruh
81 tes otomatis lulus, dan `flutter build apk --debug` berhasil.
APK berada di `build/app/outputs/flutter-apk/app-debug.apk`.
Pengujian kamera langsung pada HP belum dilakukan untuk versi hasil merge.

Kode classifier lama yang tidak digunakan dan laporan build bawaan dibersihkan;
versi sebelumnya tetap tersedia dalam riwayat Git. File model, foto kamus,
source Dart/Android, dokumentasi, dan `pubspec.lock` tersedia untuk tim.
Perubahan merge masih lokal dan belum di-push ke GitHub.

Project Flutter telah dipindahkan dari subfolder `sign_language` ke root
repository agar `flutter run` bisa dijalankan langsung dari `D:\PBL_SEMESTER5`.
