-- Probes whose error may be the result: they are not run by tools/hol (top-level files only).
-- The runner records the error code per version; any that succeed on 26.10 are noted in the lab README, not hidden here.

CREATE DATABASE IF NOT EXISTS index_lab;

DROP TABLE IF EXISTS index_lab.e_pk;

DROP TABLE IF EXISTS index_lab.e_sk;

DROP TABLE IF EXISTS index_lab.e_inv;

DROP TABLE IF EXISTS index_lab.e_ft;

DROP TABLE IF EXISTS index_lab.e_txd;

DROP TABLE IF EXISTS index_lab.e_txn;

DROP TABLE IF EXISTS index_lab.e_txu;

DROP TABLE IF EXISTS index_lab.e_noorder;

CREATE TABLE index_lab.e_pk (id UInt64, c UInt32) ENGINE = MergeTree ORDER BY id;

INSERT INTO index_lab.e_pk SELECT number, number % 7 FROM numbers(10000);

CREATE TABLE index_lab.e_sk (id UInt64, v UInt32, INDEX i_v v TYPE minmax GRANULARITY 1) ENGINE = MergeTree ORDER BY id;

INSERT INTO index_lab.e_sk SELECT number, number FROM numbers(10000);

-- probe: err-force-pk value
-- Correct: code 277 (c is not in the primary key; with 10,000 rows c = 7 matches 0 rows, but the query must be refused).
SELECT count() FROM index_lab.e_pk WHERE c = 7 SETTINGS force_primary_key = 1;

-- probe: err-force-skip value
-- Correct: code 277 (no index named i_none).
SELECT count() FROM index_lab.e_sk WHERE v = 7 SETTINGS force_data_skipping_indices = 'i_none';

-- probe: err-type-inverted value
-- Correct: 24.8/25.3 code 127, 25.8+ code 80.
CREATE TABLE index_lab.e_inv (id UInt64, s String, INDEX i s TYPE inverted(0)) ENGINE = MergeTree ORDER BY id;

-- probe: err-type-full-text value
-- Correct: 24.8 code 344 (24.8 does not take the setting from the CREATE's SETTINGS; accepted after a session SET), 25.3 ok, 25.8+ code 80.
CREATE TABLE index_lab.e_ft (id UInt64, s String, INDEX i s TYPE full_text(0)) ENGINE = MergeTree ORDER BY id SETTINGS allow_experimental_full_text_index = 1;

-- probe: err-type-text-default value
-- Correct: 25.8 ok, 26.x code 36, 24.8/25.3 code 80.
CREATE TABLE index_lab.e_txd (id UInt64, s String, INDEX i s TYPE text(tokenizer = 'default')) ENGINE = MergeTree ORDER BY id SETTINGS allow_experimental_full_text_index = 1;

-- probe: err-type-text-notok value
-- Correct: 26.x code 36 (tokenizer is required).
CREATE TABLE index_lab.e_txn (id UInt64, s String, INDEX i s TYPE text) ENGINE = MergeTree ORDER BY id SETTINGS allow_experimental_full_text_index = 1;

-- probe: err-text-on-uint value
-- Correct: an error on every build (a text index needs a string column); the code is the finding.
CREATE TABLE index_lab.e_txu (id UInt64, n UInt64, INDEX i n TYPE text(tokenizer = splitByNonAlpha)) ENGINE = MergeTree ORDER BY id SETTINGS allow_experimental_full_text_index = 1;

-- probe: err-no-order-by value
-- Correct: 25.8 and earlier fail, 26.3+ ok (25.11 create_table_empty_primary_key_by_default).
CREATE TABLE index_lab.e_noorder (id UInt64) ENGINE = MergeTree;
