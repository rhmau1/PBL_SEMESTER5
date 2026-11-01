# Dokumentasi training

Folder ini menyimpan sumber training dan bukti hasil sebelum penambahan J/Z ke aplikasi.

| Folder | Isi |
| --- | --- |
| [training/model_24_huruf](training/model_24_huruf/README.md) | Kode training model CNN 24 huruf yang dipakai aplikasi |
| [training/j_dan_z](training/j_dan_z/README.md) | Notebook Colab mandiri dan kode training GRU J/Z/OTHER |
| [DATASET](DATASET/README.md) | CSV Sign Language MNIST, foto Hugging Face, dan dataset fitur gerakan J/Z |
| [laporan](laporan/HASIL_TRAINING_2026-11-01.md) | Hasil terbaru, ukuran model, grafik, dan bukti JSON/CSV asli |

Untuk training J/Z di Colab, unggah `training/j_dan_z/TRAINING_J_Z_COLAB.ipynb`, pilih GPU, lalu jalankan **Run all**. Kode dan model 24 huruf sudah tertanam dalam notebook.

Dokumentasi ini tidak memasang model J/Z ke aplikasi. Model 24 huruf yang digunakan tetap `camera_robust_v1`, berukuran 326.108 byte.
