-- settings: use_skip_indexes_if_final, use_skip_indexes_if_final_exact_mode
-- Skip index under FINAL (small; the full matrix is in final-across-versions/05-skip-index.sql). 1,000,000 rows.
-- Base: code = number, ver 1, one part, merges stopped. Re-insert 1% (number % 100 = 0) with code = number + 1000000000, ver 2.
-- So key 500000 has code 500000 only in its OLD row; key 500001 was not updated.
-- CODEC(LZ4) on every column: same codec on every build (26.9+ would pick ZSTD(3) for a part of 100 MiB or more (this one is small, the pin is for consistency), ClickHouse#108786;
-- older builds write LZ4), so sizes and timings do not compare codecs as well as builds.

CREATE DATABASE IF NOT EXISTS index_lab;

DROP TABLE IF EXISTS index_lab.fi;

CREATE TABLE index_lab.fi
(
    id UInt64 CODEC(LZ4),
    code UInt64 CODEC(LZ4),
    ver UInt32 CODEC(LZ4),
    INDEX ic code TYPE bloom_filter GRANULARITY 1
)
ENGINE = ReplacingMergeTree(ver)
ORDER BY id;

INSERT INTO index_lab.fi SELECT number, number, 1 FROM numbers(1000000);

OPTIMIZE TABLE index_lab.fi FINAL;

SYSTEM STOP MERGES index_lab.fi;

INSERT INTO index_lab.fi SELECT number, number + 1000000000, 2 FROM numbers(1000000) WHERE number % 100 = 0;

-- probe: 06-old value
-- Correct: 0 (the newest row of key 500000 has another code)
SELECT count() FROM index_lab.fi FINAL WHERE code = 500000;

-- probe: 06-old-g value
-- Granules read for 06-old (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.fi FINAL WHERE code = 500000))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 06-new value
-- Correct: 1 (key 500001 was not updated)
SELECT count() FROM index_lab.fi FINAL WHERE code = 500001;

-- probe: 06-new-g value
-- Granules read for 06-new (data-dependent; the point is the granules read).
SELECT arrayStringConcat(groupArray(e), ' ') FROM (SELECT trimBoth(replaceRegexpAll(explain, '^[ │└├─]+', '')) AS e FROM (EXPLAIN indexes = 1 SELECT count() FROM index_lab.fi FINAL WHERE code = 500001))
WHERE e LIKE 'Granules:%' OR e IN ('PrimaryKey', 'Skip', 'MinMax', 'Partition')
   OR e LIKE 'Name:%' OR e LIKE 'Search Algorithm:%';

-- probe: 06-old-noidx value
-- Correct: 0
SELECT count() FROM index_lab.fi FINAL WHERE code = 500000 SETTINGS use_skip_indexes_if_final = 0;
