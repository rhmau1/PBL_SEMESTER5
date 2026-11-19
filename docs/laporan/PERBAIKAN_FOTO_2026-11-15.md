# Perbaikan foto dan validasi Vivo

Perbaikan dilakukan pada branch `rama` tanpa mengganti bobot CNN 24 huruf,
model J/Z, atau tampilan aplikasi. Pengujian dilakukan pada Vivo 1918
`33a40574`, tanggal 15 November 2026.

## Perubahan

- Foto yang menghasilkan nol tangan dicoba sekali lagi dengan border putih.
  Seluruh piksel sumber dipertahankan dan landmark dipetakan kembali.
  Threshold MediaPipe tetap 0,35. Landmark pada border tambahan ditolak.
- Hasil retry diperiksa terhadap foto utuh. Jika prediksi foto utuh cukup yakin
  tetapi berbeda, hasil dibatasi menjadi 59% agar tidak diterima otomatis.
- Foto dan Upload memeriksa context serta tight sebelum menerima prediksi.
  Kebijakan kamera live tidak diubah.
- Diagnostik foto dibersihkan ketika klasifikasi baru dimulai.
- Sampler Python evaluasi Colab memakai grid 4 × 4 dan pembulatan yang sama
  dengan Dart. Versi cache diperbarui. Notebook mandiri disinkronkan.

## Hasil

| Data | Konfigurasi | Benar diterima | Salah diterima | Kurang yakin | Ditolak sebelum CNN |
| --- | --- | ---: | ---: | ---: | ---: |
| Drive, 24 foto | Sebelum | 12 | 4 | 1 | 7 |
| Drive, 24 foto | Sesudah | 13 | 4 | 6 | 1 |
| Foto asli, 73 foto | Sebelum | 6 | 12 | 55 | 0 |
| Foto asli, 73 foto | Sesudah | 6 | 11 | 56 | 0 |

Pada Drive, deteksi naik dari 17 menjadi 23 dan K sekarang benar diterima
64,62%. G masih diprediksi H, tetapi ditolak pada 59% melalui pengaman retry.
Pada foto asli Q `IMG_6038.JPG`, hasil salah P yang sebelumnya diterima kini
ditolak pada 59%. Semua jawaban benar yang sebelumnya diterima tetap diterima.
Tidak ada tambahan jawaban salah yang diterima pada kedua kumpulan foto ini.

Sebanyak 100 sampel test MNIST tetap benar 100/100 saat langsung masuk CNN.
Jalur Upload tetap menolak seluruh sampel tersebut pada detektor. Empat
kontrol tanpa tangan dan tiga gambar dua tangan semuanya ditolak.

Batch 204 input memakai `UploadScreen` produksi dan `classifyUploadFile` di
Android. Pemilihan file diotomatisasi. Pemilih galeri manual dan penulisan
riwayat tidak dijalankan dalam batch. Aplikasi biasa sudah dipasang kembali.

## Verifikasi dan batas hasil

- 227 tes Flutter lulus, satu dilewati. `flutter analyze` tidak menemukan masalah.
- Tiga tes Python lulus, termasuk kecocokan piksel dengan fixture Dart untuk
  gambar persegi panjang dan crop di tepi.
- Seluruh 17 context Drive dan 73 context foto asli identik per piksel dengan
  input baseline. Baseline 73 foto berasal dari V2310, pengujian baru di Vivo 1918.
- SHA-256 kedua model tidak berubah dan model di APK sesuai dengan aset repo.
- Foto Drive dan foto asli sudah digunakan selama pengembangan, sehingga bukan
  test independen baru. Label belum disertifikasi ahli ASL.

**Masalah klasifikasi belum selesai.** C → O, O → E, P → Q, dan W → V masih
terjadi pada foto Drive. N masih gagal dideteksi. Benar diterima terhadap
seluruh foto Drive baru 13/24 atau 54,17%, bukan mendekati 100%.

Checkpoint `.keras` CNN yang sekarang belum ditemukan dalam file lokal,
riwayat Git yang diperiksa, tujuh branch remote, dan arsip training terkait. Checkpoint J/Z dan
model September yang berbeda tidak digunakan sebagai pengganti. Notebook
awal menyimpan checkpoint pada lokasi default
`MyDrive/LatihIsyarat/camera_robust_v1/final.keras` di akun yang menjalankan
training. ZIP deployment notebook itu tidak menyertakan checkpoint tersebut.
Perbaikan bobot perlu checkpoint yang benar atau pemulihan model yang
divalidasi terlebih dahulu. Tidak ada fine-tuning dalam pekerjaan ini.

Laporan HTML berisi 204 input, gambar sumber dan PNG input Android disimpan
lokal di Downloads `Perbaikan_Foto_Vivo_2026-11-15`. Foto pribadi dan laporan
HTML tidak disertakan ke Git.

Ringkasan angka, identitas model/APK dan pemeriksaan regresi ada di
[bukti JSON](bukti/PERBAIKAN_FOTO_2026-11-15.json).
