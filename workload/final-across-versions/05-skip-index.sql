-- settings: use_skip_indexes_if_final, use_skip_indexes_if_final_exact_mode
-- Skip indexes and FINAL on 20M rows. The bloom_filter index is on `code`. The base rows have code = number;
-- the re-insert (1% of keys, number % 100 = 0, ver 2) gives those keys code = number + 1000000000.
-- So key 5000000 has code 5000000 only in its OLD row; its newest row has code 1005000000.
-- Base is one part (OPTIMIZE ... FINAL), merges stopped, then the re-insert.

CREATE DATABASE IF NOT EXISTS final_lab;

DROP TABLE IF EXISTS final_lab.si;

-- CODEC(LZ4) on every column: same codec on every build (26.9+ would pick ZSTD(3) for this ~175 MiB part).
CREATE TABLE final_lab.si
(
    id   UInt64 CODEC(LZ4),
    code UInt64 CODEC(LZ4),
    s    String CODEC(LZ4),
    ver  UInt32 CODEC(LZ4),
    INDEX ic code TYPE bloom_filter GRANULARITY 1
)
ENGINE = ReplacingMergeTree(ver)
ORDER BY id;

INSERT INTO final_lab.si SELECT number, number, repeat('a', 20), 1 FROM numbers(20000000);

OPTIMIZE TABLE final_lab.si FINAL;

SYSTEM STOP MERGES final_lab.si;

INSERT INTO final_lab.si SELECT number, number + 1000000000, repeat('a', 20), 2 FROM numbers(20000000) WHERE number % 100 = 0;

-- probe: 05-old-default repeat=5 value
-- Correct: 0 (key 5000000 was updated, its newest row has code 1005000000).
SELECT count() FROM final_lab.si FINAL WHERE code = 5000000;

-- probe: 05-old-noindex repeat=5 value
-- Correct: 0.
SELECT count() FROM final_lab.si FINAL WHERE code = 5000000 SETTINGS use_skip_indexes_if_final = 0;

-- probe: 05-old-index-only repeat=5 value
-- Correct: 0. Only use_skip_indexes_if_final = 1, the exact-mode setting left at the build's default (or absent).
SELECT count() FROM final_lab.si FINAL WHERE code = 5000000 SETTINGS use_skip_indexes_if_final = 1;

-- probe: 05-old-index-inexact repeat=5 value
-- Correct: 0.
SELECT count() FROM final_lab.si FINAL WHERE code = 5000000 SETTINGS use_skip_indexes_if_final = 1, use_skip_indexes_if_final_exact_mode = 0;

-- probe: 05-old-index-exact repeat=5 value
-- Correct: 0.
SELECT count() FROM final_lab.si FINAL WHERE code = 5000000 SETTINGS use_skip_indexes_if_final = 1, use_skip_indexes_if_final_exact_mode = 1;

-- probe: 05-new-default repeat=5 value
-- Correct: 1 (key 5000001 was not updated).
SELECT count() FROM final_lab.si FINAL WHERE code = 5000001;

-- probe: 05-new-noindex repeat=5 value
-- Correct: 1.
SELECT count() FROM final_lab.si FINAL WHERE code = 5000001 SETTINGS use_skip_indexes_if_final = 0;

-- probe: 05-ctl-plain repeat=5 value
-- Control without FINAL. Correct: 1.
SELECT count() FROM final_lab.si WHERE code = 5000001;
