# Log prompt Gemini Canvas (Soal 3.1a)

Tautan percakapan: https://share.gemini.google/kM0c01748nEk
Hasil akhir: `voucher_gemini_canvas.html`

## Prompt 1 - konstruksi awal
Bertindaklah sebagai senior frontend developer untuk sistem akuntansi. Buat satu berkas HTML (Tailwind CSS via CDN + JavaScript murni) untuk "Voucher Entri Transaksi Kas Keluar". Header: tanggal, nomor bukti, keterangan, dropdown aktivitas arus kas (Operasi/Investasi/Pendanaan). Tabel baris jurnal dinamis: dropdown akun, kolom debit, kolom kredit, tombol hapus, tombol "+ Tambah baris". Tampilkan live: Total Debit, Total Kredit, Selisih, dan lencana hijau "SEIMBANG" / merah "TIDAK SEIMBANG". Tombol Submit harus disabled kecuali: Total Debit = Total Kredit dan > 0, minimal 2 baris, setiap baris punya akun dan tepat satu sisi (debit ATAU kredit) bernilai > 0, nomor bukti dan tanggal terisi. Hitung dalam satuan sen (integer) agar tidak ada galat floating point.

## Prompt 2 - aturan bisnis dan integrasi RPC
Tambahkan aturan: karena ini kas keluar, minimal satu baris harus mengkredit akun Kas atau Bank, dan tampilkan pesan error jelas jika tidak. Saat Submit, kumpulkan data ke objek JSON dan panggil supabase.rpc('rpc_create_and_post_journal', {p_trx_date, p_reference_no, p_description, p_lines}). Beri komentar bahwa validasi final dilakukan oleh database.

## Prompt 3 - audit dan UX
Tambahkan konfirmasi sebelum Submit yang menampilkan ringkasan jurnal, dan tambahkan pesan bahwa jurnal berstatus POSTED tidak dapat diedit atau dihapus (hanya dapat dibalik dengan jurnal storno).

## Prompt 4 - perbaikan bug satuan (ditemukan lewat pengujian manual)
Perbaiki ketidaksesuaian satuan: kolom Debit dan Kredit berlabel (Rp), tetapi angka yang diketik pengguna (misalnya 1.500.000) dihitung sebagai sen sehingga total tampil Rp 15.000,00. Ubah agar input diisi dalam Rupiah (boleh dua digit desimal), lalu dikonversi ke sen secara internal (dikali 100) untuk perhitungan integer. Dengan perbaikan ini, input 1.500.000 harus menampilkan Total Rp 1.500.000,00. Pertahankan semua aturan sebelumnya (validasi Kas/Bank, konfirmasi sebelum Submit, pesan POSTED dan storno).
