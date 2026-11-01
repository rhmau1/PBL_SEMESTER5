# Training model 24 huruf

`MODEL_24_HURUF_COLAB.ipynb` adalah salinan utuh [notebook asli](https://colab.research.google.com/drive/1vQENLLVGYwXPmr4i6WwEOCaDoy8CaY5y). Outputnya mencatat hash model yang sama dengan model 318,46 KiB pada aplikasi.

CNN dilatih memakai MNIST dan foto Hugging Face, seed 42, AdamW, batch 256, serta 18 epoch. Unggah notebook ke Colab untuk membaca kode dan hasil training yang tersimpan.

Notebook lama memantau test setiap epoch dan belum memiliki validation terpisah. Output memakai cache 132.719 sampel, sedangkan konfigurasi yang tersimpan menghasilkan 265.438 sampel jika cache dibuat ulang. Menjalankannya dari nol tidak menjamin hasil yang identik. Model aplikasi tetap dipertahankan.
