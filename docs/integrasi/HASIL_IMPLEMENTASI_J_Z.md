# Hasil implementasi backend J/Z

Backend J/Z sudah ditambahkan sebagai layanan terpisah. Halaman aplikasi belum memanggilnya. Tampilan, navigasi, model CNN 24 huruf, crop, threshold, serta konfigurasi deteksi statis tetap utuh.

## Komponen

`JzRecognitionService` menerima frame satu gerakan, menjalankan MediaPipe VIDEO, membentuk fitur landmark `48 × 64`, lalu meminta prediksi GRU melalui TFLite. Hasilnya J, Z, OTHER, kurang yakin, atau penolakan kualitas clip. OTHER tidak pernah ditambahkan sebagai huruf.

Layanan menangani mulai, selesai, batal, frame yang dilewati saat sibuk, timestamp tidak valid, serta penutupan resource. Tracker baru dibuat untuk setiap clip. Pemrosesan memakai waktu akuisisi frame dan tidak mengulang landmark lama.

| File model | Ukuran |
| --- | ---: |
| CNN 24 huruf, tetap | 326.108 byte |
| GRU J/Z, tambahan | 229.672 byte |
| Total kedua file | 555.780 byte |

Hash CNN tetap `74f52ab0d6f091b37600ce65c4b7797a102c6e26112b6c2e4824483b168140bc`. Hash GRU cocok dengan hasil training. Task MediaPipe memakai asset plugin yang sudah ada dan cocok dengan hash pada kontrak training. Tidak ada dependency runtime baru.

## Validasi

| Pemeriksaan | Hasil |
| --- | --- |
| `flutter analyze --no-pub` | Tidak ada masalah |
| `flutter test --no-pub --reporter expanded` | 168 lulus, 1 dilewati |
| Kompilasi Android `:app:compileDebugKotlin` | Berhasil |
| Preprocessing Dart terhadap fungsi training Python | Seluruh 3.072 nilai fitur cocok, selisih maksimum 0,0 |
| TFLite pada fitur test J tersimpan | 43/43 benar dan diterima pada threshold 0,60 |
| TFLite pada fitur test Z tersimpan | 56/56 benar dan diterima pada threshold 0,60 |
| TFLite pada OTHER sintetis tersimpan | 99/99 benar, seluruhnya tidak menjadi huruf |
| Perbandingan Git pada kode UI dan jalur CNN | Tidak berubah |

Tes yang dilewati memerlukan DLL TFLite C pada Windows untuk menjalankan interpreter Flutter secara langsung. Pemeriksaan model aktual di atas memakai `tf.lite.Interpreter` TensorFlow 2.21, bukan transport tiruan. Rincian runtime, hash, dan hasil per kelas ada di [VALIDASI_MODEL_J_Z.json](VALIDASI_MODEL_J_Z.json).

Tes juga mencakup rotasi dan rasio frame, YUV/NV21/BGRA, stride buffer, frame kosong, urutan timestamp, retry inisialisasi, serta cancel/dispose ketika proses belum selesai. Satu tes upload lama diperbaiki agar menjalankan kedua langkah antarmuka yang diperlukan, tanpa mengubah fitur upload.

## Yang dikerjakan tim frontend

Gunakan [kontrak API dan contoh pemanggilan](BACKEND_J_Z.md). Frontend perlu meneruskan callback kamera, menentukan awal dan akhir satu gerakan, menerima hasil, serta menyambungkannya ke target latihan atau riwayat. Foto tunggal tetap menggunakan CNN 24 huruf.

Backend ini mengklasifikasikan satu gerakan per clip. Pemisahan banyak gerakan pada video latihan bebas belum diterapkan. J/Z tidak otomatis menggantikan prediksi CNN, sehingga perilaku 24 huruf tetap sama.

Belum ada pengujian kamera Vivo, build APK, atau instalasi aplikasi pada tahap ini. Hasil fitur test tersimpan tidak membuktikan akurasi kamera HP. Tujuh kegagalan ekstraksi video sumber tidak termasuk dalam 198 fitur test tersebut, dan OTHER masih berupa data sintetis.
