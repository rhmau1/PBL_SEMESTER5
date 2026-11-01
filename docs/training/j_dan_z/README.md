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

Kode di folder ini sama dengan kode pada hasil training 1 November 2026. Generator notebook dan tes pengembangan tidak diperlukan untuk menjalankannya.
