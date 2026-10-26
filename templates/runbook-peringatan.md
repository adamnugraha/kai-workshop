# Runbook peringatan

Satu runbook untuk satu peringatan. Ditulis supaya petugas on-call yang baru pertama kali melihat peringatan ini, pukul tiga pagi, tetap tahu langkah pertamanya. Tautkan runbook dari anotasi peringatan.

## Templat

### `[NamaPeringatan]`

| | |
|---|---|
| Tingkat | `[page / tiket]` |
| SLO | `[nama SLO, target]` |
| Pemilik | `[tim]` |
| Terakhir diuji | `[tanggal game day atau insiden]` |

**Artinya.** `[Satu kalimat: apa yang dialami pengguna saat peringatan ini menyala.]`

**Dampak.** `[Siapa terdampak, apa yang tidak bisa mereka lakukan, perkiraan tingkat keparahan awal.]`

**Lihat dulu.**
1. `[Dasbor SLO: tautan]`
2. `[Dasbor layanan: tautan]`
3. `[Trace: tautan dengan filter layanan]`
4. `[Log: query yang sudah disimpan]`

**Diagnosis.**

| Bila terlihat | Kemungkinan penyebab | Langkah |
|---|---|---|
| `[...]` | `[...]` | `[...]` |

**Pemulihan.**
1. `[Langkah yang paling aman dan cepat lebih dulu, misalnya kembalikan rilis terakhir]`
2. `[...]`

**Eskalasi.** `[Siapa dan kapan, misalnya: bila belum pulih dalam 30 menit, panggil ...]`

**Selesai bila.** `[SLI kembali normal minimal 15 menit; antrean kosong; dsb.]`

---

## Contoh terisi: `RelnusaModernPenerbitanTiket`

| | |
|---|---|
| Tingkat | page (burn rate 14,4 dalam 1 jam dan 5 menit, atau 6 dalam 6 jam dan 30 menit) |
| SLO | Penerbitan tiket, 99,9% upaya pembayaran berhasil, 30 hari |
| Pemilik | Tim platform pemesanan |
| Terakhir diuji | Game day demo 4 di lab |

**Artinya.** Pembayaran ke bank gagal atau habis waktu jauh lebih sering dari normal, sehingga penumpang sudah memegang kursi tetapi e-tiket belum terbit. Situs bisa tetap cepat dan tanpa error.

**Dampak.** Penumpang menunggu e-tiket; kursi tetap terkunci selama masa tahan (10 menit di lab). Bila berlangsung lebih lama dari masa tahan, kursi bisa lepas dan penumpang harus memesan ulang. Tingkat awal: Sev2, naik ke Sev1 bila hampir semua pembayaran gagal lebih dari 10 menit.

**Lihat dulu.**
1. Grafana `RelNusa · 2 · SLO dan error budget`: burn rate penerbitan tiket dan ketersediaan. Bila ketersediaan tetap hijau, masalahnya di jalur pembayaran, bukan di situs.
2. Grafana `RelNusa · 3 · Di dalam arsitektur modern`, baris *Pembayaran dan bank*: circuit breaker, upaya pembayaran menurut hasil, antrean.
3. Jaeger, layanan `payment-worker`: cari trace dengan error dan lihat span panggilan bank.

**Diagnosis.**

| Bila terlihat | Kemungkinan penyebab | Langkah |
|---|---|---|
| Hasil `timeout` mendominasi, breaker terbuka | Bank lambat | Cek status mitra pembayaran; hubungi kontak teknis bank |
| Hasil `failure` mendominasi | Bank menolak atau error | Cek kode error di log worker; cek kredensial dan sertifikat |
| Hasil `error` mendominasi | Database atau Redis bermasalah | Cek panel database dan koneksi aktif |
| Antrean naik tetapi upaya pembayaran nol | Worker mati atau macet | `kubectl -n modern get pods -l app=payment-worker`; cek log |

**Pemulihan.**
1. Jangan menaikkan timeout atau mematikan circuit breaker; keduanya melindungi seluruh sistem.
2. Bila bank lambat: tunggu atau alihkan ke penyedia cadangan bila tersedia. Pembayaran yang tertunda tetap di antrean dan dibayar otomatis saat bank pulih, tanpa tagihan ganda karena kunci idempotensi.
3. Bila masalah mulai setelah rilis: kembalikan rilis worker.
4. Bila worker mati: periksa event pod dan sumber daya node, lalu jalankan ulang.

**Eskalasi.** Bila belum pulih dalam 30 menit, atau masa tahan kursi hampir habis, naikkan ke Sev1 dan beri tahu layanan pelanggan.

**Selesai bila.** Circuit breaker tertutup, antrean pembayaran kosong, dan burn rate 5 menit kembali di bawah 1 selama minimal 15 menit.
