# J/Z pada aplikasi

Menu Video memakai dua model terpisah. CNN mengenali 24 pose huruf, sedangkan GRU mengenali gerakan J dan Z dari landmark MediaPipe. Warna, kartu, navigasi, serta tema tetap menggunakan komponen aplikasi yang tersedia.

## Cara menggunakan

Untuk latihan satu huruf, pilih J atau Z pada dropdown. Tekan **Mulai gerakan**, lakukan satu gerakan lengkap dengan tangan terlihat, lalu tekan **Selesai gerakan**. Model memberikan satu keputusan. Target hanya menjadi pembanding. Jika target J tetapi hasilnya Z, aplikasi tetap menampilkan Z dan menyatakan belum sesuai target.

Untuk latihan bebas, tekan **Mulai latihan bebas**. Huruf statis tetap dikenali otomatis. Sebelum membentuk J/Z, tekan **Mulai J/Z**, lakukan satu gerakan, lalu **Selesai gerakan**. Turunkan tangan sebentar sebelum melanjutkan huruf berikutnya. Ulangi langkah ini untuk setiap J/Z. Tekan **Akhiri dan lihat hasil** untuk melihat susunan huruf seluruh sesi.

Tombol J/Z harus ditekan sebelum memperagakan hurufnya agar pose awal tidak tercatat oleh CNN. Ini pemisahan gerakan dengan tombol, bukan pemisahan otomatis berdasarkan bentuk tangan. Satu potongan hanya boleh memuat satu gerakan. Capture dibatalkan setelah 10 detik agar tidak berkembang menjadi rekaman tanpa batas.

## Hasil dan menu lain

| Bagian | Perilaku |
| --- | --- |
| Target 24 huruf statis | Deteksi otomatis, tombol Reset, tanpa menyimpan tiap frame ke riwayat |
| Target J/Z | Satu hasil per gerakan. J/Z yang diterima disimpan dengan sumber Latihan gerakan J/Z |
| Latihan bebas | Hasil statis dan gerakan disusun dalam satu sesi. Riwayat disimpan sekali setelah sesi diakhiri |
| Foto dan Upload | Tetap memakai CNN 24 huruf. Foto tidak membuktikan gerakan J/Z |
| Kamus dan Panduan | Menjelaskan penggunaan Video untuk J/Z dan Foto untuk pose statis |
| Progres | Target 26 huruf. Hanya hasil yang benar-benar disimpan masuk ke progres |
| Badges | Syarat 5, 15, 24 huruf serta streak tetap berlaku. Badge 24 huruf adalah pencapaian antara, bukan klaim sudah menyelesaikan 26 huruf |

OTHER, hasil kurang yakin, gerakan ditolak, serta capture yang dibatalkan tidak ditambahkan ke huruf atau riwayat. Jika penyimpanan gagal, hasil tetap ditampilkan dengan pesan kegagalan riwayat. Mengganti target, kamera, mode, meninggalkan halaman, atau masuk background membatalkan capture yang masih berlangsung. Hasil terlambat dari capture itu diabaikan.

## Sambungan kode

`CameraScreen` memanggil `JzRecognitionService`. Callback kamera yang sama diteruskan sebagai frame baru, dengan waktu dari Stopwatch serta rotasi tegak tanpa mirror. Tidak ada stream kamera kedua atau pengulangan landmark lama.

Jalur statis menggunakan `StaticCameraPipeline`, pembungkus CNN dan detector yang sudah dipakai. Threshold 0,60, stabilitas dua prediksi, interval deteksi 320 ms, dan interval CNN 260 ms tetap sama. File model, label 24 huruf, konfigurasi, serta preprocessing CNN tidak diubah.

Saat gerakan J/Z berlangsung, hasil CNN yang masih berjalan dibatalkan secara logis melalui nomor generasi. Setelah gerakan, tangan harus keluar dari pandangan detector sebelum prediksi statis diterima lagi. Saat menekan Akhiri, aplikasi menunggu keputusan J/Z terakhir sebelum menyusun dan menyimpan hasil sesi.

Kontrak backend lengkap ada di [BACKEND_J_Z.md](BACKEND_J_Z.md). Model dan backend Android memerlukan menjalankan ulang aplikasi, bukan hanya hot reload.

## Batas pengujian

Tes otomatis memeriksa penghubung kamera, hasil diterima atau ditolak, pembatalan, penyimpanan, serta progres. Pengujian dengan backend tiruan tidak membuktikan akurasi kamera nyata. Pengujian J/Z melalui kamera Vivo masih harus dilakukan saat perangkat tersambung. Penolakan gerakan lain juga perlu dicoba karena data OTHER saat training berupa sampel sintetis.

## Hasil validasi 2 November 2026

| Pemeriksaan | Hasil |
| --- | --- |
| `flutter analyze --no-pub` | Tidak ada masalah |
| `flutter test --no-pub --reporter expanded` | 189 lulus, 1 dilewati, 0 gagal |
| Kompilasi Android Kotlin dan Java dengan JDK 17 | Berhasil, termasuk kompilasi Dart debug |
| Tes penghubung kamera J/Z | 20 skenario lulus, termasuk urutan campuran AJBZ, hasil ditolak, ganti kamera, background, timeout, dan percobaan ulang setelah error |
| Riwayat dan progres | Hasil gerakan masuk kategori Kamera, progres menghitung 26 huruf, syarat badge lama tetap berlaku |
| Model dan jalur CNN | Hash kedua model sesuai sumber. Model, label, metadata, preprocessing CNN, serta widget preview tidak berubah |

Satu tes yang dilewati adalah inferensi TFLite native pada komputer. Tes itu memerlukan runtime C TFLite dan opsi `--dart-define=JZ_NATIVE_TEST=true`. Tes lain memakai backend tiruan untuk memeriksa alur aplikasi. Belum ada APK yang dipasang atau aplikasi yang dijalankan di HP pada tahap ini.

Path JDK Linux yang sebelumnya terkunci di `android/gradle.properties` dihapus. Pilih JDK 17 di komputer masing-masing sesuai [REQUIREMENTS.md](../../REQUIREMENTS.md). Konfigurasi model dan kamera tidak berkaitan dengan perubahan setup ini.

Untuk uji kamera, jalankan ulang aplikasi melalui `flutter run`. Coba target J dan Z masing-masing beberapa kali, termasuk saat target berbeda dari gerakan. Lalu coba urutan A, J, B, Z pada latihan bebas menggunakan tombol J/Z. Pastikan hasil sesi hanya tersimpan sekali. Coba juga tanpa tangan, gerakan lain, ganti kamera, serta masuk dan keluar aplikasi. Foto dan Upload tetap digunakan untuk huruf statis.
