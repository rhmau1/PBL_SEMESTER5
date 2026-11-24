# Dokumentasi Atribusi & Lisensi Aset (Third-Party Assets & Licenses)

Dokumen ini mencatat kepatuhan hukum (*legal compliance*), lisensi terbuka, dan atribusi sumber daya visual maupun model pihak ketiga yang digunakan dalam pengembangan aplikasi **LatihIsyarat**.

---

## 1. Gambar Referensi Alfabet Bahasa Isyarat (`assets/signs/`)

* **Lokasi Berkas**: `assets/signs/a.png` s.d. `assets/signs/y.png` (24 gambar alfabet statis).
* **Sumber Aset**: Dataset **Sign Language MNIST** oleh Datamunge pada Kaggle:
  [https://www.kaggle.com/datasets/datamunge/sign-language-mnist](https://www.kaggle.com/datasets/datamunge/sign-language-mnist)
* **Lisensi**: **Creative Commons Zero: Public Domain (CC0)**.
* **Keterangan Penggunaan**:
  Foto-foto ini dipotong (*cropped*) dari gambar referensi master `amer_sign2.png` yang disertakan di dalam dataset Kaggle tersebut. Gambar ini disajikan di dalam aplikasi hanya sebagai panduan visual edukatif pada menu **Kamus Isyarat** dan instruksi pose tangan.
* **Catatan Huruf J dan Z**:
  Huruf J dan Z memerlukan gerakan tangan dinamis (*motion*) sehingga tidak tersedia dalam bentuk gambar statis pada dataset ini maupun dalam klasifikasi gestur statis aplikasi.

---

## 2. Model Deteksi Titik Sendi Tangan (MediaPipe Hand Landmarker)

* **Model**: Google MediaPipe Tasks Vision Hand Landmarker (`hand_landmarker.task`).
* **Pengembang**: Google LLC.
* **Tautan Sumber**: [https://developers.google.com/mediapipe/solutions/vision/hand_landmarker](https://developers.google.com/mediapipe/solutions/vision/hand_landmarker)
* **Lisensi**: **Apache License 2.0**.
* **Keterangan Penggunaan**:
  Digunakan untuk mengekstraksi 21 koordinat tiga dimensi (X, Y, Z) titik persendian tangan secara *real-time* pada mode video kamera dan foto still-image secara lokal di perangkat (*on-device*).

---

## 3. Model Hybrid Machine Learning (`assets/models/svm_hog.bin.gz`)

* **Lokasi Berkas**: `assets/models/svm_hog.bin.gz` (~34.9 MB terkompresi).
* **Metode**: Hybrid Multi-class RBF Support Vector Machine (1867 dimensi fitur gabungan HOG, LBP Uniform, Hu Invariant Moments, Kontur Geometri, dan 21 MediaPipe Landmarks).
* **Basis Dataset Training**: Dilatih menggunakan dataset Sign Language MNIST (Lisensi CC0: Public Domain) dengan teknik augmentasi rotasi dan skala.
* **Lisensi Model**: Karya orisinal tim pengembang LatihIsyarat.

---

## 4. Aset Vektor Lencana & Maskot (`assets/badges/` & `assets/logo/`)

* **Lencana Gamifikasi**:
  * `assets/badges/keep_learning.svg`
  * `assets/badges/good.svg`
  * `assets/badges/excellent.svg`
  * `assets/badges/perfect.svg`
  * `assets/badges/impossible.svg`
* **Maskot Aplikasi**:
  * `assets/logo/signy_maskot.svg`
* **Lisensi**: Desain orisinal tim pengembang LatihIsyarat untuk keperluan PBL Semester 5.

---

## 5. Tipografi & Ikon Sistem

* **Material Icons**: Desain ikon antarmuka oleh Google LLC di bawah lisensi **Apache License 2.0**.
* **Font Roboto**: Font tipografi standar Material Design oleh Google LLC di bawah lisensi **Apache License 2.0**.
