# PBL Semester 5 — LatihIsyarat

Aplikasi Flutter untuk latihan ejaan jari ASL. Project aktif berada langsung
di root repository `~/Documents/rhma2026/PBL_SEMESTER5`. Repository ini
menggabungkan beranda, navigasi, dan riwayat dari `rhmau1/PBL_SEMESTER5`
dengan kamera, crop tangan, model, dan kamus foto dari project
`PBL-BAHASA-ISYARAT`.

## Menjalankan

```bash
cd ~/Documents/rhma2026/PBL_SEMESTER5
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

Validasi lokal pada 12 Oktober 2026: `flutter analyze` bersih dan
`flutter build apk --debug` berhasil. APK berada di
`build/app/outputs/flutter-apk/app-debug.apk`. Pengujian kamera langsung pada
HP belum dilakukan untuk versi hasil merge.

Status tes otomatis pada 18 Oktober 2026: `flutter analyze` bersih dan
`flutter test` menjalankan 88 kasus dengan 88 lulus, 0 gagal. Sebelum
perbaikan, suite berisi 81 kasus dan 4 di antaranya gagal: tiga tes upload
mencari tombol lama yang sudah diganti tombol `Satu gambar` dan `Banyak
gambar`, dan satu tes tata letak kamera mengharapkan jarak bebas 88 px
sedangkan jarak bebas sebenarnya 84 px (24 px status bar + 8 px celah +
52 px overlay). Setelah keempat tes diperbaiki, 81 kasus lama ditambah 7
kasus baru di `test/session_result_sheet_test.dart` menjadi 88 kasus yang
seluruhnya lulus.

`flutter test` hanya menjalankan `test/`. Folder `integration_test/` memerlukan
HP Android yang terhubung dan tidak ikut dijalankan oleh perintah tersebut.
Workflow CI di `.github/workflows/ci.yml` menjalankan `flutter analyze` dan
`flutter test` pada Ubuntu dengan Flutter 3.47.5.

Kode classifier lama yang tidak digunakan dan laporan build bawaan dibersihkan;
versi sebelumnya tetap tersedia dalam riwayat Git. File model, foto kamus,
source Dart/Android, dokumentasi, dan `pubspec.lock` tersedia untuk tim.
Branch `fijri` melacak `origin/fijri`, dan HEAD saat ini adalah commit merge
`7ea9c5a`. Perubahan setelah merge masih belum di-commit di working tree.

Project Flutter telah dipindahkan dari subfolder `sign_language` ke root
repository agar `flutter run` bisa dijalankan langsung dari root repository.
