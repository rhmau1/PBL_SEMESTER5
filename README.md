# LatihIsyarat: Random Forest HOG

Branch: `RAMA-SVM-HOG` (backend klasifikasi kini menggunakan Random Forest HOG).
Basis frontend: `origin/silva`, commit `3190f377ef034b6fa68db3a8360b45b5ed9c1e20`.

## Yang tersedia

Tampilan dan navigasi dari Silva: splash, onboarding, beranda, Video,
Foto, Upload satu atau banyak gambar, kamus, riwayat, progres belajar,
dan badges. Aset gambar, tema, serta komponen UI tetap digunakan.
Preview kamera, pengambilan foto, pemilih gambar, dan penyimpanan lokal
frontend dipertahankan.

## Deteksi di perangkat

`RandomForestHogClassifier` menjalankan preprocessing, ekstraksi HOG, dan
inferensi Random Forest langsung di perangkat. Model sumber
`assets/models/random_forest_hog.joblib` diekspor ke format aset Dart
`assets/models/random_forest_hog.bin.gz`. API Dart menerima file foto dan buffer
luma kamera untuk layar Foto, Upload, dan Video. Asetnya mendukung 24 huruf
statis. Foto diterima berdasarkan kesepakatan prediksi crop. Video mencatat
huruf setelah tiga sampel berurutan memilih huruf yang sama.

Ekspor ulang model dengan menjalankan `training/SVM_HOG/export_random_forest_hog.py`
setelah memasang `joblib==1.4.2` dan `scikit-learn==1.6.1`:

```bash
python training/SVM_HOG/export_random_forest_hog.py \
  assets/models/random_forest_hog.joblib \
  assets/models/random_forest_hog.bin.gz
```

Joblib adalah format pickle Python dan tidak dimuat oleh Flutter. Konverter
hanya boleh dijalankan pada file model tepercaya.

Notebook SVM-HOG lama di `training/SVM_HOG` bukan bagian dari backend inferensi
Random Forest yang digunakan aplikasi.

## Menjalankan aplikasi

Gunakan lingkungan Flutter dan Android pada REQUIREMENTS.md.

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```
