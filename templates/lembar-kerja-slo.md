# Lembar kerja SLO

Satu lembar untuk satu perjalanan pengguna. Isi dari atas ke bawah; setiap bagian bergantung pada bagian sebelumnya.

## 1. Perjalanan pengguna

| Butir | Isi | Contoh (RelNusa) |
|---|---|---|
| Nama perjalanan | `[...]` | Pesan dan bayar tiket |
| Siapa penggunanya | `[...]` | Penumpang di aplikasi dan situs |
| Apa arti "berhasil" bagi pengguna | `[...]` | Kursi terkunci dan e-tiket terbit |
| Pemilik bisnis | `[...]` | Kepala produk penjualan tiket |
| Pemilik teknis | `[...]` | Tim platform pemesanan |
| Layanan yang terlibat | `[...]` | Gateway, booking, payment worker, bank |
| Waktu paling kritis | `[...]` | Pembukaan penjualan tiket hari raya |

## 2. SLI: apa yang diukur

Rumus SLI selalu **kejadian baik ÷ semua kejadian**, diukur sedekat mungkin dengan pengguna.

| SLI | Kejadian baik | Semua kejadian | Diukur di | Contoh query |
|---|---|---|---|---|
| Ketersediaan | Permintaan tanpa error server (bukan 5xx) | Semua permintaan | Load balancer atau ingress | `sum(rate(traefik_router_requests_total{code!~"5.."}[5m])) / sum(rate(traefik_router_requests_total[5m]))` |
| Latensi | Permintaan selesai di bawah `[500 ms]` | Semua permintaan | Load balancer atau ingress | bucket histogram `le="0.5"` dibagi jumlah permintaan |
| Penyelesaian perjalanan | `[Pembayaran berhasil, e-tiket terbit]` | `[Semua upaya pembayaran]` | Layanan yang menyelesaikan perjalanan | `payment_attempts_total{outcome="success"}` dibagi semua upaya |
| `[...]` | `[...]` | `[...]` | `[...]` | `[...]` |

Pertanyaan pemeriksa:
- Apakah SLI ini turun saat pengguna benar-benar terdampak? Coba uji dengan data insiden yang lalu.
- Apakah SLI ini tetap diam saat pengguna tidak terdampak (misalnya CPU tinggi tapi semua permintaan cepat)?
- Apa yang **tidak** tertangkap? Contoh: bila worker pembayaran mati, tidak ada upaya pembayaran, sehingga SLI penyelesaian tidak bergerak. Untuk itu pantau juga usia antrean.

## 3. Data saat ini

Ukur minimal empat minggu sebelum menetapkan target.

| SLI | Minggu 1 | Minggu 2 | Minggu 3 | Minggu 4 | Terburuk |
|---|---|---|---|---|---|
| `[...]` | `[...]` | `[...]` | `[...]` | `[...]` | `[...]` |

## 4. SLO: target

Aturan praktis: tetapkan sedikit di bawah kinerja terburuk yang masih bisa diterima pengguna, bukan setinggi mungkin. Setiap tambahan satu angka sembilan biasanya butuh perubahan arsitektur, bukan sekadar kerja lebih keras.

| SLI | Target | Jendela | Error budget per jendela |
|---|---|---|---|
| `[...]` | `[99,9%]` | 30 hari bergulir | `[43 menit, atau 1 dari setiap 1.000 permintaan]` |

### Tabel bantu: target dan jatah gangguan

| Target | Jatah per 30 hari (waktu) | Jatah per 1 juta permintaan |
|---|---|---|
| 99% | 7 jam 12 menit | 10.000 permintaan |
| 99,5% | 3 jam 36 menit | 5.000 permintaan |
| 99,9% | 43 menit 12 detik | 1.000 permintaan |
| 99,95% | 21 menit 36 detik | 500 permintaan |
| 99,99% | 4 menit 19 detik | 100 permintaan |

Rumus: jatah waktu = (1 − target) × 43.200 menit. Jatah permintaan = (1 − target) × jumlah permintaan dalam jendela.

## 5. Peringatan berbasis burn rate

Burn rate = laju error saat ini ÷ laju error yang diizinkan. Burn rate 1 berarti jatah habis tepat di akhir jendela 30 hari.

| Jenis | Burn rate | Jendela panjang | Jendela pendek | Jatah terpakai saat menyala | Jatah habis dalam | Dikirim ke |
|---|---|---|---|---|---|---|
| Page | 14,4 | 1 jam | 5 menit | 2% | sekitar 2 hari | On-call, langsung |
| Page | 6 | 6 jam | 30 menit | 5% | 5 hari | On-call, langsung |
| Tiket | 3 | 1 hari | 2 jam | 10% | 10 hari | Antrean tim, jam kerja |
| Tiket | 1 | 3 hari | 6 jam | 10% | 30 hari | Antrean tim, jam kerja |

Peringatan menyala bila **kedua** jendela melewati ambang. Ambang error untuk SLO 99,9% dengan burn rate 14,4 adalah 14,4 × 0,1% = 1,44% permintaan gagal. Sumber: Google, *The Site Reliability Workbook*, bab 5. Alat seperti [Sloth](https://sloth.dev) membuat aturan Prometheus ini otomatis dari definisi SLO; contohnya ada di `k8s/slo/relnusa-slos.yaml`.

## 6. Kesepakatan

| Butir | Isi |
|---|---|
| Kebijakan error budget yang berlaku | `[tautan]` |
| Dasbor SLO | `[tautan]` |
| Runbook untuk setiap peringatan page | `[tautan]` |
| Jadwal tinjauan SLO | `[bulanan, bersama pemilik bisnis]` |
| Disetujui oleh (bisnis) | `[nama, tanggal]` |
| Disetujui oleh (TI) | `[nama, tanggal]` |
