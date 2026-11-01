# Dataset yang digunakan

| Folder | Isi yang disertakan | Penggunaan |
| --- | --- | --- |
| `MNIST/` | ZIP berisi CSV asli, 27.455 gambar training dan 7.172 gambar test | Training CNN sebelumnya dan evaluasi ulang model 24 huruf |
| `HUGGING_FACE/` | Parquet asli berisi 10.873 foto dengan 26 label | Sumber foto pada training CNN sebelumnya dan diagnostik terbaru pada 10.033 foto selain J/Z |
| `J_Z/` | Dataset fitur sebenarnya, 1.320 urutan landmark beserta label dan pembagian data | Training, validation, serta test GRU J/Z/OTHER |

Ekstrak ZIP MNIST untuk memperoleh dua CSV. Parquet Hugging Face menyimpan gambar dan label dalam satu tabel. File `sequence_features_and_labels.npz` berisi input GRU: 922 sampel training, 200 validation, dan 198 test. Separuh sampelnya adalah OTHER sintetis yang dibuat dari posisi tangan pada video sumber.

Di `J_Z/`, manifest mencatat asal video dan pembagian setiap sampel. `labels.json` menjelaskan urutan kelas, sedangkan `preprocessing_contract.json` menjelaskan susunan fitur.

Video J/Z mentah berjumlah 712 dengan total sekitar 3,94 GiB dan tersedia di sumber SigNN. Repositori menyertakan hasil ekstraksi yang benar-benar digunakan model, bukan video mentahnya. Notebook training mengunduh video dari sumber saat dijalankan di Colab.

Sumber resmi:

- [Sign Language MNIST](https://www.kaggle.com/datasets/datamunge/sign-language-mnist)
- [Foto ASL Hugging Face](https://huggingface.co/datasets/Marxulia/asl_sign_languages_alphabets_v03)
- [Video SigNN J/Z](https://www.kaggle.com/datasets/signnteam/asl-sign-language-alphabet-videos-j-z)

Identitas file dan hash tercatat di [sumber_dataset.json](sumber_dataset.json). CSV MNIST, parquet Hugging Face, dan fitur J/Z cocok dengan data pada hasil training yang diperiksa.
