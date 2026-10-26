# Matriks tingkat keparahan dan peran insiden

Tingkat keparahan disepakati di depan supaya tidak diperdebatkan saat panik. Bila ragu antara dua tingkat, pilih yang lebih tinggi; menurunkan tingkat lebih mudah daripada terlambat menaikkannya.

## Tingkat keparahan

| Tingkat | Definisi | Contoh | Target respons | Siapa dipanggil | Kabar ke manajemen | Postmortem |
|---|---|---|---|---|---|---|
| **Sev1** | Perjalanan utama berhenti untuk banyak pengguna, atau ada risiko data, keamanan atau keselamatan | Penjualan tiket berhenti; pembayaran gagal massal; data pelanggan bocor | 5 menit | On-call, incident commander, pemilik layanan | Setiap 30 menit | Wajib, draf dalam 5 hari kerja |
| **Sev2** | Satu fungsi terganggu sebagian, atau perjalanan utama melambat jauh | Pencarian sangat lambat; satu metode pembayaran gagal; e-tiket tertunda | 15 menit | On-call, pemilik layanan | Setiap 30 menit | Wajib |
| **Sev3** | Gangguan kecil dan ada jalan lain bagi pengguna | Fitur riwayat perjalanan error; notifikasi terlambat | Hari kerja yang sama | Tim pemilik layanan | Tidak perlu | Bila berulang |
| `[Sev4]` | `[Opsional: masalah kosmetik atau informasi]` | `[...]` | `[...]` | `[...]` | `[...]` | `[...]` |

Ganti contoh dengan perjalanan pengguna yang sebenarnya. Untuk organisasi transportasi, pertimbangkan juga dampak ke operasional di lapangan (misalnya petugas tidak bisa memeriksa tiket).

## Peran saat insiden Sev1 dan Sev2

| Peran | Tugas | Yang sengaja tidak dilakukan |
|---|---|---|
| **Incident commander (IC)** | Memimpin, menetapkan prioritas, memutuskan, menetapkan dan mengubah tingkat keparahan, menyatakan insiden selesai | Tidak ikut mengetik perintah perbaikan |
| **Operasional** | Mendiagnosis dan memulihkan; melaporkan temuan ke IC | Tidak menjawab pertanyaan manajemen langsung |
| **Komunikasi** | Kabar berkala ke manajemen, layanan pelanggan dan pemangku kepentingan lain | Tidak mengubah sistem |
| **Pencatat** | Mencatat kronologi, keputusan dan siapa melakukan apa, lengkap dengan waktu | |

Pada insiden kecil satu orang bisa memegang lebih dari satu peran, tetapi IC dan operasional sebaiknya tetap orang yang berbeda.

## Aturan koordinasi

- Satu kanal koordinasi per insiden: `[#insiden-tanggal-nama]` atau `[grup/bridge]`.
- Keputusan penting diucapkan IC dan dicatat pencatat.
- Pemulihan dulu, penyebab kemudian. Mengembalikan rilis terakhir adalah langkah pertama yang sah bila insiden mulai setelah perubahan.
- IC menyatakan insiden selesai setelah SLI kembali normal minimal `[15 menit]`.

## Templat kabar berkala

```
[Sev1/Sev2] [judul singkat] · kabar ke-[n] · [jam WIB]
Dampak saat ini : [siapa terdampak, seberapa besar]
Mulai           : [jam WIB]
Status          : [sedang diselidiki / penyebab ditemukan / pemulihan berjalan / pulih, dipantau]
Langkah berikut : [apa yang sedang dikerjakan]
Kabar berikut   : [jam WIB]
IC              : [nama]
```

## Persetujuan

| Peran | Nama | Tanggal |
|---|---|---|
| Kepala TI | `[...]` | `[...]` |
| Pemilik bisnis | `[...]` | `[...]` |
