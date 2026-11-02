# LatihIsyarat Flutter

Project hasil penggabungan aplikasi PBL Semester 5 dengan sistem deteksi
`PBL-BAHASA-ISYARAT`. Aplikasi mengenali 24 pose huruf statis ASL serta
gerakan J dan Z. Rangkaian huruf belum membentuk kalimat atau spasi otomatis.

Project Flutter berada langsung di root repository, misalnya `D:\PBL_SEMESTER5`;
`pubspec.yaml`, `lib`, `android`, dan `assets` tersedia di root repository.

## Menu dan fitur

| Menu | Fungsi |
| --- | --- |
| Home | Beranda dan pintasan menuju fitur aplikasi |
| Deteksi — Video | Latihan bebas dan target A–Z. Pose statis otomatis, J/Z dengan Mulai/Selesai gerakan |
| Deteksi — Foto | Ambil foto, deteksi, dan ambil ulang |
| Deteksi — Upload | Tombol `Satu gambar` dan `Banyak gambar`; hasil per gambar mengikuti urutan pilihan |
| Kamus | Foto tangan 24 huruf statis dan petunjuk; J/Z dijelaskan sebagai gerakan |
| Riwayat | Hasil lokal beserta waktu, sumber, dan keyakinan model; detail serta hapus riwayat |
| Progres dan Badges | Pencatatan latihan dari riwayat, target 26 huruf, dan pencapaian belajar |

Kamera depan menjadi pilihan awal dan dapat diganti ke kamera belakang.
Pada latihan bebas, huruf yang diterima ditampilkan setelah **Akhiri** pada
panel hasil yang dapat di-scroll.
Satu sesi disimpan sebagai satu hasil riwayat jika terdapat huruf yang diterima.
Target huruf statis berjalan otomatis tanpa menyimpan setiap frame ke Riwayat.
Target J/Z memakai **Mulai gerakan** lalu **Selesai gerakan**. Satu hasil J/Z
yang diterima disimpan sekali. Dalam latihan bebas, tekan **Mulai J/Z** sebelum
memperagakan gerakan, lalu **Selesai gerakan**. Turunkan tangan sebentar sebelum
melanjutkan huruf berikutnya. Pemisahan gerakan masih menggunakan tombol.
Rangkaian huruf belum memiliki spasi otomatis.

## Pengolahan input

Jalur 24 huruf statis:

```text
Frame kamera → MediaPipe menemukan tangan → crop persegi mengikuti tangan
→ koreksi orientasi → grayscale 28×28 → model TFLite
→ pemeriksaan keyakinan dan kestabilan → rangkaian huruf
```

Latihan bebas merekam video melalui `startVideoRecording` sambil menerima
frame pada callback `onAvailable`. Rekaman disimpan saat sesi diakhiri.
Target statis memakai `startImageStream` tanpa merekam. Analisis CNN dibatasi sekitar
setiap 260 ms dan menunggu proses sebelumnya selesai; frame tidak dipilih
acak. Deteksi tangan memiliki interval tersendiri, sehingga angka ini bukan
jaminan waktu respons. Huruf diterima setelah prediksi stabil dan memenuhi
batas keyakinan 60%. Model dengan keyakinan tinggi tetap dapat salah.

J/Z memakai frame baru dari kamera yang sama. MediaPipe menghasilkan urutan
landmark XYZ, kemudian GRU memberikan satu keputusan untuk satu gerakan lengkap.
CNN tidak mencatat huruf selama gerakan tersebut. Hasil OTHER, kurang yakin,
atau gerakan yang ditolak tidak dimasukkan ke rangkaian huruf. Capture gerakan
dibatalkan setelah 10 detik. Alur lengkap ada di
[panduan integrasi J/Z](docs/integrasi/FRONTEND_J_Z.md).

Foto kamera dan Upload memakai MediaPipe Hand Landmarker mode IMAGE melalui
`classifyFile`: EXIF dikoreksi, tangan dicari pada seluruh gambar,
lalu crop persegi mengikuti tangan sebelum CNN dijalankan. Foto tanpa tangan
atau dengan lebih dari satu tangan tidak diterima sebagai huruf. Model deteksi
tangan memakai asset yang sudah disertakan package `hand_landmarker`, tanpa
unduhan tambahan. Pada Upload, `Banyak gambar` memproses gambar sesuai urutan
pilihan. Hasil dengan keyakinan di bawah 60% ditampilkan sebagai
`Belum yakin` dan tidak disimpan ke Riwayat. Upload video bukan fitur yang
tersedia.

Preview digambar oleh `CameraPreview` di dalam `OverflowBox`/`FittedBox`
dengan `BoxFit.cover`, sehingga memenuhi layar dan tepinya dapat terpotong.
Bridge geometri CameraX native tetap tersedia, tetapi hanya dipakai untuk
metadata diagnostik `camera_diagnostic`, bukan untuk menggambar preview.
Setelah mengubah kode native, hentikan aplikasi dan jalankan ulang; hot reload
tidak memperbarui bridge tersebut.

## Model dan data

- CNN: `assets/models/model_float16.tflite`, 326.108 byte, sekitar 318,46 KiB.
- Input `[1, 28, 28, 1]`, `float32`, grayscale bernilai 0–255.
- Normalisasi `1/255` sudah berada di model; aplikasi tidak membagi ulang.
- Output `[1, 24]`; urutan huruf mengikuti `assets/models/labels.json`.
- CNN mengenali 24 huruf statis tanpa J dan Z.
- GRU: `assets/models/jz/model_float16.tflite`, 229.672 byte, sekitar 224,29 KiB.
  Input `[1, 48, 64]`, output J, Z, OTHER. MediaPipe mendeteksi tangan untuk
  kedua jalur. Kedua model klasifikasi berjumlah 555.780 byte, belum termasuk
  asset detektor tangan dan komponen aplikasi.

Metadata CNN mencatat akurasi MNIST bersih **99,986%**. Untuk GRU, 99 dari 99
video uji yang tangannya berhasil dideteksi dikenali benar. Jika 7 kegagalan
deteksi ikut dihitung, hasilnya 99 dari 106 video atau **93,40%**. Angka ini
berasal dari pengujian dataset, bukan pengukuran akurasi kamera HP.

SHA-256 CNN:

```text
74f52ab0d6f091b37600ce65c4b7797a102c6e26112b6c2e4824483b168140bc
```

Foto kamus 24 huruf berasal dari `amer_sign2.png` pada dataset
[Sign Language MNIST](https://www.kaggle.com/datasets/datamunge/sign-language-mnist).
Sumber dan lisensi foto dicatat di [THIRD_PARTY_ASSETS.md](THIRD_PARTY_ASSETS.md).
Script pembuat ulang foto tersedia di `tooling/generate_sign_reference_images.py`
beserta gambar sumbernya; alat opsional ini memakai Python dan Pillow.
Model MediaPipe Hand Landmarker disertakan oleh dependency `hand_landmarker`.
Setelah dependency terpasang dan aplikasi dibangun, prediksi berjalan di HP
tanpa mengirim gambar ke server.

## Penyimpanan

Riwayat disimpan di SQLite lokal. Foto hasil kamera, upload, dan rekaman
latihan bebas berada di direktori internal aplikasi pada HP. Detail riwayat
menampilkan foto jika tersedia dan lokasi berkas video. Belum ada pemutar
video di halaman riwayat. Target J/Z
menyimpan huruf dan keyakinan tanpa berkas video.
Menghapus entri riwayat tidak sama dengan menghapus semua file media.
Menghapus data aplikasi atau uninstall menghilangkan data lokal.

Application ID project ini adalah `com.example.sign_language`. Aplikasi lama
`com.example.pbl_bahasa_isyarat` memiliki penyimpanan terpisah; riwayatnya
tidak dipindahkan otomatis.

## Menjalankan dan memeriksa

```powershell
cd D:\PBL_SEMESTER5
flutter pub get
flutter analyze
flutter test
flutter devices
flutter run
```

`flutter test` hanya menjalankan berkas di `test/`. Folder `integration_test/`
tidak dijalankan oleh perintah tersebut dan memerlukan HP Android yang
terhubung, misalnya `flutter test integration_test -d ID_PERANGKAT`.
Hasil validasi integrasi dicatat di
[panduan integrasi J/Z](docs/integrasi/FRONTEND_J_Z.md).
Workflow CI di `.github/workflows/ci.yml` menjalankan
`flutter analyze` dan `flutter test` pada Ubuntu dengan Flutter 3.47.5.

Panduan setup tersedia di [REQUIREMENTS.md](REQUIREMENTS.md).
Ikuti [CAMERA_VALIDATION.md](CAMERA_VALIDATION.md) untuk pengujian HP.
Catatan penggabungan tersedia di [MERGE_NOTES.md](MERGE_NOTES.md).
Tes otomatis memeriksa logika dan pengolahan data; tes tersebut tidak
membuktikan bahwa prediksi semua huruf di kamera nyata sudah akurat.

# Link Figma :
https://www.figma.com/design/SewQENN5995xunTwIdynXo/Sign-Language----F?node-id=0-1&t=NdBmrhNT66jatJ47-0

# Link Dataset yang digunakan untuk training model :
https://huggingface.co/datasets/Marxulia/asl_sign_languages_alphabets_v03
https://www.kaggle.com/datasets/datamunge/sign-language-mnist

# Link percobaan training : 
https://github.com/SahrulRamadhani29/Sign-Language_Machine-Learning
https://github.com/rhmau1/PBL_SEMESTER5

# User github :
rhmau1 = Fijriati Rahmatur Rizqi
silvatria = Silva Tria Alfares
SahrulRamadhani29 = Sahrul Ramadhani
Ariqq16 = Mohammad Ariq Baihaqi
CresentCrysy = Raymon Devtant
