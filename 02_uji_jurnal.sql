\set ON_ERROR_STOP off
INSERT INTO chart_of_accounts(account_code,account_name,normal_balance,report_classification) VALUES
 ('1-1100','Kas','DEBIT','ASSET'),('1-1300','Persediaan Barang Dagang','DEBIT','ASSET'),
 ('5-1100','Harga Pokok Penjualan','DEBIT','EXPENSE'),('6-1100','Beban Listrik','DEBIT','EXPENSE');
\echo '--- T1: CHECK nol-nol & negatif'
INSERT INTO journal_headers(trx_date,reference_no) VALUES (CURRENT_DATE,'TEST-1');
INSERT INTO journal_lines(header_id,account_id,debit,credit) VALUES (1,1,0,0);
INSERT INTO journal_lines(header_id,account_id,debit,credit) VALUES (1,1,-5,0);
\echo '--- T2: FK RESTRICT (akun & header yang sudah dipakai tidak bisa dihapus)'
INSERT INTO journal_lines(header_id,account_id,debit,credit) VALUES (1,1,100,0);
DELETE FROM chart_of_accounts WHERE account_code='1-1100';
DELETE FROM journal_headers WHERE header_id=1;
DELETE FROM journal_lines WHERE header_id=1;
DELETE FROM journal_headers WHERE header_id=1;
\echo '--- T3: jurnal tak seimbang tidak bisa POSTED (commit gagal)'
BEGIN;
INSERT INTO journal_headers(trx_date,reference_no,posting_status) VALUES (CURRENT_DATE,'BAD-1','POSTED');
COMMIT;
\echo '--- T4: jurnal Kas Keluar seimbang -> post'
BEGIN;
INSERT INTO journal_headers(trx_date,reference_no,description) VALUES (CURRENT_DATE,'KK-001','Bayar listrik') RETURNING header_id \gset
INSERT INTO journal_lines(header_id,account_id,debit,credit) VALUES (:header_id,4,1500000,0),(:header_id,1,0,1500000);
SELECT rpc_post_journal(:header_id) AS hash;
COMMIT;
SELECT header_id,reference_no,posting_status,left(hash_checksum,12) FROM journal_headers WHERE reference_no='KK-001';
\echo '--- T5: UPDATE/DELETE posted ditolak'
UPDATE journal_headers SET description='ubah' WHERE reference_no='KK-001';
DELETE FROM journal_headers WHERE reference_no='KK-001';
UPDATE journal_lines SET debit=1 WHERE header_id=(SELECT header_id FROM journal_headers WHERE reference_no='KK-001');
DELETE FROM journal_lines WHERE header_id=(SELECT header_id FROM journal_headers WHERE reference_no='KK-001');
\echo '--- T6: storno'
SELECT rpc_reverse_journal(header_id,'Salah input') FROM journal_headers WHERE reference_no='KK-001';
SELECT reference_no,posting_status,reversal_of_id FROM journal_headers ORDER BY header_id;
SELECT a.account_code, l.debit, l.credit, h.reference_no FROM journal_lines l JOIN chart_of_accounts a USING(account_id) JOIN journal_headers h USING(header_id) WHERE h.reference_no LIKE '%KK-001' ORDER BY h.header_id, l.line_id;
SELECT reference_no, rpc_verify_journal(header_id) AS integritas_ok FROM journal_headers WHERE posting_status<>'DRAFT';
\echo '--- T7: manipulasi tersembunyi (trigger proteksi dimatikan), lalu verifikasi hash'
ALTER TABLE journal_lines DISABLE TRIGGER trg_protect_lines;
UPDATE journal_lines
   SET debit  = CASE WHEN debit  > 0 THEN 9999999 ELSE 0 END,
       credit = CASE WHEN credit > 0 THEN 9999999 ELSE 0 END
 WHERE header_id = (SELECT header_id FROM journal_headers WHERE reference_no = 'KK-001');
SELECT reference_no, rpc_verify_journal(header_id) AS integritas_ok
  FROM journal_headers WHERE reference_no = 'KK-001';
