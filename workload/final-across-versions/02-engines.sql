-- FINAL on the other MergeTree engines: Collapsing, Summing, Aggregating (small tables, merges stopped).
-- Collapsing: 100,000 states, then for the 1,000 keys id % 100 = 0 a new state (+1, v + 1) and then the cancel row (-1, old v).
-- Summing: 1,000 keys a = 1, b = 1; keys 0..99 get (-1, -1) (all-zero sum), keys 100..199 get (-1, 0) (a = 0, b = 1).
-- Aggregating: two inserts over different number ranges, grouped to 1,000 keys each.

CREATE DATABASE IF NOT EXISTS final_lab;

DROP TABLE IF EXISTS final_lab.cmt;

DROP TABLE IF EXISTS final_lab.smt;

DROP TABLE IF EXISTS final_lab.amt;

CREATE TABLE final_lab.cmt
(
    id   UInt64,
    v    UInt64,
    sign Int8
)
ENGINE = CollapsingMergeTree(sign)
ORDER BY id;

SYSTEM STOP MERGES final_lab.cmt;

INSERT INTO final_lab.cmt SELECT number, number, 1 FROM numbers(100000);

INSERT INTO final_lab.cmt SELECT number, number + 1, 1 FROM numbers(100000) WHERE number % 100 = 0;

INSERT INTO final_lab.cmt SELECT number, number, -1 FROM numbers(100000) WHERE number % 100 = 0;

-- probe: 02-cmt-count-plain value
-- Correct (physical rows): 102000.
SELECT count() FROM final_lab.cmt;

-- probe: 02-cmt-count-final value
-- Correct: 100000.
SELECT count() FROM final_lab.cmt FINAL;

-- probe: 02-cmt-sum-final value
-- Correct: 4999951000 (sum 0..99999 = 4999950000, plus 1 for each of the 1000 changed keys).
SELECT sum(v) FROM final_lab.cmt FINAL;

-- probe: 02-cmt-sum-sign value
-- Correct: 4999951000 (positive control: sum(v * sign) without FINAL).
SELECT sum(v * sign) FROM final_lab.cmt;

CREATE TABLE final_lab.smt
(
    k UInt64,
    a Int64,
    b Int64
)
ENGINE = SummingMergeTree((a, b))
ORDER BY k;

SYSTEM STOP MERGES final_lab.smt;

INSERT INTO final_lab.smt SELECT number, 1, 1 FROM numbers(1000);

INSERT INTO final_lab.smt SELECT number, -1, if(number < 100, -1, 0) FROM numbers(200);

-- probe: 02-smt-count-final value
-- Correct: 1000 if FINAL keeps all-zero rows, 900 if it removes them (the data has 100 all-zero keys).
SELECT count() FROM final_lab.smt FINAL;

-- probe: 02-smt-count-suma-final value
-- Correct: count 1000 (900 if all-zero rows are removed), sum(a) 800.
SELECT count(), sum(a) FROM final_lab.smt FINAL;

-- probe: 02-smt-count-sumb-final value
-- Correct: count 1000 (900 if all-zero rows are removed), sum(b) 900.
SELECT count(), sum(b) FROM final_lab.smt FINAL;

-- probe: 02-smt-count-sumab-final value
-- Correct: count 1000 (900 if all-zero rows are removed), sum(a) 800, sum(b) 900.
SELECT count(), sum(a), sum(b) FROM final_lab.smt FINAL;

-- probe: 02-smt-zero-rows-final value
-- Correct: 100 all-zero keys if FINAL keeps them (0 if removed), sum(a) 800, sum(b) 900.
SELECT countIf(a = 0 AND b = 0), sum(a), sum(b) FROM final_lab.smt FINAL;

SYSTEM START MERGES final_lab.smt;

-- probe: 02-smt-optimize-final
OPTIMIZE TABLE final_lab.smt FINAL;

-- probe: 02-smt-count-plain-after value
-- Correct: 900 (the merge drops the 100 all-zero rows).
SELECT count() FROM final_lab.smt;

-- probe: 02-smt-count-final-after value
-- Correct: 900.
SELECT count() FROM final_lab.smt FINAL;

CREATE TABLE final_lab.amt
(
    k  UInt64,
    mx SimpleAggregateFunction(max, UInt64),
    u  AggregateFunction(uniq, UInt64)
)
ENGINE = AggregatingMergeTree
ORDER BY k;

SYSTEM STOP MERGES final_lab.amt;

INSERT INTO final_lab.amt SELECT number % 1000, max(number), uniqState(number) FROM numbers(100000) GROUP BY 1;

INSERT INTO final_lab.amt SELECT number % 1000, max(number), uniqState(number) FROM numbers(100000, 100000) GROUP BY 1;

-- probe: 02-amt-count-plain value
-- Correct (physical rows): 2000.
SELECT count() FROM final_lab.amt;

-- probe: 02-amt-count-final value
-- Correct: 1000.
SELECT count() FROM final_lab.amt FINAL;

-- probe: 02-amt-summax-final value
-- Correct: 199499500 (sum over k of the largest number below 200000 with number % 1000 = k, i.e. 199000 + k; equals the GROUP BY row below).
SELECT sum(mx) FROM final_lab.amt FINAL;

-- probe: 02-amt-summax-groupby value
-- Correct: 199499500 (same as FINAL).
SELECT sum(mx) FROM (SELECT k, max(mx) AS mx FROM final_lab.amt GROUP BY k);

-- probe: 02-amt-uniq-final value
-- Correct: about 200000 distinct numbers (uniq is approximate).
SELECT uniqMerge(u) FROM final_lab.amt FINAL;
