# Uji Vivo pada MNIST dan foto Drive

Pengujian dilakukan pada Vivo 1918, serial `33a40574`, tanggal 15 November 2026. Kode sumber mengikuti commit `60ae231` pada branch `rama`. Bobot model CNN dan model J/Z, preprocessing, serta threshold produksi tidak diubah. Tidak ada training pada tugas ini.

## Sampel test MNIST

Dipilih 100 indeks unik secara acak menggunakan seed `20261115` dari 7.172 baris `sign_mnist_test.csv`. PNG diverifikasi sama persis dengan piksel dan label CSV. Tidak ditemukan kecocokan piksel persis antara 100 sampel tersebut dan 27.455 gambar pada CSV training. Sampel mencakup 23 huruf, Q kebetulan tidak terpilih. Model sebelumnya sudah pernah dievaluasi pada split test resmi ini, sehingga hasil sekarang bukan ukuran generalisasi pada sumber baru.

| Jalur di Android | Benar diterima | Salah diterima | Kurang yakin | Ditolak detektor |
| --- | ---: | ---: | ---: | ---: |
| Model langsung, input asli 28×28 | 100 | 0 | 0 | 0 |
| Upload penuh, input asli 28×28 | 0 | 0 | 0 | 100 |
| Model langsung, input diperbesar lalu diperkecil | 100 | 0 | 0 | 0 |
| Upload penuh, gambar diperbesar menjadi 448×448 | 0 | 0 | 0 | 100 |

Model langsung melewati MediaPipe untuk memeriksa CNN secara terpisah. Ini alat diagnosis, bukan fallback aplikasi. Penolakan detektor tidak boleh disebut 100 salah klasifikasi CNN. Perbesaran gambar tidak menambah detail asli.

## Foto berwarna dari Drive

Folder yang diberikan pengguna berisi 26 foto RGB 640×640. Label mengikuti nama file. Tidak ada bukti split train/test dari folder tersebut, sehingga digunakan sebagai data evaluasi tambahan. Sebanyak 24 huruf statis dinilai. J dan Z berupa ilustrasi dengan petunjuk gerak, tidak dinilai sebagai rekaman gerakan.

| Jalur di Android | Benar diterima | Salah diterima | Kurang yakin | Ditolak detektor |
| --- | ---: | ---: | ---: | ---: |
| Upload foto RGB asli | 12 | 4 | 1 | 7 |
| Upload versi grayscale dari foto yang sama | 0 | 0 | 0 | 24 |

Pada foto RGB, 17 dari 24 melewati detektor. Yang benar dan diterima adalah A, B, E, F, H, I, L, R, S, U, V, dan Y. Kesalahan yang diterima: C menjadi O, O menjadi E, P menjadi Q, dan W menjadi V. M ditolak karena kurang yakin. D, G, K, N, Q, T, dan X tidak terdeteksi. Benar diterima terhadap seluruh foto RGB adalah 12/24 atau 50%.

Pembanding grayscale dibuat di Android dari foto yang sama dengan dimensi tetap. PNG grayscale diverifikasi memiliki kanal R, G, dan B setara. Hasil pasangan ini menunjukkan bahwa perubahan menjadi grayscale memengaruhi jalur detektor yang dipakai pada foto tersebut. Ini bukan kesimpulan bahwa semua implementasi MediaPipe pasti gagal pada grayscale. Kode produksi sudah menjalankan MediaPipe pada foto berwarna, kemudian menyiapkan grayscale untuk CNN.

## Kontrol dan batas pengujian

Tiga foto asli dari audit pengguna sebelumnya diuji secara terpisah. Ketiganya menghasilkan 21 landmark di Vivo yang sama. B terbaca B, H terbaca H, sedangkan X tetap terbaca P. Kontrol ini tidak dimasukkan ke angka MNIST atau Drive.

Batch MNIST yang diperbesar dan foto Drive memakai widget `UploadScreen` produksi dan fungsi `classifyUploadFile`, dengan pemilihan file otomatis. Pemilih galeri manual dan penyimpanan riwayat tidak dijalankan dalam batch. Semua prediksi utama berasal dari Android, bukan interpreter komputer. Aplikasi biasa sudah dipasang kembali setelah pengujian.

Foto RGB berlatar putih juga masih memiliki salah klasifikasi, sehingga background bebas belum terbukti menjadi satu-satunya penyebab kegagalan foto sebelumnya. Keberhasilan 100/100 pada MNIST tidak membuktikan model optimal untuk foto nyata. Tahap deteksi tangan dan tahap klasifikasi perlu dievaluasi terpisah sebelum mengubah konfigurasi produksi atau memutuskan fine-tuning.

Laporan HTML lengkap, 124 hasil per gambar, gambar input CNN yang benar-benar dihasilkan Android, manifest sumber, dan JSON bukti disimpan lokal di folder Downloads `Uji_Vivo_MNIST100_dan_Foto_Drive_2026-11-15`. Foto pengguna tidak disertakan ke Git.

Sumber foto tambahan: https://drive.google.com/drive/folders/18cFgSn6ePkU_srS4W2MLa5_2aAd3QOM3
