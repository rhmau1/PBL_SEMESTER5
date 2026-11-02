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
| Latihan bebas | Hasil statis dan gerakan disusun dalam satu sesi. Riwayat disimpan sekali setelah sesi diakhiri. Jika aplikasi masuk background, huruf yang sudah diterima disimpan sebagai sesi terputus |
| Foto dan Upload | Tetap memakai CNN 24 huruf. Foto tidak membuktikan gerakan J/Z |
| Kamus dan Panduan | Menjelaskan penggunaan Video untuk J/Z dan Foto untuk pose statis |
| Progres | Target 26 huruf. Hanya hasil yang benar-benar disimpan masuk ke progres |
| Badges | Syarat 5, 15, 24 huruf serta streak tetap berlaku. Badge 24 huruf adalah pencapaian antara, bukan klaim sudah menyelesaikan 26 huruf |

OTHER, hasil kurang yakin, gerakan ditolak, serta capture yang dibatalkan tidak ditambahkan ke huruf atau riwayat. Jika penyimpanan gagal, hasil tetap ditampilkan dengan pesan kegagalan riwayat. Mengganti target, kamera, mode, meninggalkan halaman, atau masuk background membatalkan capture yang masih berlangsung. Hasil terlambat dari capture itu diabaikan.

## Sambungan kode

`CameraScreen` memanggil `JzRecognitionService`. Callback kamera yang sama diteruskan sebagai frame baru, dengan waktu dari Stopwatch serta rotasi tegak tanpa mirror. Tidak ada stream kamera kedua atau pengulangan landmark lama.

Jalur statis menggunakan `StaticCameraPipeline`, pembungkus CNN dan detector yang sudah dipakai. Threshold 0,60, stabilitas dua prediksi, interval deteksi 320 ms, dan interval CNN 260 ms tetap sama. File model, label 24 huruf, konfigurasi, serta preprocessing CNN tidak diubah.

Saat gerakan J/Z berlangsung, hasil CNN dan callback detector statis yang masih berjalan dibatalkan secara logis melalui nomor generasi. Setelah gerakan, tangan harus keluar dari pandangan detector sebelum prediksi statis diterima lagi. Callback lama tidak boleh dianggap sebagai bukti tangan sudah diturunkan. Saat menekan Akhiri, aplikasi menunggu keputusan J/Z terakhir sebelum menyusun dan menyimpan hasil sesi.

Persiapan model dan pembacaan hasil masing-masing dibatasi 10 detik. Pembatalan backend dibatasi 2 detik agar kontrol tidak terus terkunci. Hasil yang datang setelah pembatalan diabaikan. Timeout tidak menghentikan paksa proses native. Jika proses native belum selesai, backend dapat menolak percobaan berikutnya dengan status sibuk.

Jika masuk background, sesi dihentikan dan hanya huruf yang sudah diterima yang disimpan. Gerakan yang belum selesai dibatalkan. Saat kembali, pengguna memulai sesi baru. Jika penyimpanan gagal, aplikasi mencoba menyimpan ulang sebelum mengosongkan hasil untuk sesi baru. Mekanisme ini menangani perpindahan background normal, bukan jaminan pemulihan setelah proses dimatikan paksa oleh sistem.

Kontrak backend lengkap ada di [BACKEND_J_Z.md](BACKEND_J_Z.md). Model dan backend Android memerlukan menjalankan ulang aplikasi, bukan hanya hot reload.

## Batas pengujian

Tes otomatis memeriksa penghubung kamera, hasil diterima atau ditolak, pembatalan, penyimpanan, serta progres. Pengujian dengan backend tiruan tidak membuktikan akurasi kamera nyata. Alur aplikasi juga diuji pada Vivo, tetapi ketepatan peragaan fisik J/Z tetap perlu diukur bersama pengguna. Penolakan gerakan lain perlu dicoba karena data OTHER saat training berupa sampel sintetis.

## Validasi awal integrasi, 2 November 2026

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

## Perbaikan stabilitas, 2 November 2026

| Kasus yang direproduksi | Hasil perbaikan |
| --- | --- |
| Callback detector lama membuat AJ menjadi AJI | Callback sebelum gerakan diabaikan. Tes sekarang menghasilkan AJ |
| Huruf diterima hilang saat masuk background sebelum Akhiri | Sesi terputus disimpan sekali. Penyimpanan lambat dan gagal juga diuji |
| Persiapan atau pembacaan J/Z tidak selesai | Kontrol kembali setelah timeout. Hasil terlambat diabaikan dan retry diuji |
| Kamera ditampilkan setelah controller ditutup | Referensi preview dibersihkan dan tutup-buka kamera diurutkan |
| Background kedua saat riwayat masih disimpan | Penutupan kamera dipisahkan dari antrean penyimpanan. Kamera kedua tetap ditutup |
| Kontrol meluber pada layar 360 x 640 dengan navigasi dan inset sistem | Overlay dapat digulir sehingga seluruh tombol bisa diakses |
| Penanda hari latihan mengikuti jumlah streak | Penanda sekarang mengikuti tanggal latihan pada minggu berjalan |

Validasi kode terakhir: **200 tes lulus, 1 dilewati, 0 gagal**, termasuk **30 tes penghubung kamera/J/Z**. `flutter analyze --no-pub` tidak menemukan masalah. Tes yang dilewati memerlukan runtime C TFLite pada Windows.

Uji alur pada Vivo 1918 mencakup mulai dan selesai target J/Z, penolakan input tanpa tangan, pembatalan saat background dan pemulihan kamera, latihan bebas sampai hasil sesi, target statis otomatis, ganti kamera, Foto tanpa tangan, serta membuka dan membatalkan pemilih Upload. Log proses selama pemeriksaan tidak menunjukkan crash atau exception Flutter yang tidak ditangani. Riwayat lama tetap utuh setelah pembaruan APK dan pengujian input yang ditolak.

Hash kedua model tetap sama. Tidak ada training ulang atau perubahan threshold CNN. Hasil ini memvalidasi perbaikan alur, bukan klaim akurasi 100% pada gerakan kamera nyata. Kasus database lambat dan backend tidak merespons diuji secara terkontrol melalui tes otomatis.
