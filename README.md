# LatihIsyarat: Smart Sign Language Learning & Recognition

Aplikasi mobile cerdas berbasis Flutter untuk pembelajaran dan pengenalan alfabet bahasa isyarat statis (24 kelas: A–Y, tanpa J dan Z) secara *real-time* langsung di perangkat (*on-device*). Sistem memadukan model Machine Learning **Hybrid RBF SVM (HOG + LBP + Hu Moments + Kontur + MediaPipe Hand Landmarks)**, pengolahan citra komputer adaptif, dan asistensi **Generative AI (Gemini 3.5 Flash Lite)** untuk koreksi otomatis (*autocorrect*) serta pemisahan spasi kalimat.

Proyek ini dikembangkan sebagai luaran Project-Based Learning (PBL) Semester 5 yang mengintegrasikan 4 mata kuliah inti program studi Teknik Informatika.

---

## Anggota Tim Pengembang

| No | Nama Lengkap | NIM | Username GitHub |
| :---: | :--- | :---: | :--- |
| 1 | Fijriati Rahmatur Rizqi | 244107020069 | [@rhmau1](https://github.com/rhmau1) |
| 2 | Mohammad Ariq Baihaqi | 244107020161 | [@Ariqq16](https://github.com/Ariqq16) |
| 3 | Raymon Devtant | 2441020009 | [@CresentCrysy](https://github.com/CresentCrysy) |
| 4 | Sahrul Ramadhani | 244107020058 | [@SahrulRamadhani29](https://github.com/SahrulRamadhani29) |
| 5 | Silva Tria Alfares | 254107023001 | [@silvatria](https://github.com/silvatria) |

---

## Integrasi 4 Mata Kuliah

Aplikasi ini dibangun dengan mengimplementasikan capaian pembelajaran dari empat bidang kompetensi utama:

```
                                  +---------------------------------------+
                                  |             LatihIsyarat              |
                                  +---------------------------------------+
                                                      |
         +--------------------+-----------------------+-----------------------+--------------------+
         |                    |                                               |                    |
         v                    v                                               v                    v
+-----------------+  +------------------+                           +-----------------+  +-----------------+
| 1. Pemrograman  |  | 2. Pembelajaran  |                           | 3. Pengolahan   |  | 4. Penjaminan   |
|     Bergerak    |  |      Mesin       |                           |  Citra & Visi   |  |  Mutu Perangkat |
|     (Mobile)    |  |       (ML)       |                           | Komputer (PCVK) |  |   Lunak (PMPL)  |
+-----------------+  +------------------+                           +-----------------+  +-----------------+
| - Clean Arch    |  | - Hybrid RBF SVM |                           | - Preprocessing |  | - Unit & Widget |
| - Riverpod      |  | - One-vs-One     |                           |   Bilinear/Otsu |   |   Testing (Dart)|
| - SQLite DB     |  | - Dart Isolate   |                           | - HOG (1764)    |  | - Espresso Test |
| - Native Camera |  | - LLM Gemini 3.5 |                           | - LBP & Hu (51) |  | - E2E Physical  |
| - Gamification  |  |   Autocorrect    |                           | - MediaPipe 21  |  | - GitHub Action |
+-----------------+  +------------------+                           +-----------------+  +-----------------+
```

### 1. Pemrograman Bergerak (Mobile Programming)
* **Arsitektur Aplikasi Bersih & Modular**: Dibangun menggunakan framework Flutter dengan pemisahan tanggung jawab yang jelas antara lapisan tampilan (`pages/`, `screens/`), logika bisnis (`services/`), penyimpanan (`models/`, `database_helper.dart`), dan komponen antarmuka reusable (`widgets/`).
* **State Management Reaktif**: Menggunakan **Flutter Riverpod** (`flutter_riverpod`) untuk mengelola state riwayat deteksi (`historyProvider`) dan progres gamifikasi secara terpusat tanpa *boilerplate* berlebih.
* **Penyimpanan Lokal (Persistence)**: Menggunakan **SQLite** (`sqflite`) untuk menyimpan seluruh riwayat deteksi latihan (gestur, tingkat keyakinan, waktu, tanggal, media gambar, dan rekaman video) dengan skema database yang mendukung migrasi versi.
* **Native CameraX Preview Bridge**: Mengatasi masalah umum preview kamera terdistorsi atau terpotong pada Android dengan mengimplementasikan jembatan native [`LatihIsyaratPreviewBridge.java`](android/app/src/main/java/io/flutter/plugins/camerax/LatihIsyaratPreviewBridge.java) dan [`LatihIsyaratPreviewGeometry.java`](android/app/src/main/java/androidx/camera/core/LatihIsyaratPreviewGeometry.java). Jembatan ini membaca transformasi geometri CameraX agar preview di Flutter tampil *upright full-bleed* 100% presisi.
* **Pengalaman Pengguna (UX/UI) Modern**:
  * Tampilan Onboarding 4 langkah interaktif untuk pengguna baru.
  * Dukungan tema terang dan gelap (*Dark/Light Mode*) yang konsisten.
  * Sistem Gamifikasi: Perhitungan akumulasi poin XP, pelacak streak latihan harian, dan 5 tingkatan lencana (*badges*): *Keep Learning, Good, Excellent, Perfect,* hingga *Impossible*.
  * Tiga Mode Akses Deteksi Fleksibel: Mode **Video** (live stream kontinu), Mode **Foto** (jepret instan), dan Mode **Upload** (pilihan satu atau banyak gambar dari galeri).

### 2. Pembelajaran Mesin (Machine Learning)
* **Model Klasifikasi On-Device**: Menggunakan algoritma **Support Vector Machine (SVM)** dengan **Kernel Radial Basis Function (RBF)** multi-kelas (*One-vs-One decision function*) yang mendukung 24 alfabet isyarat statis.
* **Optimasi Hyperparameter**: Model dilatih melalui *GridSearchCV* menggunakan hyperparameter optimal ($C = 100$ dan $\gamma = \text{scale}$) serta normalisasi fitur menggunakan *StandardScaler*.
* **Eksekusi Asinkron via Dart Isolate**: Mengingat komputasi kernel RBF pada ruang fitur 1867-dimensi cukup intensif, model biner terkompresi (`assets/models/svm_hog.bin.gz`) dimuat dan dieksekusi di dalam thread background terisolasi (`Isolate.spawn`) di [`svm_hog_classifier.dart`](lib/services/svm_hog_classifier.dart). Hal ini menjamin antarmuka pengguna tetap berjalan mulus pada 60 FPS tanpa terjadi *frame drop* (*jank*).
* **Asistensi Generative AI (LLM Autocorrect & Word Segmenter)**:
  * Mengintegrasikan API **Google Gemini 3.5 Flash Lite** (`gemini-3.5-flash-lite`) pada [`llm_autocorrect_service.dart`](lib/services/llm_autocorrect_service.dart) dengan latency rendah (timeout 4 detik).
  * Dilengkapi *System Prompt Guardrails* dan **Sign Language Confusion Map** (pemetaan kemiripan bentuk isyarat: `M <-> N <-> E <-> S <-> A <-> T`, `U <-> V <-> R <-> K`, `B <-> W <-> F`, `C <-> O`, dll.).
  * LLM bertugas memecah aliran huruf tanpa spasi hasil deteksi kontinu video (contoh: `"SAYAMAKANBAYAE"`) menjadi kata-kata bermakna sesuai KBBI dengan pemisahan spasi yang tepat (`"SAYA MAKAN BAYAM"`).

### 3. Pengolahan Citra dan Visi Komputer (PCVK)
* **Pipeline Preprocessing Citra Adaptif**:
  * **Koreksi Rotasi & Ekstraksi Luma**: Penanganan orientasi EXIF pada gambar file dan ekstraksi bidang Y (luminansi) pada buffer kamera real-time.
  * **Bilinear Lighting Flattening**: Algoritma perataan pencahayaan adaptif untuk mengatasi bayangan keras atau pencahayaan ruangan yang tidak merata sebelum segmentasi.
  * **Otsu Adaptive Thresholding & Operasi Morfologi**: Penerapan *morphological opening* dan *closing* (kombinasi erosi dan dilatasi) untuk membersihkan noise latar belakang dan menutup lubang pada masker tangan.
  * **Connected-Component Labeling**: Pelacakan kontur terbesar untuk menentukan *bounding box* tangan secara akurat dan membuang artefak latar belakang yang tidak relevan.
* **Ekstraksi Fitur Multimodal Hybrid (Total 1867 Dimensi)**:
  1. **HOG (Histogram of Oriented Gradients)**: 1764 fitur (jendela 64×64, 9 bin orientasi, ukuran sel 8×8, blok 2×2, normalisasi L2-Hys) untuk menangkap tepi dan gradien bentuk tangan.
  2. **LBP (Local Binary Patterns)**: 40 fitur pola biner seragam (*uniform LBP 2×2*) untuk merepresentasikan tekstur permukaan kulit dan lipatan jari.
  3. **Hu Moments**: 7 invariant moments yang tahan terhadap perubahan skala, translasi, dan rotasi bentuk siluet tangan.
  4. **Contour Geometry Descriptors**: 4 rasio geometris kontur (luas area, keliling, *aspect ratio*, dan *solidity*).
  5. **MediaPipe Hand Landmarks**: 52 fitur spasial yang diekstraksi dari 21 titik koordinat persendian tangan (jarak antarsendi yang dinormalisasi dan sudut jari).
* **Dual Landmark Detection System**:
  * **Mode Video Real-Time**: Integrasi plugin `hand_landmarker` untuk streaming landmark per-frame yang distabilkan dengan filter temporal [`StableSign`](lib/services/stable_sign.dart) (konsensus 3 dari 4 frame berurutan).
  * **Mode Foto & Upload**: Integrasi MediaPipe Tasks Vision native Android via [`StillImageHandLandmarker.kt`](android/app/src/main/kotlin/com/example/sign_language/StillImageHandLandmarker.kt) dengan verifikasi konsensus *dual-crop* (*tight* vs *wide*).

### 4. Penjaminan Mutu Perangkat Lunak (PMPL)
* **Piramida Pengujian Komprehensif**:
  * **Unit Testing**: Memvalidasi integritas matematika model SVM (`test/svm_hog_model_test.dart`), parsing input dan normalisasi citra (`test/svm_hog_input_test.dart`), algoritma penstabil deteksi (`test/stable_sign_test.dart`), logika gamifikasi dan perhitungan streak (`test/gamification_test.dart`), serta operasi CRUD database SQLite (`test/history_provider_test.dart`).
  * **Widget Testing**: Pengujian interaksi komponen antarmuka pengguna pada seluruh layar utama (`test/camera_modes_test.dart`, `test/upload_screen_test.dart`, `test/onboarding_screen_test.dart`, `test/guide_page_test.dart`, `test/history_page_test.dart`, dan layout preview kamera).
  * **Native Android Espresso Testing**: Pengujian lapisan native Android Activity lifecycle dan interaksi surface Flutter engine (`android/app/src/androidTest/.../MainActivityEspressoTest.kt`).
  * **End-to-End Physical Device Integration Testing**: Pengujian otomatis alur perjalanan pengguna secara menyeluruh pada perangkat fisik nyata Android menggunakan Flutter `integration_test` ([`integration_test/ui_journey_physical_test.dart`](integration_test/ui_journey_physical_test.dart)) yang mencakup 10 skenario alur tanpa henti:
    `Splash` -> `Onboarding (4 langkah)` -> `Home` -> `Deteksi Video` -> `Deteksi Foto` -> `Deteksi Upload` -> `Kamus Isyarat` -> `Riwayat` -> `Progres Belajar & Badges` -> `Panduan Penggunaan`.
* **Continuous Integration (CI)**: Pipeline otomatisasi pengujian menggunakan GitHub Actions ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) yang secara ketat menjalankan `flutter pub get`, `flutter analyze` (pemeriksaan linting kode), dan `flutter test` pada setiap aktivitas *push* dan *pull request*.

---

## Struktur Direktori Proyek

```text
.
├── android/                  # Konfigurasi native Android, Gradle, CameraX Bridge & MediaPipe Native
├── assets/
│   ├── badges/               # Aset SVG untuk lencana gamifikasi
│   ├── logo/                 # Maskot dan logo aplikasi
│   ├── models/               # Model biner terkompresi svm_hog.bin.gz (Hybrid 1867-dim)
│   └── signs/                # Gambar referensi visual 24 alfabet isyarat
├── docs/                     # Dokumentasi teknis, arsitektur, dan laporan eksperimen
├── integration_test/         # Pengujian integrasi E2E pada perangkat fisik nyata
├── lib/
│   ├── models/               # Data model (HistoryItem, BadgeItem, GamificationProgress, dll.)
│   ├── pages/                # Halaman utama (HomePage, DetectionPage, DictionaryPage, HistoryPage)
│   ├── providers/            # State management Riverpod (HistoryProvider, GamificationProvider)
│   ├── screens/              # Layar tampilan spesifik (CameraScreen, UploadScreen, Splash, Onboarding)
│   ├── services/             # Backend logic (SvmHogClassifier, LlmAutocorrectService, DatabaseHelper)
│   ├── widgets/              # Komponen widget modular & reusable
│   └── main.dart             # Titik masuk utama aplikasi (Entrypoint)
├── test/                     # Kumpulan Unit Test dan Widget Test
├── tooling/                  # Skrip bantu konversi model dan pengujian kualitas citra
├── training/                 # Notebook Google Colab training model Hybrid SVM 1867-dim
├── pubspec.yaml              # Konfigurasi dependensi dan aset Flutter
└── README.md                 # Dokumentasi utama proyek
```

---

## Kebutuhan Sistem & Spesifikasi Lingkungan

Untuk menjalankan dan membangun aplikasi dengan konsisten:

| Komponen | Spesifikasi Rekomendasi |
| :--- | :--- |
| **Flutter SDK** | 3.47.5 stable (Dart 3.13.4+) |
| **Java Development Kit (JDK)** | JDK 17 LTS |
| **Android SDK** | Platform API 36, Build Tools 36.0.0 |
| **Android NDK** | 28.2.13676358 |
| **Gradle** | 9.3.1 (Android Gradle Plugin 9.1.0, Kotlin 2.4.0) |
| **Target Perangkat Fisik** | Android 7.0 (API 24) ke atas |

---

## Cara Menjalankan Aplikasi

1. **Clone Repository**:
   ```bash
   git clone https://github.com/rhmau1/PBL_SEMESTER5.git
   cd PBL_SEMESTER5
   ```

2. **Pasang Dependensi**:
   ```bash
   flutter pub get
   ```

3. **Verifikasi Lingkungan dan Kode**:
   ```bash
   flutter analyze
   flutter test
   ```

4. **Jalankan Aplikasi di Perangkat Android**:
   Aktifkan *Developer Options* dan *USB Debugging* pada ponsel pintar Android Anda, sambungkan via kabel USB, lalu jalankan perintah berikut (sertakan API Key Gemini untuk mengaktifkan fitur autocorrect AI):
   ```bash
   flutter run --dart-define=GEMINI_API_KEY=API_KEY_GEMINI_ANDA
   ```

5. **Menjalankan Pengujian Integrasi Fisik**:
   ```bash
   flutter test integration_test/ui_journey_physical_test.dart
   ```
