# Validasi frontend RAMA-SVM-HOG

Dokumen ini adalah panduan uji manual, bukan bukti uji HP.
Backend ML belum terpasang pada branch ini.

1. Buka Home, Kamus, Riwayat, Progres, dan Badges. Periksa navigasi dan aset.
2. Buka Deteksi, lalu berpindah Video, Foto, Upload. Periksa kamera depan
   dan belakang, proporsi preview, serta izin kamera.
3. Ambil foto dan ambil ulang. Tekan Deteksi: harus tampil pesan backend
   SVM-HOG belum terpasang, tanpa hasil huruf atau catatan keberhasilan baru.
4. Upload satu atau beberapa foto. Setiap foto menampilkan status backend
   belum tersedia, tanpa prediksi buatan atau riwayat keberhasilan.
5. Pada Video, Mulai atau pemilihan target belum menjalankan pengenalan.
   Pesan backend belum tersedia harus muncul dan navigasi tetap bisa dipakai.
6. Periksa aplikasi setelah masuk background dan dibuka kembali.

Akurasi, confidence, segmentasi, HOG, SVM, dan dukungan J/Z baru dapat diuji
setelah backend serta model tersedia. Tidak ada klaim akurasi pada tahap ini.
