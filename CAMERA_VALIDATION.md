# Validasi aplikasi hasil merge pada HP

Dokumen ini berisi langkah pengujian manual, bukan klaim bahwa pengujian HP
sudah selesai. Angka 99,30% dalam metadata adalah hasil eksperimen dataset.

## 1. Preview dan perpindahan mode

Gunakan benda bulat atau kartu persegi sebagai pembanding. Lingkaran harus
tetap bulat dan kartu mempertahankan proporsinya; kamera tidak boleh gepeng,
miring, atau tertukar saat transisi. Preview memenuhi layar dengan crop tepi.

Periksa kamera depan dan belakang pada kondisi berikut:

1. Masuk Home → Deteksi → Video.
2. Pilih target huruf; deteksi aktif otomatis tanpa Mulai.
3. Kembali ke latihan bebas, tekan Mulai, lalu Akhiri.
4. Pindah tab Foto → Upload → Video.
5. Pindah menu Home/Kamus/Riwayat lalu kembali ke Deteksi.
6. Tekan Home Android, kembali ke aplikasi, dan coba lagi.

Pastikan tombol dan navigasi tidak mengaktifkan kamera kedua atau rekaman
bersamaan. Setelah perubahan native, lakukan stop dan run ulang sebelum
menilai perbaikan preview.

## 2. Latihan bebas dan target huruf

Pada Video, pilih latihan bebas, tekan Mulai, dan peragakan beberapa huruf
statis. Semua ujung jari harus terlihat. Tangan boleh berada di luar tengah
frame selama terlihat kamera dan dideteksi MediaPipe.

Tekan Akhiri dan periksa bahwa urutan huruf tampil di akhir, rekaman selesai,
dan satu hasil sesi masuk ke Riwayat bila terdapat huruf yang diterima. Jika
tidak ada huruf diterima, jangan menganggap sesi tersebut berhasil mengenali
tangan. Rangkaian huruf belum memiliki spasi otomatis.

Untuk target huruf, pilih huruf dan peragakan pose yang sesuai tanpa menekan
Mulai. Periksa prediksi langsung, status benar/salah, dan Reset hasil. Mode
target tidak merekam video dan tidak menambahkan setiap frame ke Riwayat.

Uji pula kamera tanpa tangan: huruf baru tidak boleh diterima hanya karena
model menebak objek atau latar. Prediksi lama dapat tetap terlihat sebagai
hasil sebelumnya; bedakan dari penambahan huruf baru.

## 3. Foto, upload, kamus, dan riwayat

- Foto: ambil foto, deteksi, lihat keyakinan model, lalu ambil ulang. Coba
  kamera depan dan belakang; hasil foto harus memiliki orientasi yang benar.
- Upload: coba satu gambar, beberapa gambar, batalkan pemilihan, dan coba
  gambar yang gagal dibaca. Periksa urutan hasil dan pesan kesalahan.
- Foto/upload: tempatkan tangan di tengah gambar. Kedua jalur ini memakai
  crop tengah dan EXIF, belum crop MediaPipe seperti jalur frame video.
- Kamus: buka seluruh 24 foto huruf. J dan Z harus dijelaskan sebagai gerakan
  yang belum dikenali model statis.
- Riwayat: lihat hasil, waktu, sumber, dan confidence; buka detail foto,
  restart aplikasi, dan pastikan data tetap ada. Uji hapus satu dan hapus
  semua, termasuk batal pada dialog konfirmasi.
- Izin: coba penolakan izin kamera dan buka kembali setelah izin diberikan.

Detail rekaman saat ini menunjukkan lokasi file, bukan pemutar video.
Penghapusan riwayat menghapus catatan; file media tidak otomatis seluruhnya
dibersihkan. Jika aplikasi/data dihapus, data lokal hilang.

## 4. Mengukur akurasi kamera

Gunakan sedikitnya tiga peserta, seluruh 24 huruf statis, dan variasi cahaya
serta latar. Contoh pengujian: `3 peserta × 24 huruf × 10 pengulangan × 3
kondisi = 2.160 percobaan`.

Tentukan batas tunggu sebelum pengujian, misalnya tiga detik setelah pose
stabil. Untuk setiap percobaan, catat huruf benar, hasil aplikasi, waktu
respons, kondisi, dan apakah tangan terdeteksi. Hasil salah maupun tidak ada
hasil sampai batas tunggu harus tetap dicatat. Jangan hanya menghitung
percobaan yang berhasil diterima aplikasi.

```text
Akurasi percobaan = jumlah percobaan benar / seluruh percobaan × 100%
```

Persentase pada mode target dihitung dari kejadian prediksi stabil yang
diterima. Percobaan tanpa hasil tidak otomatis masuk hitungan itu; karena itu
catatan manual tetap diperlukan untuk mengukur kemampuan kamera keseluruhan.

Laporkan hasil per huruf, pasangan huruf yang sering tertukar, respons yang
terlambat, jumlah gagal deteksi, model HP, kamera depan/belakang, jarak, latar,
dan cahaya. Confidence tinggi bukan bukti hasil benar.

Untuk debugging, build debug dapat menghasilkan `camera_diagnostic` pada
direktori internal aplikasi: input crop grayscale dan metadata prediksi serta
transformasi preview. Data ini membantu membedakan crop/orientasi salah dari
keterbatasan model; jangan menyebutnya sebagai bukti akurasi seluruh huruf.
