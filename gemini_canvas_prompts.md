# Log prompt Gemini Canvas (Soal 3.1a)

Tempel prompt berurutan di Gemini Canvas. Simpan tautan percakapan / tangkapan layar sebagai bukti.

## Prompt 1 - konstruksi awal
Bertindaklah sebagai senior frontend developer untuk sistem akuntansi. Buat satu berkas HTML (Tailwind CSS via CDN + JavaScript murni) untuk "Voucher Entri Transaksi Kas Keluar". Header: tanggal, nomor bukti, keterangan, dropdown aktivitas arus kas (Operasi/Investasi/Pendanaan). Tabel baris jurnal dinamis: dropdown akun, kolom debit, kolom kredit, tombol hapus, tombol "+ Tambah baris". Tampilkan live: Total Debit, Total Kredit, Selisih, dan lencana hijau "SEIMBANG" / merah "TIDAK SEIMBANG". Tombol Submit harus disabled kecuali: Total Debit = Total Kredit dan > 0, minimal 2 baris, setiap baris punya akun dan tepat satu sisi (debit ATAU kredit) bernilai > 0, nomor bukti dan tanggal terisi. Hitung dalam satuan sen (integer) agar tidak ada galat floating point.

## Prompt 2 - aturan bisnis
Tambahkan aturan: karena ini kas keluar, minimal satu baris harus mengkredit akun Kas atau Bank, dan tampilkan pesan error jelas jika tidak. Saat Submit, kumpulkan data ke objek JSON dan panggil supabase.rpc('rpc_create_and_post_journal', {p_trx_date, p_reference_no, p_description, p_lines}). Beri komentar bahwa validasi final dilakukan oleh database.

## Prompt 3 - audit dan UX
Tambahkan konfirmasi sebelum Submit yang menampilkan ringkasan jurnal, dan tambahkan pesan bahwa jurnal berstatus POSTED tidak dapat diedit atau dihapus (hanya dapat dibalik dengan jurnal storno).
