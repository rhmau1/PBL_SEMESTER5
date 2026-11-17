# Evaluasi preprocessing foto nyata

Pengujian dilakukan pada Vivo Y17s / V2310 menggunakan 73 foto untuk 24 huruf statis. Ada empat foto B dan tiga foto per huruf lainnya. Target ditetapkan dari urutan pengambilan dan inspeksi awal, belum disertifikasi ahli ASL. Model CNN 326.108 byte dan model gerakan J/Z tidak dilatih atau diganti.

## Perubahan yang dipakai

- Foto, Upload, YUV, dan BGRA memakai grid sampling crop yang sama, yaitu 4 × 4 sampel per piksel keluaran.
- Koordinat sampling kamera mengikuti rotasi dan mirror tanpa memutar landmark dua kali. Pembacaan piksel memperhitungkan stride.
- Konversi luminance dilakukan sekali. Titik pengambilan warna padding diseragamkan pada tepi gambar.
- Crop persegi, padding context 1,60 dan tight 1,40, minimum sisi 0,28 dan 0,22 dipertahankan. Alternatif crop/padding diuji dan belum terbukti lebih baik.
- Input tetap float32 `[1, 28, 28, 1]`, grayscale 0–255. Normalisasi `/255` tetap di dalam model.

## Hasil Android

| Pengukuran | Sebelum | Konfigurasi utama baru | Eksperimen dua orientasi |
| --- | ---: | ---: | ---: |
| Benar dan diterima | 6 | 6 | 13 |
| Salah dan diterima | 12 | 12 | 0 |
| Ditolak karena kurang yakin | 55 | 55 | 60 |
| Gagal deteksi/proses | 0 | 0 | 0 |
| Kandidat teratas sesuai target tanpa ambang | 16 | 15 | 27 |

Penyamaan input belum meningkatkan jumlah jawaban benar yang diterima. Seluruh enam foto yang benar diterima sebelumnya tetap benar diterima. Perubahan top-1 dari 16 menjadi 15 terjadi pada kelompok prediksi yang tidak diterima. Jangan menyebut hasil ini sebagai peningkatan akurasi.

Eksperimen merata-ratakan skor crop normal dan mirror. Pada input MNIST standar, jumlah jawaban benar yang lolos ambang 60% turun dari 7.170 menjadi 3.016. Kandidat top-1 benar turun dari 7.171 menjadi 7.163 dari 7.172 input. Pengujian ini hanya menilai aturan orientasi pada input yang sudah disiapkan, bukan seluruh jalur Upload. Karena regresi penolakan tersebut, eksperimen **tidak aktif secara default**.

Untuk menjalankan opsi eksperimen secara sengaja:

```powershell
flutter run --dart-define=STATIC_ORIENTATION_ENSEMBLE=true
```

Jalankan biasa tanpa flag untuk konfigurasi utama. Mode eksperimen menggunakan dua sampai empat inferensi per gambar, sehingga biaya inferensinya lebih besar.

## Validasi dan batasannya

- Tes proyek akhir: 221 lulus, 1 dilewati. Analisis kode: tidak ada masalah.
- Tes sintetis membuktikan piksel input identik antara file, YUV, dan BGRA untuk empat rotasi, dua kondisi mirror, crop tepi, dan row stride berpadding. Ini tidak berarti RGB dan YUV dari kamera nyata pasti identik secara fotometrik.
- Masing-masing konfigurasi diuji pada seluruh 73 foto lewat widget UploadScreen dan classifier produksi di Android. Pemilihan file batch diotomatisasi, bukan mengetuk galeri 73 kali.
- Semua PNG input baru berhasil diambil dari Android. Replay pada komputer cocok untuk 73/73 label, dengan selisih skor maksimum sekitar 0,0000016.
- Tiga foto diperiksa melalui pemilih galeri Android asli. Nama cache dan metadata berubah, tetapi identitas MediaStore dan piksel gambar setelah orientasi cocok dengan sumber.
- Aplikasi biasa sudah dipasang kembali. Satu foto B diuji melalui galeri pada aplikasi biasa, menghasilkan B 93,4% dan masuk Riwayat. Menu Video, Foto, dan Upload bisa dibuka. Akurasi peragaan kamera live belum diukur ulang.
- Foto asli dan bobot kedua model tidak berubah. Foto pribadi dan laporan HTML lengkap disimpan lokal, tidak disertakan dalam Git.

73 foto ini merupakan data evaluasi pengembangan karena sudah dipakai memilih konfigurasi. Hasilnya belum menjadi ukuran generalisasi pada orang atau sesi baru. Penyamaan preprocessing memperbaiki konsistensi jalur input, tetapi belum menyelesaikan kelemahan model pada foto nyata. Peningkatan selanjutnya perlu diuji dengan foto baru. Jika gambar yang telah disiapkan dengan benar tetap salah, fine-tuning menggunakan data nyata yang terpisah berdasarkan orang atau sesi menjadi langkah berikutnya.
