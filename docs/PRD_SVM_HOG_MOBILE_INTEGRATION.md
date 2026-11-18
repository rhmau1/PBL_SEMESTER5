# PRD Integrasi Model SVM-HOG ke Flutter

## Status implementasi

- Aset inferensi `assets/models/svm_hog.bin.gz` berukuran 63.615.075 byte
  (60,67 MiB). Ekspor float32 berasal dari Joblib model 07 dan dimuat sekali ke
  isolate Dart. HOG dan inferensi dicocokkan dengan scikit-learn 1.6.1 pada
  43 input grayscale 64×64 dari bukti MNIST. Seluruh label cocok.
- Backend foto memakai orientasi EXIF, segmentasi foreground klasik,
  dua crop persegi, grayscale, resize 28×28 lalu 64×64, dan HOG.
  Hasil diterima jika dua crop memilih huruf yang sama. Skor keputusan
  SVM tersedia sebagai nilai keputusan mentah.
- Backend frame menerima bidang luma kamera dan memakai jalur crop serta
  inferensi yang sama. Tim frontend memegang sambungan layar dan sesi video.
- Uji diagnostik lokal pada 24 foto Drive berlatar putih menghasilkan 8 benar,
  10 salah, dan 6 ditolak karena dua crop berbeda. Akurasi seluruh input
  33,33%. Foto ini dipakai untuk pengembangan dan belum mengukur akurasi
  penggunaan kamera umum. Ulangi uji dengan pose dan pengguna baru sebelum
  menyatakan model siap produksi.

## 1. Tujuan

Menyiapkan backend SVM-HOG augmented untuk frontend Flutter dari Silva.
API backend tersedia untuk Foto, Upload satu atau banyak gambar, dan frame Video.

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
    -> grayscale
    -> segmentasi foreground dan dua crop persegi
    -> resize 28×28 lalu 64×64
    -> ekstraksi HOG
    -> StandardScaler
    -> RBF SVM
    -> label huruf dan skor keputusan
    -> periksa kesepakatan dua crop
```

Model training memakai gambar MNIST 28x28 yang diproses menjadi 64x64 sebelum HOG. Preprocessing mobile harus menghasilkan bentuk dan skala tangan yang sama. Crop yang berbeda dari training dapat menyebabkan penurunan akurasi walaupun model benchmark memiliki hasil tinggi.

## 4. Kontrak backend Flutter

Panggil `SvmHogClassifier.instance` dari `lib/services/svm_hog_classifier.dart`.

### `initialize`

Memuat konfigurasi model, scaler, support vector, koefisien, intercept, dan konfigurasi HOG. Fungsi harus aman dipanggil lebih dari satu kali dan tidak memuat model berulang kali.

### `classifyFile`

Menerima path gambar dan mengembalikan `Future<SvmHogPrediction>`.
File hilang, gambar gagal dibaca, atau foreground yang gagal dipisahkan
menghasilkan `FormatException`. Timeout inferensi menghasilkan `StateError`.

### `classifyLuma`

Menerima byte bidang Y dengan `width`, `height`, `stride` (byte per baris),
`pixelStride`, dan rotasi searah jarum jam `0/90/180/270`. Hasil `null`
berarti area foreground gagal dipisahkan. Buffer atau metadata yang tidak
valid menghasilkan `FormatException`.

### `SvmHogPrediction`

- `label` adalah huruf dari crop pertama.
- `accepted` bernilai benar saat kedua crop memilih huruf yang sama.
- `scores` berisi 24 skor keputusan dalam urutan label di bagian 7.
  Persentase keyakinan memerlukan kalibrasi tersendiri.
- Gunakan `SvmHogClassifier.modelId` untuk identitas model pada riwayat.

## 5. Pekerjaan implementasi berurutan

1. Bekukan artefak model augmented dan checksum-nya.
2. Ekspor isi Joblib menjadi format portabel yang dapat dibaca Flutter. Data yang diperlukan adalah scaler, support vector, dual coefficient, intercept, gamma, dan label.
3. Implementasikan preprocessing gambar di satu tempat agar mode Foto, Upload, dan kamera memakai aturan yang sama.
4. Implementasikan crop tangan persegi dengan padding. Aturan crop harus menghindari tangan gepeng dan mempertahankan seluruh jari.
5. Samakan ukuran input melalui grayscale, padding dengan warna latar, dan resize.
6. Implementasikan HOG dengan konfigurasi 64x64, 9 orientasi, cell 8x8, block 2x2, dan L2-Hys.
7. Implementasikan StandardScaler menggunakan nilai mean dan scale dari training.
8. Implementasikan kernel RBF dan klasifikasi multi-kelas SVM.
9. Sambungkan adaptor frontend `SignClassifier` ke API Dart pada bagian 4.
10. Hubungkan hasil satu foto ke `CameraScreen` dan `UploadScreen` melalui `classifyFile`.
11. Panggil `classifyFile` untuk setiap gambar di loop Upload.
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

Tim frontend bisa memanggil `classifyFile` setelah pengambilan foto dan
`classifyLuma` pada frame Video terpilih. Untuk Video, batasi satu
permintaan pada satu waktu, tunggu prediksi stabil pada beberapa frame,
dan abaikan respons lama setelah sesi atau target berubah.

Mode Video memerlukan perhatian khusus karena SVM-HOG hanya mengenali pose statis. J dan Z membutuhkan model gerakan terpisah dan belum masuk ke model ini.

### UploadScreen

Tim frontend bisa memakai pemilih gambar dan loop Upload yang sudah ada.
Proses setiap path dengan `classifyFile` dan tangani kegagalan per gambar.

### Riwayat dan progres

Simpan label ketika hasil lolos aturan penerimaan. Kontrak UI lama memiliki
kolom keyakinan dalam persen. Tampilkan hasil SVM dengan status penerimaan
dan biarkan nilai probabilitas kosong sampai tersedia kalibrasi.

## 7. Ruang lingkup label

Model ini mengenali huruf:

```text
A B C D E F G H I K L M N O P Q R S T U V W X Y
```

J dan Z tidak diproses oleh SVM-HOG ini. Keduanya memerlukan model gerakan atau analisis rangkaian frame yang terpisah.

## 8. Kriteria selesai

- `SvmHogClassifier.initialize` berhasil memuat aset.
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
