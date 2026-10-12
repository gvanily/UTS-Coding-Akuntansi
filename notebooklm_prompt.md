# NotebookLM (Soal 3.1b)

Notebook: "PSAK 207 Dan Akuntansi Kas Kecil" (22 sumber: PSAK 207, PSAK 201, buletin/modul IAI, isi 01_skema_trigger_rpc.sql, isi voucher_gemini_canvas.html).
Tangkapan layar: notebooklm_1.png sampai notebooklm_5.png

## Prompt
Berdasarkan HANYA sumber yang saya unggah, periksa apakah logika kode (form kas keluar, constraint, trigger, dan fungsi posting) konsisten dengan ketentuan pengakuan dan penyajian kas dan setara kas. Untuk setiap aturan, nyatakan: sesuai / tidak sesuai / tidak dapat diverifikasi, sertakan kutipan sumber dan paragraf standar.

## Rangkuman evaluasi NotebookLM
| Aturan | Status | Paragraf acuan |
|---|---|---|
| Klasifikasi aktivitas arus kas | Sesuai | PSAK 207 par. 10 dan 11 |
| Penegakan kredit akun Kas/Bank | Sesuai | PSAK 207 par. 06 dan 14(c) |
| Transfer internal antar-kas | Tidak sesuai | PSAK 207 par. 09 |
| Pencatatan rinci beban kas kecil | Sesuai | Teori dan evaluasi kas kecil |
| Keseimbangan dan imutabilitas (storno) | Sesuai | PSAK 201 par. 15 |
| Pengukuran nominal Rupiah | Sesuai | PSAK 221 par. 21 |
| Pengungkapan restriksi kas | Tidak dapat diverifikasi | PSAK 207 par. 48 |
| Transaksi arus kas valas | Tidak dapat diverifikasi | PSAK 207 par. 25 dan 28 |
| Pengungkapan terpisah bunga dan dividen | Tidak dapat diverifikasi | PSAK 207 par. 31 |

Temuan utama: transfer antar-kas tidak boleh dipaksa menjadi salah satu dari tiga aktivitas arus kas (PSAK 207 par. 09). Rekomendasi: tambahkan pilihan "Transfer antar-kas (bukan arus kas)".
