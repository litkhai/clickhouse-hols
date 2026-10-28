-- ClickHouse 26.10 — XGBoost dictionaries (experimental)
--
--   CREATE DICTIONARY m (f1 Float64, f2 Float64, target Float64)
--   PRIMARY KEY (f1, f2) SOURCE(CLICKHOUSE(DB 'xg' TABLE 'train'))
--   LAYOUT(XGBOOST(objective 'binary:logistic' num_iterations 100 max_depth 4))
--   LIFETIME(0);
--   SELECT predictXGBoost('m', f1, f2);
--
-- A dictionary that holds a model instead of rows. Loading it trains a
-- gradient-boosted model on the source table; predictXGBoost runs it. The key
-- columns are the features, in order, and the one attribute is the target.
--
-- What to know before you build on it:
--
--   * training happens on every load, including a server restart. The model is
--     not persisted. SYSTEM RELOAD DICTIONARY retrains on the current rows.
--   * the whole training set is held in memory while it trains.
--   * dictGet and SELECT * FROM the dictionary do not work; predictXGBoost is
--     the only way in, and it needs enable_xgboost = 1 on every query.
--   * trees do not extrapolate. Section 4 asks for a value ten times outside the
--     training range and gets a tenth of the right answer.
--   * not in ClickHouse Cloud, per the layout's documentation.

SET enable_xgboost = 1;

DROP DATABASE IF EXISTS xg;
CREATE DATABASE xg;
USE xg;

SELECT '════════ 1. A classification problem with a known answer ════════' AS section;

-- Will a delivery be late? Late when distance and basket size are both high, or
-- in the evening rush, with a 5% label flip so the model cannot be perfect.
CREATE TABLE deliveries
(
    id          UInt64,
    distance_km Float64,
    items       Float64,
    hour        Float64,
    late        Float64
)
ENGINE = MergeTree ORDER BY id;

INSERT INTO deliveries
SELECT number,
       (sipHash64(number, 0) % 200) / 10.0            AS distance_km,
       sipHash64(number, 1) % 30                      AS items,
       sipHash64(number, 2) % 24                      AS hour,
       xor((distance_km > 12 AND items > 15) OR (hour BETWEEN 17 AND 19),
           sipHash64(number, 3) % 100 < 5)            AS late
FROM numbers(50000);

-- 80/20 split on a hash of the id, so it is stable across runs.
CREATE VIEW train AS SELECT distance_km, items, hour, late FROM deliveries WHERE id % 5 != 0;
CREATE VIEW test  AS SELECT distance_km, items, hour, late FROM deliveries WHERE id % 5  = 0;

SELECT (SELECT count() FROM train) AS train_rows, (SELECT count() FROM test) AS test_rows,
       round((SELECT avg(late) FROM deliveries), 3) AS late_share;

SELECT '════════ 2. Train ════════' AS section;

CREATE DICTIONARY late_model (distance_km Float64, items Float64, hour Float64, late Float64)
PRIMARY KEY (distance_km, items, hour)
SOURCE(CLICKHOUSE(DB 'xg' TABLE 'train'))
LAYOUT(XGBOOST(objective 'binary:logistic' num_iterations 100 max_depth 4))
LIFETIME(0);

-- Dictionaries load lazily; the first predictXGBoost would train it. Load it now
-- so system.dictionaries has something to show.
SYSTEM RELOAD DICTIONARY late_model;

-- element_count and bytes_allocated are 0: there are no rows, and XGBoost does
-- not report the model's memory.
SELECT status, element_count, bytes_allocated, round(loading_duration, 2) AS train_seconds
FROM system.dictionaries WHERE name = 'late_model';

SELECT '════════ 3. Score the held-out 20% ════════' AS section;

-- With binary:logistic the prediction is a probability.
SELECT distance_km, items, hour, late,
       round(predictXGBoost('late_model', distance_km, items, hour), 3) AS p_late
FROM test ORDER BY sipHash64(distance_km, items, hour) LIMIT 5;

-- Accuracy at 0.5 and ROC AUC, against two baselines: always "on time", and the
-- rule that generated the data minus the noise. The 5% flip caps accuracy at
-- about 0.95, so a model near that has learned the rule.
WITH predictXGBoost('late_model', distance_km, items, hour) AS p
SELECT round(avg((p > 0.5) = (late = 1)), 4)                  AS model_accuracy,
       round(arrayAUC(groupArray(p), groupArray(late)), 4)    AS model_auc,
       round(avg(late = 0), 4)                                AS always_on_time,
       round(avg(((distance_km > 12 AND items > 15) OR (hour BETWEEN 17 AND 19)) = (late = 1)), 4) AS true_rule
FROM test;

SELECT '════════ 4. Trees do not extrapolate ════════' AS section;

-- A regressor on y = 2*x1 + 3*x2 for x1 in [0, 99]: right inside the range,
-- capped at the largest leaf outside it.
CREATE TABLE linear (x1 Float64, x2 Float64, y Float64) ENGINE = MergeTree ORDER BY tuple();
INSERT INTO linear SELECT number AS x1, number * 2 AS x2, 2 * x1 + 3 * x2 AS y FROM numbers(100);

CREATE DICTIONARY linear_model (x1 Float64, x2 Float64, y Float64)
PRIMARY KEY (x1, x2) SOURCE(CLICKHOUSE(DB 'xg' TABLE 'linear'))
LAYOUT(XGBOOST(objective 'reg:squarederror' num_iterations 100 max_depth 6))
LIFETIME(0);

SELECT x1, x2, 2 * x1 + 3 * x2 AS truth, round(predictXGBoost('linear_model', x1, x2), 2) AS predicted
FROM values('x1 Float64, x2 Float64', (1, 2), (50, 100), (99, 198), (1000, 2000))
ORDER BY x1;

SELECT '════════ 5. Retraining is a reload ════════' AS section;

-- Add rows outside the old range and reload: the same call now answers 8000.
INSERT INTO linear SELECT number AS x1, number * 2 AS x2, 2 * x1 + 3 * x2 AS y FROM numbers(100, 1000);
SYSTEM RELOAD DICTIONARY linear_model;
SELECT round(predictXGBoost('linear_model', 1000., 2000.), 2) AS predicted_after_retrain, 8000 AS truth;
