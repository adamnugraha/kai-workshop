# Rencana 90 hari: memulai SRE

Rencana ini sengaja kecil: satu atau dua perjalanan pengguna, dikerjakan sampai tuntas, lalu diperluas. Sesuaikan pemilik dan tanggal.

## Hari 1–30 · Ukur

| | Kegiatan | Pemilik | Tanggal | Selesai |
|---|---|---|---|---|
| 1 | Pilih 1–2 perjalanan pengguna paling kritis, tetapkan pemilik bisnis dan pemilik teknis | `[...]` | `[...]` | [ ] |
| 2 | Pasang pengukuran SLI di pintu masuk (load balancer, ingress atau API gateway) | `[...]` | `[...]` | [ ] |
| 3 | Buat satu dasbor SLI sederhana yang bisa dibuka semua orang | `[...]` | `[...]` | [ ] |
| 4 | Sepakati matriks tingkat keparahan, peran insiden dan jalur eskalasi | `[...]` | `[...]` | [ ] |
| 5 | Mulai memakai templat postmortem untuk setiap insiden Sev1 dan Sev2 | `[...]` | `[...]` | [ ] |

## Hari 31–60 · Sepakati

| | Kegiatan | Pemilik | Tanggal | Selesai |
|---|---|---|---|---|
| 6 | Tetapkan SLO dari data empat minggu (lembar kerja SLO) | `[...]` | `[...]` | [ ] |
| 7 | Tanda tangani kebijakan error budget bersama pemilik bisnis | `[...]` | `[...]` | [ ] |
| 8 | Ganti peringatan page berbasis CPU dan memori dengan peringatan burn rate SLO | `[...]` | `[...]` | [ ] |
| 9 | Tulis runbook untuk lima peringatan yang paling sering muncul | `[...]` | `[...]` | [ ] |
| 10 | Pasang OpenTelemetry di layanan paling kritis, sampai ke database dan mitra | `[...]` | `[...]` | [ ] |

## Hari 61–90 · Latih

| | Kegiatan | Pemilik | Tanggal | Selesai |
|---|---|---|---|---|
| 11 | Game day pertama di staging dengan rencana game day | `[...]` | `[...]` | [ ] |
| 12 | Rilis canary dengan analisis otomatis untuk satu layanan | `[...]` | `[...]` | [ ] |
| 13 | Irisan pertama strangler fig pada perjalanan pengguna yang sama (kartu penilaian modernisasi) | `[...]` | `[...]` | [ ] |
| 14 | Tinjauan SLO bulanan pertama bersama pemilik bisnis | `[...]` | `[...]` | [ ] |

## Tanda keberhasilan setelah 90 hari

- Setiap orang di tim tahu SLO perjalanan utama dan sisa error budget-nya hari ini.
- Peringatan yang membangunkan orang berkurang, dan setiap peringatan page punya runbook.
- Setiap insiden Sev1 dan Sev2 punya postmortem dengan tindak lanjut yang dilacak.
- Satu latihan gangguan sudah dijalankan dan temuannya sudah diperbaiki.
