# Panduan Kebutuhan Sistem & Menjalankan Aplikasi

Dokumen ini adalah panduan standarisasi lingkungan pengembangan (*developer environment*) bagi seluruh anggota tim untuk memastikan proses *build*, pengujian (*testing*), dan *running* berjalan konsisten di komputer masing-masing.

---

## 1. Spesifikasi Lingkungan Pengembangan

Pastikan setiap anggota tim menggunakan versi *toolchain* yang seragam berikut:

| Komponen | Versi Terkunci | Keterangan |
| :--- | :--- | :--- |
| **Flutter SDK** | `3.47.5 stable` | Framework utama UI & logika aplikasi |
| **Dart SDK** | `3.13.4+` | Bahasa pemrograman (termasuk di dalam Flutter) |
| **Java Development Kit (JDK)** | `JDK 17 LTS` | **Wajib JDK 17** untuk kompatibilitas Gradle & Android build |
| **Android SDK Platform** | `API 36` (Android 15) | Target SDK Android |
| **Android Build Tools** | `36.0.0` | Tool kompilasi Android |
| **Android NDK** | `28.2.13676358` | Kompilasi library native (MediaPipe / C++) |
| **Gradle** | `9.3.1` | Build automation tool (dikelola via Gradle Wrapper) |
| **Android Gradle Plugin (AGP)** | `9.1.0` | Plugin Gradle untuk Android |
| **Kotlin Plugin** | `2.4.0` | Native Android Kotlin runtime |
| **Perangkat Uji Minimum** | `Android 7.0 (API 24)` | Dukungan minimum OS ponsel pintar pengguna |

---

## 2. Instalasi & Konfigurasi Komputer

### A. Untuk Pengguna Linux / macOS
1. **Verifikasi Flutter & Dart**:
   ```bash
   flutter --version
   ```
2. **Arahkan Flutter ke JDK 17**:
   ```bash
   export JAVA_HOME=/path/ke/jdk-17
   flutter config --jdk-dir="$JAVA_HOME"
   ```
3. **Konfirmasi Lisensi Android**:
   ```bash
   flutter doctor --android-licenses
   flutter doctor -v
   ```
   *Pastikan pada bagian "Android toolchain", baris `Java binary at:` menunjuk ke direktori JDK 17.*

### B. Untuk Pengguna Windows
1. Pasang OpenJDK 17 (misal via winget):
   ```powershell
   winget install --id Microsoft.OpenJDK.17 -e
   ```
2. Arahkan Flutter ke direktori JDK 17:
   ```powershell
   flutter config --jdk-dir="C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot"
   ```
3. Periksa status lingkungan:
   ```powershell
   flutter doctor -v
   ```

---

## 3. Mengambil Project & Dependensi

1. **Clone Repository**:
   ```bash
   git clone https://github.com/rhmau1/PBL_SEMESTER5.git
   cd PBL_SEMESTER5
   ```

2. **Pasang Paket Dependensi**:
   ```bash
   flutter pub get
   ```
   > [!IMPORTANT]
   > Simpan selalu berkas `pubspec.lock` di dalam Git dan jangan menjalankan `flutter pub upgrade` tanpa koordinasi bersama tim agar versi package antar komputer anggota tetap identik.

### Daftar Dependensi Aktif & Fungsinya

| Package | Versi Terkunci | Fungsi / Peruntukan |
| :--- | :--- | :--- |
| `camera` | `^0.12.1` | Kontroler kamera, capture foto, dan streaming frame luma |
| `camera_android_camerax` | `0.7.4+7` | Backend CameraX Android untuk bridge preview |
| `camera_platform_interface` | `^2.13.1` | Antarmuka abstraksi backend kamera |
| `hand_landmarker` | `^3.1.0` | Deteksi real-time 21 landmark titik tangan MediaPipe |
| `image` | `4.9.2` | Decode JPEG/PNG, koreksi rotasi EXIF, crop, dan grayscale |
| `image_picker` | `^1.2.3` | Pemilih gambar galeri (single & multi-image) |
| `path_provider` | `^2.1.6` | Akses direktori penyimpanan lokal perangkat |
| `sqflite` | `^2.4.2` | Database lokal SQLite untuk riwayat deteksi latihan |
| `path` | `^1.9.1` | Manipulasi dan penggabungan path file lokal |
| `flutter_riverpod` | `^2.6.1` | Manajemen state terpusat (History & Gamifikasi) |
| `flutter_svg` | `^2.3.2` | Rendering aset vektor SVG (lencana & maskot) |
| `shared_preferences` | `^2.5.6` | Penyimpanan status lokal sederhana (flag Onboarding) |

---

## 4. Menjalankan Aplikasi di Perangkat Android

1. Aktifkan **Developer Options** dan **USB Debugging** pada ponsel Android Anda.
2. Sambungkan ponsel ke komputer dengan kabel data USB, lalu izinkan dialog otorisasi RSA yang muncul di layar ponsel.
3. Periksa koneksi perangkat:
   ```bash
   flutter devices
   ```
4. Jalankan aplikasi dengan menyertakan API Key Gemini untuk mengaktifkan fitur autocorrect kalimat berbasis AI:
   ```bash
   flutter run --dart-define=GEMINI_API_KEY=API_KEY_GEMINI_ANDA
   ```
   *Jika terdapat lebih dari satu perangkat yang terhubung, gunakan flag `-d ID_DEVICE`:*
   ```bash
   flutter run -d <ID_DEVICE> --dart-define=GEMINI_API_KEY=API_KEY_GEMINI_ANDA
   ```

---

## 5. Pengujian Kualitas Kode (Quality Assurance)

Sebelum melakukan *commit* atau *push*, pastikan semua pengujian lolos:

1. **Pemeriksaan Analisis Kode (Linter)**:
   ```bash
   flutter analyze
   ```
2. **Menjalankan Unit Test & Widget Test**:
   ```bash
   flutter test
   ```
3. **Menjalankan Pengujian Integrasi Fisik (E2E Integration Test)**:
   *Memerlukan ponsel Android fisik yang tersambung melalui USB Debugging:*
   ```bash
   flutter test integration_test/ui_journey_physical_test.dart
   ```

---

## 6. Build File APK

1. **Build APK Debug**:
   ```bash
   flutter build apk --debug
   ```
   *Lokasi output:* `build/app/outputs/flutter-apk/app-debug.apk`

2. **Build APK Release (Optimasi per Arsitektur CPU)**:
   ```bash
   flutter build apk --release --split-per-abi
   ```
   *Lokasi output untuk HP modern (64-bit):* `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`

---

## 7. Solusi Masalah Umum (Troubleshooting)

* **IDE / Editor Menampilkan Teks Merah**:
  Jalankan `flutter pub get`, lalu restart editor (atau *Restart Dart Analysis Server*).
* **Perangkat Berstatus `unauthorized`**:
  Cabut kabel data, pasang kembali, lalu klik **Izinkan / Allow** pada kotak dialog RSA di layar ponsel.
* **Error Versi JVM / Gradle Build Gagal**:
  Jalankan `flutter doctor -v` dan periksa path Java. Pastikan menggunakan JDK 17, bukan JDK 21 atau JDK 8.
* **Kamera Terbalik atau Distorsi Preview**:
  Native bridge memerlukan restart penuh jika kode Java/Kotlin diubah. Hentikan aplikasi secara total (`q`), lalu jalankan ulang dengan `flutter run`.
