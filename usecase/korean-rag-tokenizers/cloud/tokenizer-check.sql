-- Which of the lab's tokenizers does a ClickHouse Cloud service accept?
--
-- Not run by tools/hol (it is not a top-level NN-*.sql file). Run it by hand on a
-- Cloud service you own, statement by statement (the Cloud SQL console reports each
-- statement on its own, so one rejected tokenizer does not hide the others).
-- It creates one scratch database with eight one-column tables and drops it at the end.

-- 1. Server build and the tokenizers it lists. Read-only.
SELECT version() AS build, groupArray(name) AS tokenizers FROM system.tokenizers;

-- 2. tokens() for each tokenizer. Read-only. A tokenizer the build does not have fails
--    with Code 42 (wrong number of arguments) or an unknown-tokenizer error.
SELECT tokens(lower('결재선은 VPN이 ERP-4012'), 'splitByNonAlpha');
SELECT tokens(lower('결재선은 VPN이 ERP-4012'), 'asciiCJK');
SELECT tokens(lower('결재선은 VPN이 ERP-4012'), 'ngrams', 2);
SELECT tokens(lower('결재선은 VPN이 ERP-4012'), 'ngrams', 3);
SELECT tokens(lower('결재선은 VPN이 ERP-4012'), 'sparseGrams');
SELECT tokens(lower('결재선은 VPN이 ERP-4012'), 'icu', 'ko');
SELECT tokens(lower('결재선은 VPN이 ERP-4012'), 'splitByRegexp', '([\\p{L}\\p{N}]+?)(?:은|는|이|가|을|를|에서|에게|에|의|로|으로|와|과|도|만)?(?:[^\\p{L}\\p{N}]|$)', true);
SELECT tokens('결재선', 'array');

-- 3. A text index per tokenizer, exactly as 02-schema.sql declares it. Writes.
CREATE DATABASE IF NOT EXISTS krag_tokenizer_check;
CREATE TABLE krag_tokenizer_check.t_nonalpha (b String, INDEX i b TYPE text(tokenizer = splitByNonAlpha, preprocessor = lower(b))) ENGINE = MergeTree ORDER BY tuple();
CREATE TABLE krag_tokenizer_check.t_cjk      (b String, INDEX i b TYPE text(tokenizer = asciiCJK, preprocessor = lower(b))) ENGINE = MergeTree ORDER BY tuple();
CREATE TABLE krag_tokenizer_check.t_ng2      (b String, INDEX i b TYPE text(tokenizer = ngrams(2), preprocessor = lower(b))) ENGINE = MergeTree ORDER BY tuple();
CREATE TABLE krag_tokenizer_check.t_ng3      (b String, INDEX i b TYPE text(tokenizer = ngrams(3), preprocessor = lower(b))) ENGINE = MergeTree ORDER BY tuple();
CREATE TABLE krag_tokenizer_check.t_sparse   (b String, INDEX i b TYPE text(tokenizer = sparseGrams, preprocessor = lower(b))) ENGINE = MergeTree ORDER BY tuple();
CREATE TABLE krag_tokenizer_check.t_icu      (b String, INDEX i b TYPE text(tokenizer = icu('ko'), preprocessor = lower(b))) ENGINE = MergeTree ORDER BY tuple();
CREATE TABLE krag_tokenizer_check.t_regexp   (b String, INDEX i b TYPE text(tokenizer = splitByRegexp('([\\p{L}\\p{N}]+?)(?:은|는|이|가|을|를|에서|에게|에|의|로|으로|와|과|도|만)?(?:[^\\p{L}\\p{N}]|$)', true), preprocessor = lower(b))) ENGINE = MergeTree ORDER BY tuple();
CREATE TABLE krag_tokenizer_check.t_kiwi     (m Array(String), INDEX i m TYPE text(tokenizer = array)) ENGINE = MergeTree ORDER BY tuple();

-- 4. What was created: one row per accepted tokenizer.
SELECT table, type_full FROM system.data_skipping_indices WHERE database = 'krag_tokenizer_check' ORDER BY table;

-- 5. Clean up.
DROP DATABASE krag_tokenizer_check;
