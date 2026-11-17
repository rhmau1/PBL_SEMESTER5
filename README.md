# LatihIsyarat: frontend untuk SVM-HOG

Branch: `RAMA-SVM-HOG`.
Basis frontend: `origin/silva`, commit `3190f377ef034b6fa68db3a8360b45b5ed9c1e20`.

## Yang tersedia

Tampilan dan navigasi dari Silva: splash, onboarding, beranda, Video,
Foto, Upload satu atau banyak gambar, kamus, riwayat, progres belajar,
dan badges. Aset gambar, tema, serta komponen UI tetap digunakan.
Preview kamera, pengambilan foto, pemilih gambar, dan penyimpanan lokal
frontend dipertahankan.

## Status backend

Backend SVM-HOG belum dibuat atau dilatih. Model CNN, MediaPipe, model E,
serta praproses dan pengujian model lama dilepas dari snapshot branch ini.
Riwayat Git asal tetap tersedia dan branch rama maupun silva tidak diubah.

`lib/services/sign_classifier.dart` hanya menjadi penghubung sementara.
Saat diminta memprediksi atau memulai analisis, penghubung ini memberi pesan
bahwa backend belum terpasang. Tidak ada hasil huruf atau confidence buatan.
Video belum melakukan pengenalan. Foto dan Upload belum dapat memprediksi.
Pilihan model menampilkan SVM + HOG untuk persiapan sambungan berikutnya.
Ambang penerimaan lama pada UI belum menjadi kontrak untuk skor SVM.

Training, segmentasi tangan, ekstraksi HOG, serta inferensi SVM akan dikerjakan
pada tahap berikutnya sesuai instruksi. J dan Z belum diimplementasikan.

## Menjalankan frontend

Gunakan lingkungan Flutter dan Android pada REQUIREMENTS.md.

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Tidak ada build atau pemasangan ke HP pada tahap penyiapan branch ini.
