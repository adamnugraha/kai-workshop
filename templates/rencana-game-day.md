# Rencana game day

Game day adalah latihan gangguan yang direncanakan: tim menyuntikkan gangguan dengan sengaja untuk menguji arsitektur, peringatan, dasbor, runbook dan cara tim berkoordinasi. Mulai di staging; ke produksi hanya setelah tim terbiasa dan dengan batas aman yang ketat.

## Templat

| Butir | Isi |
|---|---|
| Nama latihan | `[...]` |
| Tanggal dan jam | `[...]` |
| Lingkungan | `[staging / produksi terbatas]` |
| Fasilitator | `[orang yang menjalankan gangguan]` |
| Tim yang dilatih | `[on-call dan tim layanan]` |
| Pengamat dan pencatat | `[...]` |

### 1. Hipotesis

Satu kalimat yang bisa terbukti benar atau salah: "Bila `[gangguan]`, maka `[perilaku sistem yang diharapkan]` dan `[peringatan atau respons yang diharapkan]` dalam `[waktu]`."

### 2. Kondisi normal

| Ukuran | Nilai normal | Sumber |
|---|---|---|
| `[SLI utama]` | `[...]` | `[dasbor]` |
| `[...]` | `[...]` | `[...]` |

### 3. Gangguan

| Butir | Isi |
|---|---|
| Jenis gangguan | `[jaringan lambat / pod mati / node mati / dependensi error / database failover]` |
| Alat | `[Chaos Mesh / skrip / manual]` |
| Lingkup | `[layanan, persentase pod, zona]` |
| Lama maksimal | `[menit]` |

### 4. Batas aman dan tombol berhenti

- Hentikan segera bila: `[misalnya SLI pengguna di bawah 95% lebih dari 2 menit; error di layanan yang tidak dalam lingkup]`.
- Cara menghentikan: `[perintah atau tombol, siapa yang menekan]`.
- Pemberitahuan sebelumnya ke: `[layanan pelanggan, tim lain yang bergantung]`.

### 5. Yang diamati

| Pertanyaan | Hasil |
|---|---|
| Apakah sistem berperilaku seperti hipotesis? | `[...]` |
| Apakah peringatan yang tepat menyala, dan kapan? | `[...]` |
| Apakah dasbor menunjukkan penyebab dengan jelas? | `[...]` |
| Apakah runbook bisa diikuti tanpa bantuan? | `[...]` |
| Apakah sistem pulih sendiri setelah gangguan dihentikan? | `[...]` |
| Berapa error budget yang terpakai? | `[...]` |

### 6. Kronologi

| Waktu | Kejadian |
|---|---|
| `[T+0:00]` | `[gangguan dimulai]` |
| `[...]` | `[...]` |

### 7. Temuan dan tindak lanjut

| Temuan | Tindakan | Pemilik | Tenggat |
|---|---|---|---|
| `[...]` | `[...]` | `[...]` | `[...]` |

Tulis postmortem latihan dengan templat postmortem yang sama seperti insiden nyata.

---

## Contoh terisi: bank melambat (demo 4 di lab)

| Butir | Isi |
|---|---|
| Hipotesis | Bila bank menjawab dalam 3 detik, pemesanan tetap berjalan dan peringatan page penerbitan tiket masuk Telegram dalam 3 menit |
| Kondisi normal | Ketersediaan situs modern 100%; pembayaran berhasil hampir 100%; circuit breaker tertutup |
| Gangguan | Jeda jaringan 3 detik ke bank simulasi lewat Chaos Mesh (`./lab.sh chaos bank-lambat`), atau mode lambat di bank simulasi (`./lab.sh bank slow`) |
| Lama maksimal | 3 menit |
| Tombol berhenti | `./lab.sh chaos stop` atau `./lab.sh bank normal` |
| Yang diamati | Circuit breaker terbuka; kursi tetap terkunci; SLO ketersediaan tetap hijau; burn rate penerbitan tiket di atas 14,4; peringatan masuk Telegram; trace menunjukkan panggilan bank habis waktu di 800 ms; setelah dihentikan, antrean pembayaran tuntas tanpa tagihan ganda |
| Hasil di lab | Circuit breaker terbuka sekitar 20 detik setelah gangguan; peringatan page masuk sekitar 1 menit 20 detik; situs modern tanpa error; setelah bank pulih, 190 pembayaran tertunda tuntas dalam 20 detik tanpa tagihan ganda |
| Temuan yang biasa muncul | Pesan pulih di Telegram baru datang sekitar 30 menit setelah gangguan berhenti, karena gangguan total selama 3 menit juga memicu pasangan jendela 6 jam dan 30 menit. Ini sesuai desain dan perlu dijelaskan ke tim agar tidak dianggap peringatan macet |
