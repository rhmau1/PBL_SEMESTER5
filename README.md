# LatihIsyarat: SVM-HOG

Branch: `RAMA-SVM-HOG`.
Basis frontend: `origin/silva`, commit `3190f377ef034b6fa68db3a8360b45b5ed9c1e20`.

## Yang tersedia

Tampilan dan navigasi dari Silva: splash, onboarding, beranda, Video,
Foto, Upload satu atau banyak gambar, kamus, riwayat, progres belajar,
dan badges. Aset gambar, tema, serta komponen UI tetap digunakan.
Preview kamera, pengambilan foto, pemilih gambar, dan penyimpanan lokal
frontend dipertahankan.

## Deteksi di perangkat

`SvmHogClassifier` menjalankan preprocessing, HOG, StandardScaler, dan RBF SVM
augmented langsung di perangkat. API Dart menerima file foto dan buffer
luma kamera untuk layar Foto, Upload, dan Video. Asetnya mendukung 24 huruf
statis. Foto diterima berdasarkan kesepakatan prediksi crop. Video mencatat
huruf setelah tiga sampel berurutan memilih huruf yang sama.

Kontrak hasil dan pengujian backend ada di
[PRD integrasi](docs/PRD_SVM_HOG_MOBILE_INTEGRATION.md).

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
flutter run --dart-define=GEMINI_API_KEY=API_KEY_GEMINI_KAMU
```
