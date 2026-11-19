# Uji 8 Model SVM-HOG pada Foto Drive

Dataset uji terdiri dari 24 foto A sampai Y tanpa J dan Z.
Setiap foto diuji pada kondisi asli dan 15 variasi terkontrol.
Preprocessing model tidak diubah.

## Akurasi foto asli

| Model | Benar | Total | Akurasi |
|---|---:|---:|---:|
| 01_rbf_C1.0_gamma_scale_no_aug.joblib | 4 | 24 | 16.6667% |
| 02_rbf_C1.0_gamma_0_001_no_aug.joblib | 4 | 24 | 16.6667% |
| 03_rbf_C10.0_gamma_scale_no_aug.joblib | 4 | 24 | 16.6667% |
| 04_rbf_C10.0_gamma_0_001_no_aug.joblib | 4 | 24 | 16.6667% |
| 05_rbf_C100.0_gamma_scale_no_aug.joblib | 4 | 24 | 16.6667% |
| 06_rbf_C100.0_gamma_0_001_no_aug.joblib | 4 | 24 | 16.6667% |
| 07_rbf_C100.0_gamma_scale_augmented.joblib | 6 | 24 | 25.0% |
| 08_rbf_C10.0_gamma_scale_augmented.joblib | 6 | 24 | 25.0% |

## Akurasi semua variasi

| Model | Benar | Total | Akurasi |
|---|---:|---:|---:|
| 01_rbf_C1.0_gamma_scale_no_aug.joblib | 66 | 384 | 17.1875% |
| 02_rbf_C1.0_gamma_0_001_no_aug.joblib | 63 | 384 | 16.4062% |
| 03_rbf_C10.0_gamma_scale_no_aug.joblib | 66 | 384 | 17.1875% |
| 04_rbf_C10.0_gamma_0_001_no_aug.joblib | 63 | 384 | 16.4062% |
| 05_rbf_C100.0_gamma_scale_no_aug.joblib | 66 | 384 | 17.1875% |
| 06_rbf_C100.0_gamma_0_001_no_aug.joblib | 63 | 384 | 16.4062% |
| 07_rbf_C100.0_gamma_scale_augmented.joblib | 84 | 384 | 21.875% |
| 08_rbf_C10.0_gamma_scale_augmented.joblib | 84 | 384 | 21.875% |

Variasi yang digunakan adalah rotasi ±5° dan ±10°, skala 0,90 dan 1,10, pergeseran ±5%, perubahan brightness, perubahan contrast, blur ringan, dan noise ringan.
Foto ini berasal dari folder Drive publik yang sebelumnya disalin ke workspace. Label diambil dari manifest nama file dan bukan label resmi dari dataset benchmark.
