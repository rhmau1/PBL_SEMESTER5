# Kebutuhan tim dan cara menjalankan

Pasang Flutter SDK, JDK, dan Android SDK di komputer masing-masing, di luar
folder project. Tidak perlu menyimpan SDK, cache dependency, atau APK di Git.

## Lingkungan project

| Komponen | Versi |
| --- | --- |
| Flutter | 3.47.2 stable |
| Dart | 3.13.2, termasuk Flutter |
| JDK | 17 LTS; komputer pengembangan menggunakan Microsoft OpenJDK 17.0.20 |
| Android SDK | Platform API 36 dan Build Tools 36.0.0 |
| Android NDK | 28.2.13676358, mengikuti Flutter |
| Gradle | 9.3.1 |
| Android Gradle Plugin | 9.1.0 |
| Kotlin plugin | 2.4.0 |
| Minimum HP | Android 7.0 / API 24 |

Gunakan versi Flutter yang sama untuk hasil build yang konsisten. Project
ditujukan untuk Android; kamera dan MediaPipe perlu diuji di HP nyata.

## Instalasi

1. Instal Git dan Flutter 3.47.2. Contoh lokasi SDK: `C:\src\flutter`.
   Tambahkan `C:\src\flutter\bin` ke `Path`.
2. Instal JDK 17. Di Windows, pilihan instalasi:

   ```powershell
   winget install --id Microsoft.OpenJDK.17 -e
   ```

3. Arahkan Flutter ke JDK yang terpasang. Sesuaikan folder dengan komputer:

   ```powershell
   Get-ChildItem "C:\Program Files\Microsoft" -Directory | Where-Object Name -Like "jdk-17*"
   flutter config --jdk-dir="C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot"
   ```

4. Instal Android Studio, lalu buka SDK Manager. Pasang Android SDK Platform
   36, Build Tools 36.0.0, Platform-Tools, Command-line Tools, dan NDK versi
   yang tercantum di atas. Gradle dan library Android diunduh ketika build.
5. Terima lisensi dan periksa lingkungan:

   ```powershell
   flutter doctor --android-licenses
   flutter --version
   flutter doctor -v
   ```

`Java binary` pada Android toolchain harus menunjuk ke JDK 17. JDK 25 boleh
tetap terpasang untuk project lain; jangan gunakan untuk build project ini.
Jika memakai VS Code, instal extension Flutter dan Dart.

## Mengambil project dan dependency

Untuk komputer anggota tim yang belum memiliki repository:

```powershell
git clone https://github.com/rhmau1/PBL_SEMESTER5.git D:\PBL_SEMESTER5
cd D:\PBL_SEMESTER5
flutter pub get
```

Untuk repository yang sudah ada, ambil perubahan tim melalui Git lalu
jalankan `flutter pub get` dari root repository `D:\PBL_SEMESTER5`. Simpan
`pubspec.lock` dalam Git dan jangan menjalankan `flutter pub upgrade` tanpa
menyamakan versi bersama tim.

Versi berikut berasal dari `pubspec.lock` hasil merge:

| Dependency | Versi terkunci | Fungsi |
| --- | --- | --- |
| camera | 0.12.1 | Preview, stream frame, foto, rekaman |
| camera_android_camerax | 0.7.4+7 | Backend Android; dikunci untuk bridge preview |
| camera_platform_interface | 2.14.0 | Antarmuka backend kamera |
| AndroidX camera-core | 1.6.1 | Transformasi native preview; dikelola Gradle |
| hand_landmarker | 3.1.0 | MediaPipe untuk mendeteksi tangan pada frame |
| tflite_flutter | 0.12.1 | Menjalankan model lokal |
| image | 4.9.2 | EXIF, crop, resize, grayscale |
| image_picker | 1.2.4 | Memilih gambar dari galeri |
| path_provider | 2.1.6 | Direktori penyimpanan internal |
| sqflite | 2.4.4+1 | Riwayat SQLite |
| path | 1.9.1 | Menggabungkan path file |
| shared_preferences | 2.5.6 | Pengaturan lokal |
| flutter_riverpod | 2.6.1 | State aplikasi dan riwayat |

Package tidak perlu diinstal satu per satu. `flutter pub get` memasang
dependency termasuk model Hand Landmarker yang dibundel oleh plugin.

## USB dan menjalankan di HP

Aktifkan Developer options dan USB debugging pada HP, sambungkan dengan kabel
data, lalu izinkan dialog RSA komputer. Periksa perangkat:

```powershell
cd D:\PBL_SEMESTER5
flutter devices
flutter run
```

Jika beberapa perangkat terhubung, gunakan ID dari `flutter devices`:

```powershell
flutter run -d ID_PERANGKAT
```

Contoh Vivo pengembangan: `flutter run -d 33a40574`. ID tersebut hanya milik
HP itu; anggota tim menggunakan ID HP masing-masing. Status `unauthorized`
berarti dialog izin USB pada HP belum disetujui.

Build pertama memerlukan unduhan dan kompilasi library native. Jangan cabut
USB sebelum instalasi selesai. Saat proses run aktif, `r` melakukan hot reload,
`R` hot restart, dan `q` menghentikan proses. Perubahan Android, dependency,
atau asset model membutuhkan stop lalu run kembali.

## Pemeriksaan dan APK manual

```powershell
flutter analyze
flutter test
```

Untuk membuat APK setelah siap menguji:

```powershell
flutter build apk --debug
```

Hasil: `build\app\outputs\flutter-apk\app-debug.apk`. APK dapat diinstal dan
dibuka di Android tanpa USB setelah instalasi. Untuk release per arsitektur:

```powershell
flutter build apk --release --split-per-abi
```

HP arm64 memakai `app-arm64-v8a-release.apk`. Signing release saat ini masih
debug key; siapkan signing produksi sebelum distribusi resmi.

## Masalah umum

- Kode merah: jalankan `flutter pub get`, lalu restart Dart Analysis Server
  atau muat ulang editor. Buka folder `D:\PBL_SEMESTER5` sebagai project Flutter.
- HP tidak terlihat: periksa kabel data, izin RSA, USB debugging, dan driver.
  Jalankan `adb devices` untuk membedakan `unauthorized` dan perangkat offline.
- Error JVM: periksa JDK melalui `flutter doctor -v`; samakan ke 17.
- Warning SDK XML: versi tool Android pembaca metadata tertinggal. Samakan
  instalasi Android Studio/Command-line Tools; warning ini tidak menjelaskan
  rotasi atau rasio preview kamera.
- Kamera tertukar setelah update: hentikan aplikasi dan jalankan ulang dari
  source terbaru. Hot reload tidak mengganti native preview bridge. Catat
  model HP dan tahap terjadinya masalah untuk validasi.

Jangan mengirim `build`, `.dart_tool`, `android/local.properties`, SDK, atau
JDK ke Git. Model TFLite, labels, metadata, referensi landmark, foto kamus,
source native bridge, dan `pubspec.lock` harus tetap tersedia untuk tim.
