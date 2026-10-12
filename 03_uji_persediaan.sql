\set ON_ERROR_STOP off
INSERT INTO inventory_items VALUES ('BRG-001','Kertas A4',10,50000);
\echo '--- PURCHASE 5'
INSERT INTO inventory_transactions(item_id,trx_type,qty) VALUES ('BRG-001','PURCHASE',5);
SELECT item_id, stock_qty FROM inventory_items;
\echo '--- SALE 3 -> jurnal HPP 150000'
INSERT INTO inventory_transactions(item_id,trx_type,qty) VALUES ('BRG-001','SALE',3);
SELECT item_id, stock_qty FROM inventory_items;
SELECT h.reference_no,h.posting_status,a.account_code,l.debit,l.credit FROM journal_headers h JOIN journal_lines l USING(header_id) JOIN chart_of_accounts a USING(account_id) WHERE h.reference_no LIKE 'HPP-%' ORDER BY l.line_id;
\echo '--- SALE 100 -> ditolak'
INSERT INTO inventory_transactions(item_id,trx_type,qty) VALUES ('BRG-001','SALE',100);
SELECT item_id, stock_qty FROM inventory_items;
SELECT count(*) AS trx_count FROM inventory_transactions;
\echo '--- ADJUSTMENT -20 -> ditolak; +2 diterima'
INSERT INTO inventory_transactions(item_id,trx_type,qty) VALUES ('BRG-001','ADJUSTMENT',-20);
INSERT INTO inventory_transactions(item_id,trx_type,qty) VALUES ('BRG-001','ADJUSTMENT',2);
SELECT item_id, stock_qty FROM inventory_items;
