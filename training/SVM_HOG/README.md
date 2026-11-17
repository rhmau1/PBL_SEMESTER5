# Training HOG + SVM di Google Colab

## File mana yang dijalankan?

**Hanya upload dan jalankan TRAINING_SVM_HOG_COLAB.ipynb.**
Notebook sudah memuat seluruh skrip. Tidak perlu upload file .py, project
Flutter, model lama, atau dataset secara manual jika unduhan otomatis berhasil.

train_svm_hog.py adalah sumber Python untuk pemeriksaan dan reproduksi.
Kamu tidak perlu menjalankannya terpisah saat memakai notebook.

## Cara menjalankan

1. Buka Google Colab, pilih File > Upload notebook.
2. Pilih TRAINING_SVM_HOG_COLAB.ipynb dari folder ini.
3. Gunakan runtime CPU. Implementasi scikit-learn ini tidak memakai GPU.
4. Pilih Runtime > Run all dan izinkan koneksi Google Drive.
5. Biarkan pengaturan awal seed 42 dan konfigurasi lainnya tetap default.
6. Tunggu sampai cell terakhir menampilkan lokasi model dan ZIP.
7. ZIP akan dicoba diunduh melalui browser. Ekstrak lalu buka LAPORAN_HASIL.html.

Jika Kaggle menolak unduhan atau sedang bermasalah, unduh ZIP dataset
Sign Language MNIST dari Kaggle. Upload ZIP ke Files Colab, isi
DATASET_ZIP_PATH pada cell pengaturan, lalu ulangi dari pengaturan.

## Data dan alur training

Dataset: datamunge/sign-language-mnist di Kaggle.
File train dibagi menjadi training dan validation sekitar 80:20.
Official test tetap terpisah. Jumlah aktual dicatat dari CSV, tidak dikarang.
Gambar identik dikelompokkan. Identitas orang/sesi asli tidak tersedia,
sehingga pemisahan berdasarkan signer belum dapat dibuktikan.

Preprocessing: EXIF, grayscale, estimasi latar, selisih intensitas,
Gaussian blur, Otsu, morfologi ringan untuk gambar berukuran cukup besar,
connected components, crop persegi dengan padding, resize 64x64.
Mask menentukan area crop. HOG dihitung dari crop grayscale, bukan mask.

Fitur: HOG 9 arah, sel 8x8, blok 2x2, L2-Hys, transform_sqrt.
Konfigurasi 64x64 ini menghasilkan 1.764 fitur.
StandardScaler dilatih hanya dari bagian training.

Default membandingkan sampai 10 kandidat: Linear SVM, 6 konfigurasi RBF,
lalu pembanding Linear dan maksimal 2 RBF dengan augmentasi.
Augmentasi hanya pada sekitar 35% gambar training per kelas: rotasi,
pergeseran, skala, pencahayaan, dan blur/noise ringan. Tanpa flip otomatis.

Pemenang ditentukan oleh macro-F1 validation, lalu accuracy dan ukuran.
Jika Linear SVM lebih baik, pemenangnya tetap dilaporkan sebagai Linear SVM.
Official test dievaluasi setelah pemilihan. Gambar yang ditolak preprocessing
dihitung sebagai kesalahan pada accuracy seluruh input.

## Tersimpan di mana?

Folder utama di Google Drive:

    MyDrive/LatihIsyarat_SVM_HOG/
      cache/dataset/       ZIP dan dua CSV, tidak diunduh ulang jika valid
      cache/features/      fitur dengan identitas konfigurasi
      cache/models/        checkpoint tiap kandidat
      runs/svm_hog_v1_<hash>/
      runs/svm_hog_v1_<hash>_LENGKAP.zip

Konfigurasi, dataset, versi program, dan versi dependency diperiksa sebelum
cache/checkpoint digunakan kembali. Untuk melanjutkan setelah runtime putus,
jalankan notebook lagi dengan versi dan konfigurasi yang sama.
SVM bisa lama pada CPU dan tidak memiliki progres accuracy tiap epoch.
Waktu sebenarnya bergantung runtime dan jumlah support vector, belum diukur.

## Isi ZIP

- model_svm_hog.joblib: model terpilih beserta StandardScaler.
- labels.json, preprocessing_config.json, model_metadata.json.
- validation_comparison.csv/png dan winner_validation.json.
- official_test_predictions.csv dan official_test_per_class.csv.
- Confusion matrix PNG/CSV, termasuk kolom gambar ditolak.
- evidence/: sampel gambar asli hingga HOG, benar dan salah.
- LAPORAN_HASIL.html dan LAPORAN_HASIL.md.
- Pembagian data, checksum, konfigurasi, dan versi dependency.
- train_svm_hog.py untuk reproduksi.

Cache dataset, fitur, dan seluruh bobot kandidat tidak digandakan ke ZIP.
Semua prediksi test tersedia dalam CSV. Gambar bukti hanya sampel per huruf.

## Foto sendiri dan batasan

EXTERNAL_TEST_DIR opsional, dengan susunan folder A/foto.jpg, B/foto.jpg,
dan seterusnya. Foto tersebut hanya dievaluasi, tidak ikut training atau
pemilihan model. Data yang sudah dipakai debugging adalah data pengembangan,
bukan test final independen. Folder ini juga dicatat sebagai development.

Segmentasi mencari foreground, bukan pendeteksi tangan semantik.
Ruang lingkup awal: satu tangan/objek, latar polos kontras, dan cahaya cukup.
Gambar ditolak jika foreground tidak ditemukan, ukurannya tidak memenuhi
batas, atau ada beberapa foreground besar. Keputusan ini dapat salah juga.
Tidak ada jaminan semua objek bukan tangan akan ditolak.

Tidak ada CNN, MediaPipe, atau TensorFlow dalam training ini.
J/Z belum termasuk. Tidak ada jaminan accuracy 99,5% atau 100%.
Skor keputusan SVM bukan probabilitas atau confidence persen.
Model joblib belum bisa langsung digunakan oleh TFLite Flutter.
Integrasi, kalibrasi/aturan penerimaan, dan uji kamera menyusul setelah evaluasi.

## Rujukan metode

- HOG: https://scikit-image.org/docs/stable/auto_examples/features_detection/plot_hog.html
- SVM: https://scikit-learn.org/stable/modules/generated/sklearn.svm.SVC.html
- Mencegah kebocoran data: https://scikit-learn.org/stable/common_pitfalls.html
- Dataset: https://www.kaggle.com/datasets/datamunge/sign-language-mnist
