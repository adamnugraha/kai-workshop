# Postmortem: `[judul singkat insiden]`

> Postmortem ini tanpa menyalahkan. Tujuannya memahami bagaimana sistem dan proses memungkinkan insiden terjadi, bukan mencari siapa yang salah. Orang yang terlibat menjelaskan apa yang mereka ketahui dan putuskan pada saat itu; keputusan yang masuk akal dengan informasi saat itu tidak dinilai dengan pengetahuan sesudahnya.

| | |
|---|---|
| Tanggal insiden | `[...]` |
| Tingkat keparahan | `[Sev1 / Sev2 / Sev3]` |
| Status | `[draf / ditinjau / final]` |
| Penulis | `[...]` |
| Incident commander | `[...]` |
| Peninjau | `[...]` |

## Ringkasan

`[Tiga sampai lima kalimat: apa yang terjadi, siapa terdampak, berapa lama, apa penyebab utamanya, bagaimana dipulihkan.]`

## Dampak

| Ukuran | Nilai |
|---|---|
| Mulai terdampak | `[jam WIB]` |
| Terdeteksi | `[jam WIB]` (selang dari mulai: `[menit]`) |
| Pulih | `[jam WIB]` (lama gangguan: `[menit]`) |
| Pengguna atau transaksi terdampak | `[jumlah atau persentase]` |
| Error budget terpakai | `[persen dari jatah 30 hari]` untuk SLO `[...]` |
| Dampak bisnis | `[pendapatan, kompensasi, keluhan, reputasi]` |

## Kronologi

Semua waktu dalam WIB. Sertakan sinyal yang terlihat saat itu (peringatan, grafik, laporan pengguna) dan keputusan yang diambil.

| Waktu | Kejadian |
|---|---|
| `[hh:mm]` | `[perubahan atau pemicu]` |
| `[hh:mm]` | `[peringatan menyala / laporan pertama masuk]` |
| `[hh:mm]` | `[incident commander ditetapkan, tingkat keparahan]` |
| `[hh:mm]` | `[langkah diagnosis dan temuan]` |
| `[hh:mm]` | `[langkah pemulihan]` |
| `[hh:mm]` | `[pulih, mulai dipantau]` |
| `[hh:mm]` | `[insiden dinyatakan selesai]` |

## Penyebab dan faktor pendukung

**Pemicu.** `[Kejadian yang memulai insiden, misalnya rilis, lonjakan trafik, gangguan mitra.]`

**Penyebab mendasar.** `[Mengapa pemicu itu bisa menimbulkan dampak sebesar ini. Tanyakan "mengapa" beberapa kali sampai sampai ke kondisi sistem atau proses.]`

**Faktor pendukung.** `[Hal-hal yang memperbesar dampak atau memperlambat pemulihan: tidak ada timeout, peringatan terlambat, runbook usang, akses darurat lambat, dsb.]`

## Deteksi dan respons

- Bagaimana insiden diketahui? `[peringatan SLO / laporan pengguna / kebetulan]`
- Apakah peringatan yang tepat menyala pada waktu yang tepat? `[...]`
- Apakah runbook tersedia dan bisa diikuti? `[...]`
- Apa yang memperlambat pemulihan? `[...]`

## Yang berjalan baik, yang kurang, dan yang kebetulan

| Berjalan baik | Kurang baik | Kebetulan menguntungkan |
|---|---|---|
| `[...]` | `[...]` | `[...]` |

## Tindak lanjut

Setiap tindak lanjut punya pemilik, tenggat dan tiket. Utamakan tindakan yang mencegah terulangnya insiden atau mempercepat deteksi, bukan sekadar "lebih berhati-hati".

| Tindakan | Jenis | Prioritas | Pemilik | Tenggat | Tiket |
|---|---|---|---|---|---|
| `[...]` | `[cegah / deteksi / mitigasi / proses]` | `[tinggi / sedang / rendah]` | `[...]` | `[...]` | `[...]` |

## Pelajaran

`[Hal yang perlu diketahui tim lain. Postmortem yang dibagikan luas mencegah tim lain mengalami insiden yang sama.]`

---

Tips menulis:
- Tulis draf dalam 5 hari kerja selagi ingatan masih segar; kronologi bisa diambil dari kanal koordinasi dan catatan pencatat.
- Rapat tinjauan cukup 30–60 menit. Fokus pada tindak lanjut, bukan pada kronologi.
- Lacak penyelesaian tindak lanjut setiap bulan; postmortem tanpa tindak lanjut yang selesai hanya menjadi arsip.
