# Validasi frontend Random Forest HOG

Dokumen ini adalah panduan uji manual, bukan bukti uji HP.
Backend Random Forest HOG berjalan di perangkat menggunakan aset runtime RFH1.

1. Buka Home, Kamus, Riwayat, Progres, dan Badges. Periksa navigasi dan aset.
2. Buka Deteksi, lalu berpindah Video, Foto, Upload. Periksa kamera depan
   dan belakang, proporsi preview, serta izin kamera.
3. Ambil foto dan ambil ulang. Tekan Deteksi dan pastikan hasil Random Forest
   HOG ditampilkan serta riwayat hanya mencatat hasil yang diterima.
4. Upload satu atau beberapa foto. Periksa status prediksi, urutan hasil, dan
   riwayat untuk setiap gambar.
5. Pada Video, periksa huruf yang dikenali dan kestabilan hasil selama sesi.
6. Periksa aplikasi setelah masuk background dan dibuka kembali.

Akurasi, confidence, preprocessing HOG, dan dukungan J/Z tetap perlu divalidasi
secara terpisah pada data uji dan perangkat target.
