# PRD Integrasi Model SVM-HOG ke Flutter

## 1. Tujuan

Menghubungkan model SVM-HOG augmented ke frontend Flutter yang berasal dari branch Silva. Integrasi mencakup mode Foto, Upload satu gambar, Upload banyak gambar, dan alur kamera yang sudah tersedia.

Tampilan, navigasi, kamus, riwayat, progres belajar, dan badges tetap menggunakan frontend yang ada. Pekerjaan utama berada pada backend inferensi dan sambungan ke `SignClassifier`.

## 2. Model yang dipakai

Model yang disiapkan untuk pengujian kamera adalah:

- RBF SVM
- `C = 100`
- `gamma = scale`
- Augmentasi training aktif
- HOG dengan 1.764 fitur
- StandardScaler
- 24 huruf statis tanpa J dan Z
- Ukuran Joblib sekitar 75,66 MiB

Model Joblib tidak bisa dimuat oleh `tflite_flutter`. TFLite digunakan untuk model TensorFlow seperti CNN. SVM-HOG membutuhkan implementasi inferensi khusus atau backend Python.

## 3. Alur inferensi

```text
Foto atau frame kamera
    -> orientasi dan pembacaan gambar
    -> crop tangan berbentuk persegi
    -> grayscale
    -> penyesuaian kontras dan latar
    -> resize sesuai konfigurasi
    -> ekstraksi HOG
    -> StandardScaler
    -> RBF SVM
    -> label huruf dan skor keputusan
    -> validasi hasil
    -> tampilan dan riwayat
```

Model training memakai gambar MNIST 28x28 yang diproses menjadi 64x64 sebelum HOG. Preprocessing mobile harus menghasilkan bentuk dan skala tangan yang sama. Crop yang berbeda dari training dapat menyebabkan penurunan akurasi walaupun model benchmark memiliki hasil tinggi.

## 4. Kontrak backend Flutter

File utama yang menjadi boundary adalah `lib/services/sign_classifier.dart`.

### `initialize`

Memuat konfigurasi model, scaler, support vector, koefisien, intercept, dan konfigurasi HOG. Fungsi harus aman dipanggil lebih dari satu kali dan tidak memuat model berulang kali.

### `classifyFile`

Menerima path gambar, menjalankan preprocessing, HOG, scaler, dan SVM, lalu mengembalikan `SignPrediction`.

### `classifyUploadFile`

Memakai jalur yang sama dengan `classifyFile` untuk satu gambar dan banyak gambar.

### `SignPrediction`

Mengembalikan label huruf, skor keputusan, dan daftar skor kelas. Skor SVM bukan probabilitas. UI tidak boleh menyebutnya sebagai persentase kepastian sebelum kalibrasi ditambahkan.

## 5. Pekerjaan implementasi berurutan

1. Bekukan artefak model augmented dan checksum-nya.
2. Ekspor isi Joblib menjadi format portabel yang dapat dibaca Flutter. Data yang diperlukan adalah scaler, support vector, dual coefficient, intercept, gamma, dan label.
3. Implementasikan preprocessing gambar di satu tempat agar mode Foto, Upload, dan kamera memakai aturan yang sama.
4. Implementasikan crop tangan persegi dengan padding. Aturan crop harus menghindari tangan gepeng dan mempertahankan seluruh jari.
5. Implementasikan grayscale, normalisasi ukuran, dan penyesuaian latar sesuai data training.
6. Implementasikan HOG dengan konfigurasi 64x64, 9 orientasi, cell 8x8, block 2x2, dan L2-Hys.
7. Implementasikan StandardScaler menggunakan nilai mean dan scale dari training.
8. Implementasikan kernel RBF dan klasifikasi multi-kelas SVM.
9. Hubungkan backend ke `SignClassifier.initialize`.
10. Hubungkan hasil satu foto ke `CameraScreen` dan `UploadScreen` melalui `classifyFile`.
11. Hubungkan hasil banyak foto ke loop upload yang sudah tersedia melalui `classifyUploadFile`.
12. Simpan riwayat hanya ketika hasil melewati aturan penerimaan yang telah ditentukan.
13. Tampilkan status gagal, belum yakin, dan gambar tanpa tangan tanpa membuat huruf palsu.
14. Pastikan perpindahan tab, background aplikasi, penggantian kamera, dan sesi baru membatalkan pekerjaan inferensi yang masih berjalan.
15. Uji hasil pada gambar yang sama antara Python dan Flutter untuk memeriksa kesamaan label dan fitur.
16. Uji foto nyata dengan variasi rotasi, skala, posisi, brightness, contrast, blur, dan noise.
17. Ukur waktu inferensi, penggunaan memori, dan ukuran APK pada perangkat Android.
18. Perbarui dokumentasi hasil dan checksum setelah validasi selesai.

## 6. Penyesuaian dengan frontend Silva

### DetectionPage

`DetectionPage` tetap menjadi pemilih Video, Foto, dan Upload. State model yang sudah memakai `SignModel.svmHog` tetap digunakan.

### CameraScreen

Mode Foto memanggil `classifyFile` setelah foto diambil. Mode Video memproses frame yang sudah dipilih oleh aturan sampling. Hasil hanya diterima setelah prediksi stabil pada beberapa frame.

Mode Video memerlukan perhatian khusus karena SVM-HOG hanya mengenali pose statis. J dan Z membutuhkan model gerakan terpisah dan belum masuk ke model ini.

### UploadScreen

Upload satu dan banyak gambar tetap memakai pemilih gambar, indikator proses, tampilan hasil, dan penyimpanan riwayat yang sudah tersedia. Implementasi backend menggantikan kegagalan sementara pada `SignClassifier`.

### Riwayat dan progres

Gunakan `modelId = svm_hog_augmented_c100_scale`. Simpan label hanya ketika hasil lolos aturan penerimaan. Skor keputusan SVM disimpan sebagai skor model sampai kalibrasi probabilitas tersedia.

## 7. Ruang lingkup label

Model ini mengenali huruf:

```text
A B C D E F G H I K L M N O P Q R S T U V W X Y
```

J dan Z tidak diproses oleh SVM-HOG ini. Keduanya memerlukan model gerakan atau analisis rangkaian frame yang terpisah.

## 8. Kriteria selesai

- `SignClassifier.initialize` berhasil memuat artefak tanpa error.
- Hasil prediksi Flutter dan Python sama pada kumpulan gambar uji.
- Foto dan Upload dapat menghasilkan label yang benar atau status belum yakin.
- Tidak ada hasil palsu yang masuk ke riwayat.
- Kamera tetap mempertahankan orientasi dan rasio tampilan yang sudah benar.
- Model tidak dimuat ulang pada setiap frame.
- Pengujian mencakup 24 huruf statis dan kondisi gambar yang bervariasi.
- Ukuran APK, waktu inferensi, dan penggunaan memori tercatat.
- J dan Z tetap diberi status belum didukung pada alur statis.

## 9. Catatan deployment

Joblib tidak dipasang langsung ke APK. Jalur on-device memerlukan implementasi HOG dan RBF SVM dalam Dart atau native code. Jalur backend Python dapat memakai Joblib secara langsung, tetapi memerlukan koneksi ke layanan backend.

Model augmented di folder `training/SVM_HOG_FINAL_AUGMENTED` adalah kandidat final untuk pengujian kamera. Model belum dianggap siap produksi sampai preprocessing mobile dan uji perangkat nyata selesai.
