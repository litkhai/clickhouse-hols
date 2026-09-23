-- ClickHouse 26.9 — the keyValuePairs text index tokenizer
--
--   INDEX idx attrs TYPE text(tokenizer = keyValuePairs)
--
-- Observability schemas put the variable part of a row in a Map(String,
-- String) — attributes, labels, tags. Until 26.9 the only way to make
-- attrs['service'] = 'checkout' fast was to guess the hot keys in advance and
-- promote them to real columns, or to read the map column on every query.
--
-- keyValuePairs indexes the map itself. Each entry becomes one token of key
-- and value joined together, so an equality on one key is a single token
-- lookup. This lab measures what that buys, and then spends most of its length
-- on which predicates reach the index and which quietly do not — that is the
-- part you have to plan around.

SELECT '════════ 1. A map column with a text index over it ════════' AS section;

DROP TABLE IF EXISTS kvp;
CREATE TABLE kvp
(
    ts    DateTime,
    attrs Map(String, String),
    INDEX idx_attrs attrs TYPE text(tokenizer = keyValuePairs) GRANULARITY 1
)
ENGINE = MergeTree ORDER BY ts;

-- Two million rows of log-shaped attributes. tenant is clustered — 100k
-- consecutive rows share one — because that is what makes an index useful and
-- what real ingestion looks like. service and env are spread over every row.
INSERT INTO kvp
SELECT toDateTime('2026-09-01') + number,
       map('service', ['checkout', 'search', 'auth', 'billing'][number % 4 + 1],
           'env',     'prod',
           'tenant',  concat('t', toString(intDiv(number, 100000))))
FROM numbers(2000000);

-- The same data with no index, to compare against.
DROP TABLE IF EXISTS kvp_plain;
CREATE TABLE kvp_plain (ts DateTime, attrs Map(String, String))
ENGINE = MergeTree ORDER BY ts;
INSERT INTO kvp_plain SELECT * FROM kvp;

SELECT name, type_full, formatReadableSize(data_compressed_bytes) AS index_size
FROM system.data_skipping_indices WHERE table = 'kvp';

SELECT '════════ 2. What it costs and what it saves ════════' AS section;

SELECT count() FROM kvp       WHERE attrs['tenant'] = 't7' SETTINGS log_comment = 'kvp_indexed';
SELECT count() FROM kvp_plain WHERE attrs['tenant'] = 't7' SETTINGS log_comment = 'kvp_plain';

SYSTEM FLUSH LOGS;

SELECT replace(log_comment, 'kvp_', '') AS table_,
       read_rows,
       formatReadableSize(read_bytes) AS read_bytes_,
       query_duration_ms
FROM system.query_log
WHERE log_comment IN ('kvp_indexed', 'kvp_plain') AND type = 'QueryFinish'
ORDER BY read_rows;

-- Expected, near enough: the indexed table reads single-digit rows and tens of
-- bytes, the plain one reads all two million and about ten megabytes.

SELECT '════════ 3. Why the indexed count reads almost nothing ════════' AS section;

-- It never opens the map column. A text index knows how many rows carry a
-- token, so count() is answered out of the index — the plan node is
-- ReadFromTextIndexCount, not ReadFromMergeTree.

EXPLAIN indexes = 1 SELECT count() FROM kvp WHERE attrs['tenant'] = 't7';

SELECT '════════ 4. A real SELECT prunes granules instead ════════' AS section;

-- Once a column other than the count is needed, the index goes back to being a
-- skip index: it drops the granules that cannot contain the token and leaves a
-- PREWHERE to recheck the survivors.

EXPLAIN indexes = 1
SELECT ts FROM kvp WHERE attrs['tenant'] = 't7' ORDER BY ts LIMIT 3;

-- Look for:
--   Skip / Name: idx_attrs / Condition: (mode: All; tokens: ["tenantt7\f"])
--   Granules: 13/245
--
-- The token is the key and the value concatenated with a separator, which is
-- why only whole-value equality can be looked up. There is no way to ask the
-- index for "keys beginning with tenant" or "values containing 7".

SELECT '════════ 5. AND of two keys: both tokens, one pass ════════' AS section;

EXPLAIN indexes = 1
SELECT count() FROM kvp WHERE attrs['tenant'] = 't7' AND attrs['service'] = 'auth';

-- Condition: (mode: All; tokens: ["serviceauth\f", "tenantt7\f"])
--
-- Both tokens have to be present in a granule for it to survive, which is why
-- an AND of two keys prunes at least as hard as either key alone.

SELECT '════════ 6. OR of two keys: mode Any ════════' AS section;

EXPLAIN indexes = 1
SELECT count() FROM kvp WHERE attrs['tenant'] = 't7' OR attrs['tenant'] = 't9';

-- Condition: (mode: Any; tokens: ["tenantt7\f", "tenantt9\f"])
--
-- 27/245 granules instead of 13 — the two tenants sit in different granules,
-- so the union of both is what survives.

SELECT '════════ 7. The predicates that do NOT reach the index ════════' AS section;

-- This is the section to read twice. All four of these are reasonable things
-- to write, all four compile, and all four scan every granule.

SELECT '-- 7a. IN is not expanded into tokens (245/245 granules)' AS note;
EXPLAIN indexes = 1 SELECT count() FROM kvp WHERE attrs['tenant'] IN ('t7', 't9');

SELECT '-- 7b. ...but the same thing written as OR is (see section 6)' AS note;

SELECT '-- 7c. LIKE on a value cannot use a whole-value token' AS note;
EXPLAIN indexes = 1 SELECT count() FROM kvp WHERE attrs['tenant'] LIKE 't7%';

SELECT '-- 7d. mapContains tests a key with no value, which is not a token' AS note;
EXPLAIN indexes = 1 SELECT count() FROM kvp WHERE mapContains(attrs, 'tenant');

SELECT '-- 7e. != cannot be answered by presence of a token' AS note;
EXPLAIN indexes = 1 SELECT count() FROM kvp WHERE attrs['tenant'] != 't7';

-- 7a is the trap worth remembering. IN and OR mean the same thing to a reader
-- and the optimizer treats them differently here, so a query that was fast
-- gets slow when someone tidies it up into an IN list.

SELECT '════════ 8. hasToken does not take a Map ════════' AS section;

-- You cannot reach past the map['key'] = 'value' form and query the tokens
-- directly the way you would with a text index over a String column:
--
--   SELECT count() FROM kvp WHERE hasToken(attrs, 'tenantt7');
--   Code: 43. Illegal type Map(String, String) of argument of function hasToken
--
-- The equality form is the whole interface.

SELECT 'see the comment above' AS note;

SELECT '════════ 9. Where the tokenizer sits among the others ════════' AS section;

SELECT groupArray(name) AS tokenizers_in_26_9 FROM (SELECT name FROM system.tokenizers ORDER BY name);

-- Cleanup left commented so you can keep poking at the tables.
-- DROP TABLE IF EXISTS kvp;
-- DROP TABLE IF EXISTS kvp_plain;
