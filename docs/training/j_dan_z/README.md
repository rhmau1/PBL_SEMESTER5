# Training J dan Z

Unggah `TRAINING_J_Z_COLAB.ipynb` ke Google Colab, pilih GPU, lalu jalankan **Run all**. Notebook sudah memuat seluruh kode, dependency, dan salinan model 24 huruf. Dataset serta hasil disimpan di Google Drive. Hasil lengkap dikemas dalam satu ZIP untuk diunduh.

| File | Fungsi |
| --- | --- |
| `train_all.py` | Menjalankan evaluasi, training, dan penyimpanan hasil |
| `dynamic_training.py` | Melatih GRU J/Z/OTHER dari urutan landmark MediaPipe |
| `static_training.py` | Mengevaluasi CNN 24 huruf tanpa melatih ulang atau mengubah bobot |
| `training_common.py` | Membagi data, memeriksa cache, membuat laporan, dan mengekspor model |
| `requirements_colab.txt` | Dependency training |
| `baseline_model/` | Model 24 huruf, label, dan metadata yang diperlukan skrip |

Hasil training 1 November 2026 tetap menjadi arsip. Pembaruan 15 November 2026
menyamakan sampling crop evaluasi foto dengan aplikasi: luminance dibulatkan,
grid 4 × 4, lalu rata-rata dibulatkan ke bawah. Deteksi foto yang kosong dicoba
sekali lagi dengan border putih dan koordinat dipetakan kembali ke foto asli.
Hasil retry diperiksa terhadap foto utuh sebelum diterima. Cache lama tidak
dipakai untuk versi preprocessing baru.

Notebook mandiri sudah memuat pembaruan ini. Model 24 huruf tetap dievaluasi
tanpa training ulang. Penyamaan preprocessing tidak mengubah bobot model
atau menjamin semua foto nyata langsung benar. Kontrak piksel diuji melalui
`test/static_preprocessing_contract_test.dart` dan
`test/training_static_preprocessing_test.py` di root proyek.
