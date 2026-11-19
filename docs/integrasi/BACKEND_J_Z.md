# Integrasi frontend dengan backend J/Z

Backend berjalan di Android secara offline. Tidak ada URL server atau endpoint HTTP. Frontend memanggil layanan Dart di bawah. Channel Android dipakai oleh layanan tersebut untuk menjalankan MediaPipe.

## Yang sudah tersedia

- Model GRU J/Z/OTHER, berukuran 229.672 byte, di `assets/models/jz/`.
- Detektor MediaPipe VIDEO terpisah dengan landmark XYZ dan waktu setiap frame.
- Konversi frame kamera, sampling maksimal 15 fps, preprocessing `48 × 64`, dan inferensi TFLite di isolate.
- Penanganan hasil, frame tidak valid, sesi batal, dan pelepasan resource.

Halaman kamera sudah memanggil layanan ini untuk target J/Z dan potongan gerakan dalam latihan bebas. Petunjuk penggunaan ada di [integrasi frontend](FRONTEND_J_Z.md). CNN tetap memiliki 24 output dengan konfigurasi yang sama.

## API yang dipanggil frontend

Import `package:sign_language/services/jz_recognition_service.dart` dan `package:sign_language/models/jz_clip_result.dart`.

| Method | Input | Hasil |
| --- | --- | --- |
| `JzRecognitionService()` | Tanpa argumen untuk penggunaan normal | Satu instance layanan |
| `startClip()` | Tidak ada | `Future<void>`, menyiapkan model dan tracker baru |
| `addCameraFrame(image, timestampMs: ..., rotationDegrees: ...)` | `CameraImage`, waktu akuisisi monoton, rotasi buffer agar tegak | `Future<JzFrameReceipt>` |
| `addJpegFrame(bytes, timestampMs: ...)` | JPEG dari frame video yang sudah tegak, tanpa mirror, sisi maksimal 640 px | `Future<JzFrameReceipt>` |
| `finishClip()` | Tidak ada | `Future<JzClipResult>`, satu keputusan untuk satu gerakan |
| `cancelClip()` | Tidak ada | `Future<void>`, membuang sesi tanpa menghasilkan huruf |
| `dispose()` | Tidak ada | `Future<void>`, membatalkan sesi dan menutup model milik instance |

Gunakan satu layanan aktif untuk J/Z per engine Flutter. `startClip()` boleh dipanggil lagi setelah `finishClip()` atau `cancelClip()`. Setelah `dispose()`, buat instance baru.

`state` menunjukkan `idle`, `starting`, `capturing`, `finishing`, atau `disposed`. `sampledFrames` adalah jumlah observasi yang sudah selesai diproses pada clip aktif.

Untuk receipt berstatus `sampled`, `handDetected` melaporkan keberadaan tangan pada observasi baru tersebut. Frame yang dilewati memiliki `handDetected: null`, sehingga frontend tidak boleh menganggapnya sebagai deteksi tangan baru.

## Aturan pengiriman frame

1. Satu clip harus berisi **satu gerakan J atau Z yang lengkap**, dari awal hingga akhir. Jangan mengirim satu foto berulang atau satu video panjang berisi banyak huruf sebagai satu gerakan.
2. Tunggu `startClip()` selesai, lalu teruskan callback frame kamera. Catat waktu saat callback diterima, sebelum konversi atau deteksi. Gunakan satu `Stopwatch` selama clip. Jangan memakai waktu selesainya inferensi.
3. `rotationDegrees` adalah rotasi yang membuat buffer kamera tegak, yaitu 0, 90, 180, atau 270. Jangan menambahkan mirror untuk kamera depan. Preview yang tampak seperti cermin tidak mengubah input model.
4. Layanan memilih frame baru maksimal 15 fps. Jika proses sebelumnya belum selesai, frame baru dilewati. Jangan mengulang landmark atau frame lama untuk mengejar jumlah sampel.
5. `JzFrameReceipt.status` bernilai `sampled`, `skippedBusy`, atau `skippedInterval`. Status dilewati adalah mekanisme pengaturan beban. Pantau `quality.actual_sample_fps` pada hasil karena 15 fps bukan jaminan kecepatan HP.
6. Saat berganti kamera, orientasi, pindah halaman, atau aplikasi masuk background, batalkan clip. Mulai clip baru setelah kamera siap. Jangan menggabungkan sumber JPEG dan kamera dengan orientasi yang berbeda.

Clip harus berdurasi sedikitnya 0,25 detik dengan minimal 6 observasi tangan dan proporsi deteksi minimal 60%. Hilangnya tangan atau terputusnya akuisisi lebih dari 0,55 detik menyebabkan penolakan. Batas durasi dan jumlah frame tersebut adalah pemeriksaan minimum, bukan jaminan bahwa gerakan sudah lengkap.

## Contoh pemanggilan

Contoh ini menunjukkan kontrak layanan. Tim frontend menempatkannya pada lifecycle dan callback kamera yang sudah ada, tanpa membuat stream kamera kedua.

```dart
final jz = JzRecognitionService();
final clock = Stopwatch();

Future<void> mulaiGerakan() async {
  await jz.startClip();
  clock..reset()..start();
}

// Panggil dari callback stream kamera yang sudah ada.
Future<void> terimaFrame(CameraImage image, int uprightRotation) async {
  if (jz.state != JzCaptureState.capturing) return;
  final timestampMs = clock.elapsedMilliseconds;
  try {
    await jz.addCameraFrame(
      image,
      timestampMs: timestampMs,
      rotationDegrees: uprightRotation,
    );
  } on JzBackendException catch (error) {
    // Tampilkan pesan yang sesuai dan batalkan clip jika pemrosesan gagal.
    await jz.cancelClip();
    tampilkanPesan(error.message);
  }
}

Future<void> akhiriGerakan() async {
  clock.stop();
  try {
    final result = await jz.finishClip();
    if (result.letter != null) {
      tambahkanHuruf(result.letter!); // Tambahkan sekali untuk clip ini.
    } else {
      // other/uncertain/rejected tidak menambahkan huruf.
      tampilkanHasil(result.toJson());
    }
  } on JzBackendException catch (error) {
    tampilkanPesan(error.message);
  }
}

// Saat meninggalkan fitur atau menutup pemilik layanan:
await jz.dispose();
```

`tampilkanPesan`, `tambahkanHuruf`, dan `tampilkanHasil` adalah fungsi frontend yang perlu dibuat tim. `CameraImage` berasal dari package `camera`. Tangani Future dari setiap callback, termasuk saat callback dipanggil tanpa `await` oleh plugin kamera.

## Kontrak hasil

`result.letter` hanya berisi `J` atau `Z` jika skor tertinggi mencapai 0,60. Nilai ini bukan ukuran akurasi di dunia nyata.

| `status` | `letter` | Tindakan frontend |
| --- | --- | --- |
| `recognized` | `J` atau `Z` | Tambahkan huruf sekali untuk clip tersebut |
| `other` | `null` | Jangan tambahkan huruf |
| `uncertain` | `null` | Jangan tambahkan huruf, tawarkan pengulangan |
| `rejected` | `null` | Baca `rejection.code` dan minta pengulangan |

`toJson()` memiliki bentuk berikut. Angka dan isi `quality` pada contoh ini hanya menjelaskan format.

```json
{
  "status": "recognized",
  "letter": "J",
  "prediction": {
    "raw_label": "J",
    "confidence": 0.95,
    "labels": ["J", "Z", "OTHER"],
    "scores": [0.95, 0.02, 0.03]
  },
  "quality": {
    "sampled_frames": 16,
    "detected_frames": 16,
    "detection_fraction": 1.0,
    "sampled_duration_seconds": 1.0,
    "longest_missing_gap_seconds": 0.0,
    "palm_scale": 0.12,
    "anchor_xyz": [0.4, 0.6, 0.0],
    "requested_sample_fps": 15.0,
    "actual_sample_fps": 15.0,
    "skipped_busy": 0,
    "skipped_interval": 14
  },
  "rejection": null
}
```

Untuk `rejected`, `prediction` bernilai `null`, `rejection` berisi `code` dan `message`, serta `quality` memuat hitungan capture yang tersedia. Jangan mengasumsikan seluruh field kualitas selalu ada.

## Penanganan error

Penolakan kualitas gerakan dikembalikan melalui `JzClipResult`. Kesalahan pemanggilan atau pemrosesan dilempar sebagai `JzBackendException` dengan `code` dan `message`.

| Kode | Arti dan tindakan |
| --- | --- |
| `clip_too_short`, `too_few_detected_samples` | Gerakan atau observasi terlalu sedikit, ulangi |
| `too_many_missing_detections`, `missing_gap_too_long` | Tangan tidak cukup terlihat, ulangi |
| `sampling_gap_too_long` | Capture terputus lebih dari 0,55 detik, ulangi |
| `invalid_palm_scale`, `invalid_landmarks`, `geometry_changed` | Landmark atau geometri tidak sesuai, batalkan lalu mulai ulang |
| `invalid_timestamp`, `stale_timestamp` | Jam tidak meningkat atau observasi lama dikirim ulang, perbaiki pengiriman frame |
| `busy`, `clip_already_started`, `clip_not_started` | Urutan pemanggilan tidak sesuai lifecycle |
| `invalid_frame`, `invalid_image` | Format, stride, ukuran atau isi frame salah |
| `hand_detection` | MediaPipe gagal, batalkan lalu mulai ulang |
| `model_mismatch` | Asset MediaPipe berbeda dari training, periksa dependency dan lakukan rebuild |
| `unsupported_platform` | Channel Android belum tersedia atau aplikasi perlu rebuild |
| `disposed` | Instance sudah ditutup, buat instance baru |
| `processing_failed` | Pemrosesan model gagal, hentikan clip dan catat pesan error |

## Hubungan dengan fitur 24 huruf

Foto dan upload tetap memakai `SignClassifier.instance.classifyFile(path)` atau `classifyUploadFile(path)`. Kamera statis tetap memakai `classifyCameraFrame(...)` dengan konfigurasi yang sudah ada. Jangan menambah J/Z ke `assets/models/labels.json` karena CNN tetap memiliki 24 output.

Untuk latihan J/Z, frontend mengarahkan satu gerakan ke `JzRecognitionService`. Jangan mengubah hasil CNN menjadi J/Z hanya karena labelnya mirip atau confidence GRU tinggi. Backend ini tidak melakukan penggantian prediksi CNN secara otomatis.

Pada latihan bebas, tombol Mulai J/Z dan Selesai gerakan menentukan batas satu gerakan. Prediksi statis diblokir selama potongan tersebut dan baru dilanjutkan setelah tangan diturunkan. Hasil satu clip bukan transkrip seluruh video. Susunan huruf sesi tetap disimpan saat sesi diakhiri, tanpa menambah spasi otomatis.

## Channel Android untuk pemeliharaan

Nama channel: `latih_isyarat/dynamic_hand_landmarker`. Frontend sebaiknya memakai layanan Dart, bukan memanggil channel secara langsung.

| Method native | Payload | Respons |
| --- | --- | --- |
| `startClip` | Tidak ada | `status`, `modelSha256` |
| `detectFrame` | `bytes`, `timestampMs` | `timestampMs`, `width`, `height`, `hands` berupa daftar tangan dengan 21 titik `[x,y,z]` |
| `finishClip` | Tidak ada | `status`, `framesProcessed` |
| `dispose` | Tidak ada | `status`, tracker dilepas, channel tetap dapat dipakai ulang |

Tidak ada crop gambar untuk input GRU. Model ini membaca lintasan titik tangan. CNN 24 huruf tetap menggunakan crop pada jalurnya sendiri. Task MediaPipe berasal dari plugin `hand_landmarker` yang sudah digunakan proyek, tanpa unduhan tambahan saat aplikasi dijalankan.

## Batas validasi

Backend membutuhkan rebuild Android karena ada kode native dan asset baru. Hot reload saja tidak cukup. Implementasi ini belum diuji dengan gesture kamera Vivo atau pengguna baru. OTHER baru diuji pada sampel sintetis, sehingga penolakan gerakan lain masih perlu diuji di HP. Model J/Z dan CNN tetap dua file terpisah.
