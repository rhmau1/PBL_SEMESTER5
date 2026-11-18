# LatihIsyarat: SVM-HOG

Branch: `RAMA-SVM-HOG`.
Basis frontend: `origin/silva`, commit `3190f377ef034b6fa68db3a8360b45b5ed9c1e20`.

## Yang tersedia

Tampilan dan navigasi dari Silva: splash, onboarding, beranda, Video,
Foto, Upload satu atau banyak gambar, kamus, riwayat, progres belajar,
dan badges. Aset gambar, tema, serta komponen UI tetap digunakan.
Preview kamera, pengambilan foto, pemilih gambar, dan penyimpanan lokal
frontend dipertahankan.

## Deteksi pada perangkat

Foto, Upload satu/banyak gambar, dan Video memakai RBF SVM augmented, HOG,
dan StandardScaler dalam Dart. Aplikasi memuat aset `assets/models/svm_hog.bin.gz`
otomatis dari APK. Gunakan satu tangan utuh dengan latar polos dan kontras.
Video latihan bebas menampilkan urutan setelah Akhiri. Uji huruf berjalan
otomatis saat target dipilih. Dukungan mencakup 24 huruf statis di luar J/Z.

Hasil bersifat eksperimental. Persetujuan dua crop menjadi aturan penerimaan
dan tampilan SVM tidak memberi persentase keyakinan. Lihat
[PRD integrasi](docs/PRD_SVM_HOG_MOBILE_INTEGRATION.md) untuk hasil pengujian.

## Training di Google Colab

Upload hanya `training/SVM_HOG/TRAINING_SVM_HOG_COLAB.ipynb` ke Colab,
lalu pilih Run all. Tidak perlu upload file Python pendamping.
Panduan dan lokasi hasil ada di [training/SVM_HOG/README.md](training/SVM_HOG/README.md).

## Menjalankan aplikasi

Gunakan lingkungan Flutter dan Android pada REQUIREMENTS.md.

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```
