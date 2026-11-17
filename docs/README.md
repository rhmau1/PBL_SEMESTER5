# Dokumentasi model dan backend

Folder ini menyimpan sumber training, bukti hasil, dan kontrak backend J/Z untuk integrasi frontend.

| Folder | Isi |
| --- | --- |
| [training/model_24_huruf](training/model_24_huruf/README.md) | Kode training model CNN 24 huruf yang dipakai aplikasi |
| [training/j_dan_z](training/j_dan_z/README.md) | Notebook Colab mandiri dan kode training GRU J/Z/OTHER |
| [DATASET](DATASET/README.md) | CSV Sign Language MNIST, foto Hugging Face, dan dataset fitur gerakan J/Z |
| [laporan](laporan/HASIL_TRAINING_2026-11-01.md) | Hasil terbaru, ukuran model, grafik, dan bukti JSON/CSV asli |
| [integrasi](integrasi/BACKEND_J_Z.md) | API backend J/Z, kontrak hasil, dan panduan untuk frontend |

Hasil implementasi dan pemeriksaan backend ada di [laporan implementasi J/Z](integrasi/HASIL_IMPLEMENTASI_J_Z.md).

Untuk training J/Z di Colab, unggah `training/j_dan_z/TRAINING_J_Z_COLAB.ipynb`, pilih GPU, lalu jalankan **Run all**. Kode dan model 24 huruf sudah tertanam dalam notebook.

Model J/Z terhubung ke menu Video melalui target J/Z dan tombol gerakan pada latihan bebas. Cara menggunakan dan batasannya ada di [panduan frontend J/Z](integrasi/FRONTEND_J_Z.md). Model 24 huruf tetap `camera_robust_v1`, berukuran 326.108 byte.
