# Sumber training model 24 huruf

`MODEL_24_HURUF_COLAB.ipynb` adalah salinan utuh [notebook Colab asli](https://colab.research.google.com/drive/1vQENLLVGYwXPmr4i6WwEOCaDoy8CaY5y). Output notebook mencatat hash model yang sama dengan `assets/models/model_float16.tflite` pada aplikasi.

Model ini memakai CNN untuk 24 huruf statis selain J/Z. Training menggunakan seed 42, AdamW, batch 256, dan 18 epoch. Datanya berasal dari Sign Language MNIST serta foto ASL Hugging Face, dengan augmentasi gambar untuk meniru sebagian kondisi kamera. Hasil MNIST yang tersimpan adalah 99,986%, dengan ukuran TFLite 318,46 KiB.

Unggah notebook ke Colab untuk membaca atau menjalankannya. Output yang sudah ada merupakan catatan training sebelumnya. Notebook ini memantau test setiap epoch dan belum memisahkan validation, sehingga angka tersebut perlu dibaca sebagai hasil eksperimen historis.

Output mencatat cache 132.719 sampel. Konfigurasi notebook yang tersimpan akan membuat 265.438 sampel jika cache dibangun ulang. Konfigurasi pembuat cache lama tidak tersimpan, sehingga menjalankan dari nol tidak menjamin bobot maupun hasil yang identik. Salinan ini dipertahankan agar riwayatnya dapat diperiksa.

`riwayat_mnist/` menyimpan skrip baseline, perbandingan seed, dan eksperimen MNIST sebelum model saat ini. Notebook di sana menghasilkan model versi sebelumnya.

Identitas notebook dan model tercatat di [asal_sumber.json](asal_sumber.json). Data tersedia melalui [DATASET](../DATASET/README.md).
