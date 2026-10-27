# Lembar desain sistem

Satu lembar untuk satu sistem, atau untuk satu perjalanan pengguna yang paling penting. Isi sebelum membangun sistem baru, sebelum memodernisasi sistem lama, dan pada setiap tinjauan arsitektur. Kolom contoh memakai aplikasi fiktif RelNusa dari lab; ganti dengan sistem Anda sendiri.

Urutannya sengaja dari target ke teknologi: susunan teknologi dipilih paling akhir, setelah target, hitungan dan risiko jelas.

## 1. Perjalanan pengguna dan target

| Perjalanan | Target ketersediaan | Target latensi | Boleh tertunda? | Pemilik | Contoh (RelNusa) |
|---|---|---|---|---|---|
| `[...]` | `[...]` | `[...]` | `[...]` | `[...]` | Cari jadwal: 99,9%, 99% di bawah 500 ms, tidak boleh tertunda |
| `[...]` | `[...]` | `[...]` | `[...]` | `[...]` | Pesan kursi: 99,9%, tanpa error server |
| `[...]` | `[...]` | `[...]` | `[...]` | `[...]` | E-tiket terbit: 99,9% dalam dua menit, boleh lewat antrean |
| `[...]` | `[...]` | `[...]` | `[...]` | `[...]` | Laporan internal: 99%, boleh tertunda |

Batas gangguan per bulan: 99% = 7 jam 18 menit, 99,5% = 3 jam 39 menit, 99,9% = 43 menit 50 detik, 99,95% = 21 menit 55 detik, 99,99% = 4 menit 23 detik. Pemeliharaan terencana ikut dihitung.

## 2. Rantai ketersediaan

Tulis setiap komponen yang **wajib** berjalan agar perjalanan utama berhasil.

| Komponen di jalur wajib | Ketersediaan sendiri | Jumlah cadangan yang gagal tidak bersamaan | Ketersediaan dengan cadangan | Bisa dikeluarkan dari jalur wajib? |
|---|---|---|---|---|
| `[...]` | `[...]` | `[...]` | `[...]` | `[...]` |
| `[...]` | `[...]` | `[...]` | `[...]` | `[...]` |
| `[...]` | `[...]` | `[...]` | `[...]` | `[...]` |

Rumus:
- Rantai: kalikan semua komponen wajib. Lima komponen 99,9% menjadi 0,999⁵ = **99,50%**.
- Cadangan: komponen dengan ketersediaan *a* dan *n* salinan yang tidak gagal bersamaan menjadi 1 − (1 − *a*)ⁿ. Dua salinan 99% menjadi **99,99%**.
- Komponen yang dikeluarkan dari jalur wajib (misalnya pembayaran lewat antrean) tidak masuk perkalian, tetapi tetap butuh SLO sendiri.

| Hasil | Nilai |
|---|---|
| Rantai saat ini | `[...]` |
| Rantai setelah perbaikan desain | `[...]` |
| Target perjalanan | `[...]` |

## 3. Domain kegagalan

| Domain | Contoh penyebab | Apa yang terjadi pada pengguna bila mati | Cadangan ada di mana | Terakhir diuji |
|---|---|---|---|---|
| Proses | Aplikasi macet, kehabisan memori | `[...]` | `[restart otomatis, beberapa replika]` | `[...]` |
| Server atau node | Perangkat keras rusak | `[...]` | `[replika di node berbeda]` | `[...]` |
| Zona atau ruang server | Listrik, pendingin, switch inti | `[...]` | `[replika dan database di zona berbeda]` | `[...]` |
| Pusat data atau region | Bencana, putus jaringan antarkota | `[...]` | `[situs kedua dan replikasi data]` | `[...]` |

| Pemulihan bencana | Target | Hasil uji terakhir |
|---|---|---|
| Waktu pulih (RTO) | `[...]` | `[...]` |
| Data yang boleh hilang (RPO) | `[...]` | `[...]` |

Untuk target 99,9%, rancang paling tidak sampai tingkat zona.

## 4. Menit tersibuk

| Butir | Nilai | Contoh hitungan (angka rekaan) |
|---|---|---|
| Calon pengguna pada puncak | `[...]` | 300.000 dalam 10 menit pertama penjualan |
| Permintaan per pengguna | `[...]` | 15: cari, pilih kursi, pesan, bayar, cek status |
| Rata-rata permintaan per detik | `[...]` | 300.000 × 15 ÷ 600 detik = 7.500 |
| Faktor menit pertama | `[...]` | 3 kali rata-rata = 22.500 per detik |
| Porsi jalur baca | `[...]` | Sekitar 90%, dilayani cache dan replika baca |
| Kapasitas jalur tulis yang sudah diuji | `[...]` | `[pembeli per detik yang dimasukkan ruang tunggu]` |
| Cadangan kapasitas | `[...]` | 1,5 sampai 2 kali puncak |
| Yang terjadi di atas kapasitas | `[...]` | Ruang tunggu dengan nomor antrean, bukan error |
| Uji beban terakhir | `[tanggal, beban, hasil]` | `[...]` |

## 5. Data dan konsistensi

| Data | Harus tepat, boleh tertinggal, atau boleh menyusul | Disimpan di | Cara menjaganya |
|---|---|---|---|
| `[...]` | `[...]` | `[...]` | `[...]` |
| Contoh: sisa kursi | Harus tepat | Database utama | Transaksi singkat, kunci idempotensi |
| Contoh: jadwal | Boleh tertinggal beberapa detik | Cache dan replika baca | Masa berlaku cache yang pendek |
| Contoh: pembayaran dan e-tiket | Boleh menyusul | Antrean | Retry dengan jeda, rekonsiliasi dengan bank |

## 6. Ketergantungan

| Ketergantungan | Batas waktu | Retry | Circuit breaker | Bila mati atau lambat, pengguna melihat apa? |
|---|---|---|---|---|
| `[...]` | `[...]` | `[...]` | `[ya / tidak]` | `[...]` |
| Contoh: bank | 800 ms | Dicoba ulang dari antrean | Ya | Status "menunggu pembayaran"; kursi tetap terkunci |

## 7. Susunan teknologi

| Lapisan | Pilihan | Alasan | Siapa yang mengoperasikan | Contoh (RelNusa) |
|---|---|---|---|---|
| Tepi dan pintu masuk | `[...]` | `[...]` | `[...]` | Traefik dengan ruang tunggu di gateway |
| Platform | `[...]` | `[...]` | `[...]` | Kubernetes (k3s), tiga zona |
| Database transaksi | `[...]` | `[...]` | `[...]` | PostgreSQL dengan CloudNativePG, satu primary dan dua replika |
| Cache dan antrean | `[...]` | `[...]` | `[...]` | Redis dan Redis Streams |
| Observability | `[...]` | `[...]` | `[...]` | Prometheus, Grafana, Jaeger, OpenTelemetry |
| Rilis bertahap | `[...]` | `[...]` | `[...]` | Argo Rollouts dengan analisis Prometheus |
| Uji beban dan gangguan | `[...]` | `[...]` | `[...]` | k6 dan Chaos Mesh |

Pilih yang sanggup dioperasikan tim. Layanan terkelola memindahkan sebagian pekerjaan operasional ke penyedia, tetapi tanggung jawab atas ketersediaan tetap pada pemilik sistem.

## 8. Rilis dan perubahan

| Pertanyaan | Ya / Tidak | Catatan |
|---|---|---|
| Rolling update dengan readiness probe dan graceful shutdown? | | |
| Canary dengan pemeriksaan otomatis dan batal otomatis? | | |
| Perubahan skema database bertahap (expand dan contract)? | | |
| Feature flag untuk fitur berisiko? | | |
| Rilis bisa dibatalkan dalam kurang dari lima menit? | | |
| Tanpa jendela pemeliharaan yang menghentikan layanan? | | |

## 9. Observability

| Butir | Isi |
|---|---|
| SLI diukur di mana | `[pintu masuk: load balancer atau ingress]` |
| Trace dari pintu masuk sampai database dan mitra | `[ya / belum]` |
| Dasbor perjalanan pengguna | `[tautan]` |
| Peringatan berbasis burn rate | `[tautan; turunkan dari lembar kerja SLO]` |
| Runbook untuk setiap peringatan page | `[tautan]` |

## 10. Sepuluh pertanyaan tinjauan desain

| No | Pertanyaan | Jawaban | Tindak lanjut |
|---|---|---|---|
| 1 | Perjalanan penumpang mana yang paling penting, dan berapa targetnya? | | |
| 2 | Di mana titik tunggal kegagalannya? | | |
| 3 | Apa yang terjadi bila satu zona mati? | | |
| 4 | Berapa beban di menit tersibuk, dan apa yang terjadi di atasnya? | | |
| 5 | Komponen mana yang benar-benar wajib ada di jalur pembelian? | | |
| 6 | Apa yang terjadi bila mitra lambat tiga detik? | | |
| 7 | Data mana yang harus tepat, dan mana yang boleh tertinggal? | | |
| 8 | Bisakah dirilis dan dimigrasi tanpa menghentikan layanan? | | |
| 9 | Bagaimana kita tahu penumpang gagal, sebelum mereka melapor? | | |
| 10 | Kapan rencana pemulihan terakhir benar-benar diuji? | | |

## 11. Catatan keputusan

Catat setiap keputusan desain yang penting, supaya alasannya tidak hilang saat tim berganti.

| Tanggal | Keputusan | Alternatif yang ditolak | Alasan | Ditinjau ulang |
|---|---|---|---|---|
| `[...]` | `[...]` | `[...]` | `[...]` | `[...]` |
| Contoh | Pembayaran diproses lewat antrean | Memanggil bank di dalam transaksi pemesanan | Bank yang lambat tidak boleh menahan kunci kursi dan koneksi database | Setiap kuartal |

Bagian yang perlu diisi ditandai dengan `[...]`. Angka contoh hanya ilustrasi.
