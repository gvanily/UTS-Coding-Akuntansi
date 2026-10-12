CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE chart_of_accounts (
    account_id            SERIAL        PRIMARY KEY,
    account_code          VARCHAR(20)   NOT NULL UNIQUE,
    account_name          VARCHAR(100)  NOT NULL,
    normal_balance        VARCHAR(6)    NOT NULL CHECK (normal_balance IN ('DEBIT','CREDIT')),
    report_classification VARCHAR(20)   NOT NULL CHECK (report_classification IN
                          ('ASSET','LIABILITY','EQUITY','REVENUE','EXPENSE'))
);

CREATE TABLE journal_headers (
    header_id        BIGSERIAL    PRIMARY KEY,
    trx_date         DATE         NOT NULL,
    reference_no     VARCHAR(50)  NOT NULL UNIQUE,
    description      TEXT,
    posting_status   VARCHAR(10)  NOT NULL DEFAULT 'DRAFT'
                     CHECK (posting_status IN ('DRAFT','POSTED','REVERSED')),
    created_by       VARCHAR(100) NOT NULL DEFAULT current_user,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    hash_checksum    CHAR(64),
    reversal_of_id   BIGINT       REFERENCES journal_headers(header_id) ON DELETE RESTRICT
);

CREATE TABLE journal_lines (
    line_id     BIGSERIAL     PRIMARY KEY,
    header_id   BIGINT        NOT NULL REFERENCES journal_headers(header_id) ON DELETE RESTRICT,
    account_id  INT           NOT NULL REFERENCES chart_of_accounts(account_id) ON DELETE RESTRICT,
    debit       NUMERIC(18,2) NOT NULL DEFAULT 0,
    credit      NUMERIC(18,2) NOT NULL DEFAULT 0,
    CONSTRAINT chk_non_negative CHECK (debit >= 0 AND credit >= 0),
    CONSTRAINT chk_not_both_zero CHECK (NOT (debit = 0 AND credit = 0)),
    CONSTRAINT chk_one_sided CHECK (debit = 0 OR credit = 0)
);
CREATE INDEX idx_journal_lines_header  ON journal_lines(header_id);
CREATE INDEX idx_journal_lines_account ON journal_lines(account_id);

-- Keseimbangan Debit = Kredit ditegakkan di DB (ditunda sampai COMMIT)
CREATE OR REPLACE FUNCTION fn_check_journal_balance() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_header_id BIGINT; v_status TEXT; v_debit NUMERIC; v_credit NUMERIC;
BEGIN
    IF TG_TABLE_NAME = 'journal_headers' THEN
        v_header_id := NEW.header_id;
    ELSE
        v_header_id := COALESCE(NEW.header_id, OLD.header_id);
    END IF;

    SELECT posting_status INTO v_status FROM journal_headers WHERE header_id = v_header_id;
    IF v_status IS NULL OR v_status = 'DRAFT' THEN RETURN NULL; END IF;

    SELECT COALESCE(SUM(debit),0), COALESCE(SUM(credit),0)
      INTO v_debit, v_credit FROM journal_lines WHERE header_id = v_header_id;

    IF v_debit <> v_credit OR v_debit = 0 THEN
        RAISE EXCEPTION 'Jurnal % tidak seimbang / kosong (Debit=%, Kredit=%)',
                        v_header_id, v_debit, v_credit USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END $$;

CREATE CONSTRAINT TRIGGER ctrg_balance_header
    AFTER INSERT OR UPDATE ON journal_headers
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION fn_check_journal_balance();
CREATE CONSTRAINT TRIGGER ctrg_balance_lines
    AFTER INSERT OR UPDATE OR DELETE ON journal_lines
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION fn_check_journal_balance();
CREATE TABLE inventory_items (
    item_id VARCHAR(10) PRIMARY KEY,
    item_name VARCHAR(100),
    stock_qty INT NOT NULL DEFAULT 0,
    unit_cost NUMERIC(15, 2) NOT NULL
);
CREATE TABLE inventory_transactions (
    trx_id SERIAL PRIMARY KEY,
    item_id VARCHAR(10) REFERENCES inventory_items(item_id),
    trx_type VARCHAR(10) CHECK (trx_type IN ('PURCHASE', 'SALE', 'ADJUSTMENT')),
    qty INT NOT NULL,
    trx_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE inventory_items ADD CONSTRAINT chk_stock_non_negative CHECK (stock_qty >= 0);

CREATE OR REPLACE FUNCTION trg_update_stock_and_journal() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_delta INT; v_stock INT; v_cost NUMERIC(15,2);
    v_amount NUMERIC(18,2); v_header BIGINT;
    v_acc_hpp INT; v_acc_inv INT;
BEGIN
    IF NEW.trx_type IN ('PURCHASE','SALE') AND NEW.qty <= 0 THEN
        RAISE EXCEPTION 'qty % tidak valid untuk %: harus > 0', NEW.qty, NEW.trx_type;
    ELSIF NEW.trx_type = 'ADJUSTMENT' AND NEW.qty = 0 THEN
        RAISE EXCEPTION 'qty ADJUSTMENT tidak boleh 0';
    END IF;

    v_delta := CASE NEW.trx_type WHEN 'PURCHASE' THEN NEW.qty
                                 WHEN 'SALE'     THEN -NEW.qty
                                 ELSE NEW.qty END;   -- ADJUSTMENT bertanda (+/-)

    -- kunci baris item SEBELUM memeriksa saldo (anti race condition)
    SELECT stock_qty, unit_cost INTO v_stock, v_cost
      FROM inventory_items WHERE item_id = NEW.item_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Item % tidak ditemukan', NEW.item_id;
    END IF;

    IF v_stock + v_delta < 0 THEN
        RAISE EXCEPTION 'Stok % tidak cukup: tersedia %, diminta %',
                        NEW.item_id, v_stock, ABS(v_delta) USING ERRCODE = '23514';
    END IF;

    UPDATE inventory_items SET stock_qty = stock_qty + v_delta WHERE item_id = NEW.item_id;

    -- Jurnal otomatis HPP: Dr HPP / Cr Persediaan
    IF NEW.trx_type = 'SALE' THEN
        v_amount := NEW.qty * v_cost;
        IF v_amount > 0 THEN
            SELECT account_id INTO STRICT v_acc_hpp FROM chart_of_accounts WHERE account_code = '5-1100';
            SELECT account_id INTO STRICT v_acc_inv FROM chart_of_accounts WHERE account_code = '1-1300';
            INSERT INTO journal_headers (trx_date, reference_no, description, posting_status)
            VALUES (NEW.trx_date::date, 'HPP-' || NEW.trx_id,
                    'HPP otomatis penjualan ' || NEW.item_id || ' x' || NEW.qty, 'DRAFT')
            RETURNING header_id INTO v_header;
            INSERT INTO journal_lines (header_id, account_id, debit, credit) VALUES
                (v_header, v_acc_hpp, v_amount, 0),
                (v_header, v_acc_inv, 0, v_amount);
            UPDATE journal_headers SET posting_status = 'POSTED' WHERE header_id = v_header;
        END IF;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_inventory_after_insert
AFTER INSERT ON inventory_transactions
FOR EACH ROW EXECUTE FUNCTION trg_update_stock_and_journal();
CREATE OR REPLACE FUNCTION fn_compute_journal_hash(p_header_id BIGINT) RETURNS CHAR(64)
LANGUAGE sql STABLE AS $$
    SELECT encode(digest(
        format('%s|%s|%s|%s|%s|%s|%s',
            h.header_id, h.trx_date, h.reference_no, COALESCE(h.description,''),
            h.created_by, to_char(h.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US'),
            COALESCE((SELECT string_agg(format('%s:%s:%s:%s', l.line_id, l.account_id, l.debit, l.credit),
                                        ';' ORDER BY l.line_id)
                        FROM journal_lines l WHERE l.header_id = h.header_id), '')
        ), 'sha256'), 'hex')
    FROM journal_headers h WHERE h.header_id = p_header_id;
$$;

CREATE TABLE audit_log (
    audit_id   BIGSERIAL PRIMARY KEY,
    table_name TEXT NOT NULL, record_id BIGINT, action TEXT NOT NULL,
    old_data JSONB, new_data JSONB,
    actor TEXT NOT NULL DEFAULT current_user,
    acted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION fn_audit_log() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_row JSONB;
BEGIN
    v_row := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
    INSERT INTO audit_log(table_name, record_id, action, old_data, new_data)
    VALUES (TG_TABLE_NAME,
            (v_row ->> CASE TG_TABLE_NAME WHEN 'journal_headers' THEN 'header_id' ELSE 'line_id' END)::BIGINT,
            TG_OP,
            CASE WHEN TG_OP IN ('UPDATE','DELETE') THEN to_jsonb(OLD) END,
            CASE WHEN TG_OP IN ('INSERT','UPDATE') THEN to_jsonb(NEW) END);
    RETURN COALESCE(NEW, OLD);
END $$;
CREATE TRIGGER trg_audit_headers AFTER INSERT OR UPDATE OR DELETE ON journal_headers
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log();
CREATE TRIGGER trg_audit_lines AFTER INSERT OR UPDATE OR DELETE ON journal_lines
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log();

CREATE OR REPLACE FUNCTION fn_audit_log_append_only() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'audit_log bersifat append-only'; END $$;
CREATE TRIGGER trg_audit_log_immutable BEFORE UPDATE OR DELETE ON audit_log
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log_append_only();

-- Imutabilitas header
CREATE OR REPLACE FUNCTION fn_protect_posted_header() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.posting_status <> 'DRAFT' THEN
            RAISE EXCEPTION 'Jurnal % berstatus % tidak boleh dihapus. Gunakan jurnal pembalik (storno).',
                            OLD.reference_no, OLD.posting_status USING ERRCODE = '55000';
        END IF;
        RETURN OLD;
    END IF;
    IF OLD.posting_status = 'DRAFT' THEN RETURN NEW; END IF;
    -- satu-satunya perubahan yang diizinkan: POSTED -> REVERSED (field lain identik)
    IF OLD.posting_status = 'POSTED' AND NEW.posting_status = 'REVERSED'
       AND (NEW.header_id, NEW.trx_date, NEW.reference_no, NEW.description, NEW.created_by,
            NEW.created_at, NEW.hash_checksum, NEW.reversal_of_id)
           IS NOT DISTINCT FROM
           (OLD.header_id, OLD.trx_date, OLD.reference_no, OLD.description, OLD.created_by,
            OLD.created_at, OLD.hash_checksum, OLD.reversal_of_id) THEN
        RETURN NEW;
    END IF;
    RAISE EXCEPTION 'Jurnal % berstatus % bersifat immutable. Gunakan jurnal pembalik (storno).',
                    OLD.reference_no, OLD.posting_status USING ERRCODE = '55000';
END $$;
CREATE TRIGGER trg_protect_header BEFORE UPDATE OR DELETE ON journal_headers
    FOR EACH ROW EXECUTE FUNCTION fn_protect_posted_header();

-- Imutabilitas baris (tak boleh INSERT/UPDATE/DELETE bila header bukan DRAFT)
CREATE OR REPLACE FUNCTION fn_protect_posted_lines() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_status TEXT;
BEGIN
    SELECT posting_status INTO v_status FROM journal_headers
     WHERE header_id = COALESCE(NEW.header_id, OLD.header_id);
    IF v_status IS NOT NULL AND v_status <> 'DRAFT' THEN
        RAISE EXCEPTION 'Baris jurnal pada header berstatus % tidak boleh diubah.', v_status
              USING ERRCODE = '55000';
    END IF;
    RETURN COALESCE(NEW, OLD);
END $$;
CREATE TRIGGER trg_protect_lines BEFORE INSERT OR UPDATE OR DELETE ON journal_lines
    FOR EACH ROW EXECUTE FUNCTION fn_protect_posted_lines();

-- RPC: posting
CREATE OR REPLACE FUNCTION rpc_post_journal(p_header_id BIGINT) RETURNS CHAR(64)
LANGUAGE plpgsql AS $$
DECLARE v_status TEXT; v_d NUMERIC; v_c NUMERIC; v_hash CHAR(64);
BEGIN
    SELECT posting_status INTO v_status FROM journal_headers WHERE header_id = p_header_id FOR UPDATE;
    IF v_status IS NULL THEN RAISE EXCEPTION 'Jurnal % tidak ditemukan', p_header_id; END IF;
    IF v_status <> 'DRAFT' THEN RAISE EXCEPTION 'Jurnal % sudah berstatus %', p_header_id, v_status; END IF;
    SELECT COALESCE(SUM(debit),0), COALESCE(SUM(credit),0) INTO v_d, v_c
      FROM journal_lines WHERE header_id = p_header_id;
    IF v_d = 0 OR v_d <> v_c THEN
        RAISE EXCEPTION 'Tidak dapat posting: Debit % <> Kredit %', v_d, v_c;
    END IF;
    v_hash := fn_compute_journal_hash(p_header_id);
    UPDATE journal_headers SET posting_status = 'POSTED', hash_checksum = v_hash
     WHERE header_id = p_header_id;
    RETURN v_hash;
END $$;

-- RPC: storno
CREATE OR REPLACE FUNCTION rpc_reverse_journal(p_header_id BIGINT, p_reason TEXT) RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE v_orig journal_headers%ROWTYPE; v_new BIGINT;
BEGIN
    SELECT * INTO v_orig FROM journal_headers WHERE header_id = p_header_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Jurnal % tidak ditemukan', p_header_id; END IF;
    IF v_orig.posting_status <> 'POSTED' THEN
        RAISE EXCEPTION 'Hanya jurnal POSTED yang dapat dibalik (status saat ini: %)', v_orig.posting_status;
    END IF;
    INSERT INTO journal_headers (trx_date, reference_no, description, posting_status, reversal_of_id)
    VALUES (CURRENT_DATE, 'REV-' || v_orig.reference_no,
            'Storno ' || v_orig.reference_no || ': ' || COALESCE(p_reason,'-'), 'DRAFT', p_header_id)
    RETURNING header_id INTO v_new;
    INSERT INTO journal_lines (header_id, account_id, debit, credit)
    SELECT v_new, account_id, credit, debit FROM journal_lines WHERE header_id = p_header_id;
    PERFORM rpc_post_journal(v_new);
    UPDATE journal_headers SET posting_status = 'REVERSED' WHERE header_id = p_header_id;
    RETURN v_new;
END $$;

CREATE OR REPLACE FUNCTION rpc_verify_journal(p_header_id BIGINT) RETURNS BOOLEAN
LANGUAGE sql STABLE AS $$
    SELECT hash_checksum = fn_compute_journal_hash(header_id)
      FROM journal_headers WHERE header_id = p_header_id;
$$;

-- RPC: dipanggil frontend (Supabase: supabase.rpc('rpc_create_and_post_journal', {...}))
CREATE OR REPLACE FUNCTION rpc_create_and_post_journal(
    p_trx_date DATE, p_reference_no TEXT, p_description TEXT, p_lines JSONB) RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE v_id BIGINT;
BEGIN
    INSERT INTO journal_headers (trx_date, reference_no, description)
    VALUES (p_trx_date, p_reference_no, p_description) RETURNING header_id INTO v_id;
    INSERT INTO journal_lines (header_id, account_id, debit, credit)
    SELECT v_id, (x->>'account_id')::INT,
           COALESCE((x->>'debit')::NUMERIC, 0), COALESCE((x->>'credit')::NUMERIC, 0)
      FROM jsonb_array_elements(p_lines) AS x;
    PERFORM rpc_post_journal(v_id);   -- gagal bila tidak seimbang
    RETURN v_id;
END $$;

-- Hardening (Supabase): tutup jalur tulis langsung, buka hanya lewat RPC
-- REVOKE INSERT, UPDATE, DELETE ON journal_headers, journal_lines, audit_log FROM anon, authenticated;
-- GRANT EXECUTE ON FUNCTION rpc_create_and_post_journal, rpc_reverse_journal, rpc_verify_journal TO authenticated;
-- (RPC dijadikan SECURITY DEFINER; created_by diisi auth.uid()::text)
