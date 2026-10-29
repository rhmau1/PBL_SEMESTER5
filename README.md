# LatihIsyarat Flutter

Project hasil penggabungan aplikasi PBL Semester 5 dengan sistem deteksi
`PBL-BAHASA-ISYARAT`. Fokus aplikasi adalah 24 huruf statis ASL, bukan
penerjemahan seluruh bahasa isyarat atau pembentukan kalimat otomatis.

Project Flutter berada langsung di `~/Documents/rhma2026/PBL_SEMESTER5`;
`pubspec.yaml`, `lib`, `android`, dan `assets` tersedia di root repository.

## Menu dan fitur

| Menu | Fungsi |
| --- | --- |
| Home | Beranda dan pintasan menuju fitur aplikasi |
| Deteksi — Video | Kamera penuh; latihan bebas dengan Mulai/Akhiri, atau latihan target huruf otomatis |
| Deteksi — Foto | Ambil foto, deteksi, dan ambil ulang |
| Deteksi — Upload | Tombol `Satu gambar` dan `Banyak gambar`; hasil per gambar mengikuti urutan pilihan |
| Kamus | Foto tangan 24 huruf statis dan petunjuk; J/Z dijelaskan sebagai gerakan |
| Riwayat | Hasil lokal beserta waktu, sumber, dan keyakinan model; detail serta hapus riwayat |

Kamera depan menjadi pilihan awal dan dapat diganti ke kamera belakang.
Pada latihan bebas, huruf yang diterima ditampilkan setelah **Akhiri** pada
bottom sheet selebar layar dengan tinggi tetap 50% layar (maksimum 85%; isi
yang lebih panjang dapat di-scroll), sehingga ukurannya sama di setiap sesi.
Satu sesi disimpan sebagai satu hasil riwayat jika terdapat huruf yang diterima.
Mode target huruf berjalan tanpa tombol Mulai dan tidak menambah setiap frame
ke Riwayat.
Rangkaian huruf belum memiliki spasi otomatis.

## Pengolahan input

Video kamera langsung:

```text
Frame kamera → MediaPipe menemukan tangan → crop persegi mengikuti tangan
→ koreksi orientasi → grayscale 28×28 → model TFLite
→ pemeriksaan keyakinan dan kestabilan → rangkaian huruf
```

Latihan bebas menerima frame melalui `startImageStream`; aplikasi tidak
merekam video dan tidak menyimpan berkas rekaman. Analisis dibatasi sekitar
setiap 260 ms dan menunggu proses sebelumnya selesai; frame tidak dipilih
acak. Deteksi tangan memiliki interval tersendiri, sehingga angka ini bukan
jaminan waktu respons. Huruf diterima setelah prediksi stabil dan memenuhi
batas keyakinan 60%. Model dengan keyakinan tinggi tetap dapat salah.

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

- File: `assets/models/model_float16.tflite`, 5.523.980 byte atau 5,268 MiB.
- Model ensemble tiga seed: 42, 123, dan 2026.
- Input `[1, 28, 28, 1]`, `float32`, grayscale bernilai 0–255.
- Normalisasi `1/255` sudah berada di model; aplikasi tidak membagi ulang.
- Output `[1, 24]`; urutan huruf mengikuti `assets/models/labels.json`.
- Model mengenali A–Y tanpa J dan Z. MediaPipe mendeteksi tangan, sedangkan
  model CNN memprediksi huruf.

Hasil eksperimen dalam metadata: akurasi dataset **99,3028%**, macro-F1
**99,3325%**. Beberapa tahap eksperimen dibandingkan pada official test set,
sehingga hasil ini bukan benchmark final yang sepenuhnya belum pernah
digunakan untuk memilih model. Akurasi kamera harus diukur terpisah.

SHA-256 model:

```text
80127bd9f692750047447500578bc8ecc3cdca466eee14037a55d53dc7ea79a9
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

Riwayat disimpan di SQLite lokal. Foto hasil kamera dan upload berada di
direktori internal aplikasi pada HP. Detail riwayat menampilkan foto bila
tersedia; tidak ada pemutar video dan tidak ada rekaman yang disimpan.
Menghapus entri riwayat tidak sama dengan menghapus semua file media.
Menghapus data aplikasi atau uninstall menghilangkan data lokal.

Application ID project ini adalah `com.example.sign_language`. Aplikasi lama
`com.example.pbl_bahasa_isyarat` memiliki penyimpanan terpisah; riwayatnya
tidak dipindahkan otomatis.

## Menjalankan dan memeriksa

```bash
cd ~/Documents/rhma2026/PBL_SEMESTER5
flutter pub get
flutter analyze
flutter test
flutter devices
flutter run
```

`flutter test` hanya menjalankan berkas di `test/`. Folder `integration_test/`
tidak dijalankan oleh perintah tersebut dan memerlukan HP Android yang
terhubung, misalnya `flutter test integration_test -d ID_PERANGKAT`.
Per 18 Oktober 2026, `flutter analyze` bersih dan `flutter test` menjalankan
88 kasus dengan 88 lulus. Workflow CI di `.github/workflows/ci.yml` menjalankan
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
CresentCrysy = Raymon Devtant 