# Kartu penilaian modernisasi

Kartu ini membantu memilih **fungsi pertama** yang dipisahkan dari sistem lama. Modernisasi tidak perlu sekaligus: mulai dari fungsi yang paling kritis bagi pengguna dan paling sering menjadi sumber gangguan, lalu pindahkan satu per satu dengan pola strangler fig.

## 1. Daftar fungsi

Isi satu baris per fungsi bisnis (bukan per server). Skor 1 = baik, 3 = buruk. Total tertinggi adalah kandidat pertama.

| Fungsi | Dampak ke pengguna bila mati | Frekuensi gangguan 12 bulan | Beban saat puncak | Ketergantungan eksternal tanpa perlindungan | Sulitnya rilis | Total |
|---|---|---|---|---|---|---|
| `[Pemesanan dan pembayaran]` | `[3]` | `[3]` | `[3]` | `[3]` | `[2]` | `[14]` |
| `[Pencarian jadwal]` | `[...]` | `[...]` | `[...]` | `[...]` | `[...]` | `[...]` |
| `[...]` | `[...]` | `[...]` | `[...]` | `[...]` | `[...]` | `[...]` |

## 2. Pemeriksaan per aplikasi

Jawab untuk aplikasi atau fungsi kandidat. Setiap jawaban "tidak" adalah batas atas ketersediaan yang perlu diperbaiki lewat arsitektur, bukan lewat kerja lebih keras.

| Area | Pertanyaan | Ya / Tidak | Catatan |
|---|---|---|---|
| Titik kegagalan tunggal | Apakah aplikasi tetap melayani bila satu server atau satu zona mati? | | |
| Database | Apakah ada replika dengan failover otomatis, dan sudah pernah diuji? | | |
| Rilis | Bisakah rilis dilakukan tanpa menghentikan layanan? | | |
| Rilis | Bisakah rilis dibatalkan dalam kurang dari 5 menit? | | |
| Rilis | Apakah ada rilis bertahap (canary) dengan pemeriksaan otomatis? | | |
| Lonjakan | Apakah ada antrean atau ruang tunggu untuk permintaan di atas kapasitas? | | |
| Lonjakan | Apakah data yang sering dibaca dilayani dari cache? | | |
| Lonjakan | Bisakah kapasitas ditambah otomatis? | | |
| Ketergantungan | Apakah setiap panggilan ke sistem lain punya batas waktu? | | |
| Ketergantungan | Apakah ada circuit breaker untuk mitra eksternal? | | |
| Ketergantungan | Apakah pekerjaan yang tidak harus seketika diproses lewat antrean? | | |
| Data | Apakah transaksi pendek (tidak menahan kunci sambil memanggil sistem lain)? | | |
| Data | Apakah ada kunci idempotensi untuk pembayaran dan permintaan yang bisa diulang? | | |
| Observability | Apakah SLI diukur dari sisi pengguna? | | |
| Observability | Apakah ada trace dari pintu masuk sampai database dan mitra? | | |
| Operasional | Apakah ada runbook untuk gangguan yang paling sering terjadi? | | |

## 3. Rencana irisan pertama

| Butir | Isi |
|---|---|
| Fungsi yang dipisahkan | `[...]` |
| Alasan dipilih | `[skor tertinggi, dampak bisnis, data gangguan]` |
| Pola pengalihan trafik | `[API gateway / ingress / feature flag]` |
| Data: dibagi atau disalin | `[...]` |
| SLO sejak hari pertama | `[tautan lembar kerja SLO]` |
| Cara kembali ke sistem lama bila gagal | `[...]` |
| Ukuran keberhasilan | `[misalnya error saat lonjakan turun dari X% ke Y%; waktu rilis dari jam ke menit]` |
| Target waktu | `[...]` |
