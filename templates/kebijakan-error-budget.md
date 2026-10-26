# Kebijakan error budget: `[nama layanan]`

| | |
|---|---|
| Versi | `[1.0]` |
| Berlaku sejak | `[tanggal]` |
| Pemilik dokumen | `[nama, jabatan]` |
| Ditinjau | Setiap kuartal, atau setelah insiden Sev1 |

## 1. Tujuan

Kebijakan ini menetapkan apa yang dilakukan tim ketika keandalan `[nama layanan]` mulai mengecewakan pengguna. Kebijakan disepakati di depan supaya keputusan menunda fitur tidak lagi terasa sebagai pilihan pribadi tim TI, dan supaya keandalan diperlakukan sebagai fitur yang punya target dan anggaran.

## 2. SLO yang dicakup

| SLO | Target | Jendela | Error budget | Dasbor |
|---|---|---|---|---|
| `[Ketersediaan pemesanan]` | `[99,9%]` | 30 hari bergulir | `[43 menit / 0,1% permintaan]` | `[tautan]` |
| `[Latensi pemesanan di bawah 500 ms]` | `[99%]` | 30 hari bergulir | `[1% permintaan]` | `[tautan]` |
| `[Penerbitan e-tiket]` | `[99,9%]` | 30 hari bergulir | `[0,1% upaya pembayaran]` | `[tautan]` |

Error budget dihitung dari data pengukuran, bukan dari laporan manual. Bila pengukuran sendiri rusak, waktu tanpa data dihitung sebagai `[terpakai / tidak dihitung]` (pilih satu dan tulis di sini).

## 3. Aturan berdasarkan sisa error budget

| Sisa error budget | Aturan rilis | Fokus tim | Yang memutuskan pengecualian |
|---|---|---|---|
| Di atas 50% | Rilis normal sesuai jadwal | Fitur baru | Pemimpin tim |
| 25% sampai 50% | Rilis wajib lewat canary atau rilis bertahap; rilis besar perlu persetujuan | Fitur dan perbaikan keandalan seimbang | `[Kepala pengembangan]` |
| Di bawah 25% | Hanya perbaikan bug, perbaikan keandalan dan rilis darurat | Perbaikan keandalan | `[Kepala TI]` |
| Habis | Bekukan rilis fitur sampai SLO kembali ke target selama `[7 hari]` berturut-turut | Postmortem dan tindak lanjut | `[Kepala TI bersama pemilik bisnis]` |

Selalu diizinkan, berapa pun sisa error budget: perbaikan keamanan, perbaikan yang menaikkan keandalan, dan perubahan yang diwajibkan regulasi.

## 4. Kewajiban saat jatah menipis

- Satu insiden yang memakai lebih dari **20%** error budget dalam satu jendela wajib dibuatkan postmortem, apa pun tingkat keparahannya.
- Tindak lanjut postmortem berprioritas tinggi masuk sprint berikutnya, sebelum fitur baru.
- Bila jatah habis dua jendela berturut-turut, tim dan pemilik bisnis meninjau ulang: apakah target terlalu tinggi, atau arsitektur perlu diubah.

## 5. Gangguan dari pihak lain

Gangguan yang disebabkan pihak ketiga (misalnya mitra pembayaran) atau layanan internal lain **tetap dihitung**, karena pengguna tetap merasakannya. Bila satu pihak memakai sebagian besar jatah secara berulang, tindak lanjutnya berupa perubahan desain (timeout, circuit breaker, antrean, penyedia cadangan) atau pembicaraan kontrak, bukan pengecualian dari hitungan.

## 6. Eskalasi

Bila ada ketidaksepakatan tentang penerapan kebijakan ini, keputusan diambil oleh `[Kepala TI]` dan `[pemilik bisnis]` dalam `[2 hari kerja]`. Keputusan dan alasannya dicatat di `[tautan]`.

## 7. Tinjauan

Kebijakan ditinjau setiap kuartal dengan melihat: berapa kali setiap tingkat aturan terpicu, apakah aturan itu dijalankan, dan apakah pengguna merasakan perbaikan.

## 8. Persetujuan

| Peran | Nama | Tanggal | Tanda tangan |
|---|---|---|---|
| Pemilik bisnis | `[...]` | `[...]` | |
| Kepala pengembangan aplikasi | `[...]` | `[...]` | |
| Kepala operasional TI / SRE | `[...]` | `[...]` | |
