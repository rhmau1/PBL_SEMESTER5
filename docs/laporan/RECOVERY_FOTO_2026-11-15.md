# Perbaikan Foto/Upload dan uji ulang Vivo

Checkpoint sebelum perubahan sudah ada di `origin/rama`, commit `684cdbd`. Perubahan recovery ada di `70d6abf`.

## Hasil yang terbukti

204 input diuji pada Vivo 1918 melalui `UploadScreen` dan `SignClassifier.classifyUploadFile`. Pemilihan file diotomatisasi. Dialog galeri manual dan callback penyimpanan riwayat tidak dipakai pada batch.

| Data | Sebelum: benar / salah / ragu / ditolak | Sesudah: benar / salah / ragu / ditolak |
| --- | --- | --- |
| Drive 24 foto | 13 / 4 / 6 / 1 | **15 / 4 / 4 / 1** |
| Foto asli 73 | 6 / 11 / 56 / 0 | 6 / 11 / 56 / 0 |
| MNIST test 100 melalui Upload | 0 / 0 / 0 / 100 | 0 / 0 / 0 / 100 |
| Kontrol tanpa tangan dan dua tangan | 0 / 0 / 0 / 7 | 0 / 0 / 0 / 7 |

Benar dan salah pada tabel berarti hasil yang diterima dengan confidence minimal 60%. Benar diterima terhadap seluruh foto Drive naik dari 54,17% menjadi 62,50%, atau 8,33 poin persentase. Ini bukan akurasi umum model.

- D: sebelumnya R 48,49% dan ditolak. Sekarang **D 91,36%**, diterima.
- G: sebelumnya H 59,00% dan ditolak. Sekarang **G 91,77%**, diterima.
- Tidak ada hasil benar lama yang hilang dan tidak ada tambahan hasil salah pada 97 foto berlabel yang dibandingkan.
- CNN langsung tetap benar pada 100/100 sampel test MNIST. Jalur Upload menolak gambar-gambar tersebut pada detektor. Dua hasil ini tidak boleh disamakan.

## Cara kerja perubahan

Hasil yang sudah diterima oleh jalur utama dipertahankan. Jika hasil Foto/Upload masih di bawah 60%, aplikasi dapat menyiapkan tampilan tambahan, dengan syarat:

1. MediaPipe sudah memvalidasi satu tangan dan menghasilkan 21 landmark.
2. Latar tepi cukup seragam. Persentil 90 deviasi luminance terhadap median tepi maksimal 8 pada rentang 0–255.
3. Komponen foreground terbesar berdasarkan kontras memiliki luas 1–70% gambar dan memuat landmark MediaPipe, dengan toleransi 2% sisi terpanjang komponen.
4. Foto utuh dan dua crop tambahan sepakat pada huruf yang sama. Confidence masing-masing minimal 80%.

Jika semua syarat lolos, skor ketiga tampilan dirata-rata. Nama file dan target tidak masuk keputusan. Pembentukan crop tambahan mengikuti geometri kotak foreground notebook lama, tetapi tidak diklaim identik dengan implementasi OpenCV. Proses foreground memakai `compute` agar tidak memblokir UI.

Ketiga tampilan tidak independen. Context dan tight dapat identik jika ukuran keduanya dibatasi sisi foto, seperti pada D. Kesepakatan dan confidence tinggi tetap bukan jaminan huruf benar.

Jalur kamera live, tampilan aplikasi, dan bobot model CNN maupun J/Z tidak diganti. Jalur tambahan hanya berlaku untuk klasifikasi Foto/Upload yang belum yakin.

## Validasi

- 236 tes Flutter lulus, satu dilewati. Tes tambahan mencakup perpindahan data melalui isolate, penolakan latar bertekstur, objek lain, landmark tidak valid, dan konsensus yang lemah atau berbeda.
- `flutter analyze --no-pub` bersih. Tiga tes Python preprocessing lama lulus.
- 46 input utama Drive dan 146 input utama foto asli cocok persis per piksel dengan baseline Android.
- Seluruh 18 input recovery Android cocok persis per piksel dengan rekonstruksi Dart pada komputer.
- Kedua model dalam APK aplikasi biasa cocok dengan aset repo. Aplikasi biasa sudah dipasang kembali setelah runner pengujian.

Ringkasan bukti mesin: [verifikasi recovery](bukti/recovery_foto_vivo_20261115.json).

## Batas hasil dan pekerjaan berikutnya

Empat kesalahan Drive masih diterima: C → O, O → E, P → Q, W → V. N masih gagal deteksi. M/Q/T/X masih kurang yakin. Tidak ada perbaikan pada 73 foto asli dengan latar bebas karena tidak lolos syarat latar polos.

Mengganti seluruh preprocessing dengan notebook lama ditolak karena merusak hasil yang sudah benar. Recovery dengan syarat lebih longgar juga ditolak karena dapat meloloskan M sebagai O.

Foto Drive dan foto asli dipakai selama pengembangan, sehingga bukan test independen baru. Target mengikuti nama file Drive dan catatan urutan pengambilan foto asli, belum disertifikasi ahli ASL. Tidak ada foto evaluasi yang dimasukkan ke training, dan tidak ada training bobot baru pada perubahan ini.

Notebook evaluasi Python masih mencerminkan jalur crop utama, belum recovery Foto/Upload ini. Hasil notebook tidak boleh disebut identik dengan keputusan akhir mobile setelah perubahan.

Laporan HTML dengan seluruh foto dan input Android berada pada komputer pelaksana di `C:/Users/syahr/Downloads/Perbaikan_Recovery_Foto_Vivo_2026-11-15/LAPORAN_PERBAIKAN_DAN_UJI_ULANG_VIVO.html`. Foto pribadi tidak ditambahkan ke Git.
