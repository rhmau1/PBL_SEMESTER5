# Model Final SVM-HOG Augmented

Model yang disimpan di folder ini adalah kandidat final untuk pengujian kamera.

- Metode RBF SVM
- C = 100
- Gamma = scale
- Augmentasi training aktif
- Fitur HOG 1.764 dimensi
- Ukuran model sekitar 75,66 MiB
- Validation accuracy dan macro-F1 masing-masing 100%
- Official test MNIST belum dijalankan khusus untuk model ini
- Uji foto Drive asli memperoleh 25% pada 24 foto
- Uji seluruh variasi foto memperoleh 21,875% pada 384 input
- Model hanya mendukung 24 huruf tanpa J dan Z

Model membutuhkan preprocessing yang sama dengan training sebelum dipakai. Foto kamera perlu disiapkan menjadi crop tangan berbentuk persegi, grayscale, terpusat, lalu diubah menjadi fitur HOG sebelum masuk ke pipeline SVM.

ZIP delapan kandidat tetap disimpan di folder Downloads sebagai arsip eksperimen.
