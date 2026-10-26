# Templat

Templat ini menyertai sesi **Mencapai ketersediaan 99,9% ke atas**. Semuanya berupa Markdown biasa supaya mudah disalin ke Confluence, SharePoint, Notion, wiki Git, atau dokumen apa pun yang dipakai tim. Contoh isian memakai aplikasi fiktif RelNusa dari lab; ganti dengan layanan Anda sendiri.

| Templat | Dipakai untuk | Kapan |
|---|---|---|
| [Lembar kerja SLO](lembar-kerja-slo.md) | Menurunkan SLI, SLO, error budget dan ambang peringatan dari satu perjalanan pengguna | Saat menetapkan atau meninjau SLO |
| [Kebijakan error budget](kebijakan-error-budget.md) | Aturan rilis yang disepakati bisnis dan TI bila jatah gangguan menipis | Sekali, sebelum insiden berikutnya; ditinjau tiap kuartal |
| [Matriks tingkat keparahan](matriks-keparahan.md) | Tingkat keparahan insiden, peran, target respons dan pola komunikasi | Sekali, lalu dipakai di setiap insiden |
| [Runbook peringatan](runbook-peringatan.md) | Langkah diagnosis dan pemulihan untuk satu peringatan | Untuk setiap peringatan yang bisa membangunkan orang |
| [Postmortem](postmortem.md) | Laporan insiden tanpa menyalahkan, dengan tindak lanjut yang terukur | Setelah setiap insiden Sev1 dan Sev2, dan setiap game day |
| [Rencana game day](rencana-game-day.md) | Latihan gangguan yang direncanakan dan aman | Minimal satu kali per kuartal |
| [Kartu penilaian modernisasi](kartu-penilaian-modernisasi.md) | Menilai aplikasi dan memilih fungsi pertama yang dipisahkan dari monolit | Saat menyusun rencana modernisasi |
| [Rencana 90 hari](rencana-90-hari.md) | Langkah 30, 60 dan 90 hari untuk memulai SRE | Di awal program |

## Cara memakai

1. Mulai dari **lembar kerja SLO** untuk satu perjalanan pengguna saja. Satu SLO yang dipakai lebih berguna daripada sepuluh yang hanya tertulis.
2. Sepakati **kebijakan error budget** dan **matriks tingkat keparahan** dengan pemilik bisnis sebelum ada insiden besar. Keputusan yang disepakati saat tenang jauh lebih mudah dijalankan saat panik.
3. Tulis **runbook** untuk setiap peringatan berseverity *page*. Peringatan tanpa runbook sebaiknya diturunkan menjadi tiket.
4. Latih semuanya lewat **game day**, lalu perbaiki templat ini berdasarkan temuan latihan.

Bagian yang perlu diisi ditandai dengan `[...]`. Angka contoh hanya ilustrasi.
