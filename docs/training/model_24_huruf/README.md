# Training model 24 huruf

`MODEL_24_HURUF_COLAB.ipynb` memuat kode lengkap dari [notebook asli](https://colab.research.google.com/drive/1vQENLLVGYwXPmr4i6WwEOCaDoy8CaY5y) untuk model CNN 24 huruf berukuran 318,46 KiB pada aplikasi. Output tersimpan dikosongkan. Bukti MNIST dan J/Z tersedia di [laporan](../../laporan/HASIL_TRAINING_2026-11-01.md).

CNN dilatih memakai Sign Language MNIST dan tambahan foto Hugging Face, seed 42, AdamW, batch 256, serta 18 epoch. Unggah notebook ke Colab untuk menjalankan kode training lengkap.

Notebook lama memantau test setiap epoch dan belum memiliki validation terpisah. Run terdokumentasi memakai cache 132.719 sampel, sedangkan konfigurasi yang tersimpan menghasilkan 265.438 sampel jika cache dibuat ulang. Menjalankannya dari nol tidak menjamin hasil yang identik. Model aplikasi tetap dipertahankan.
