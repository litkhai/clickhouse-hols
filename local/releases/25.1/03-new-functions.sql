-- ClickHouse 25.1: New Functions Test
-- New Features: sequenceMatchEvents, arrayNormalizedGini, currentQueryID
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-01

-- These three were confirmed by diffing system.functions between 24.12 and
-- 25.1, so they are exactly what this release added on the function surface
-- (alongside generateSerialID, which needs Keeper and is covered in the README).

-- ============================================
-- 1. Test Data: A Funnel of User Events
-- ============================================

SELECT '========== 1. Event Data ==========';

DROP TABLE IF EXISTS funnel_events;

CREATE TABLE funnel_events
(
    user_id    UInt32,
    ts         DateTime,
    event_type String,
    amount     Float64
)
ENGINE = MergeTree
ORDER BY (user_id, ts);

-- user 1 completes the whole funnel, user 2 drops out after the click,
-- user 3 buys without adding to the cart, user 4 browses twice then completes.
INSERT INTO funnel_events VALUES
    (1, '2025-01-15 10:00:00', 'view',     0),
    (1, '2025-01-15 10:01:00', 'click',    0),
    (1, '2025-01-15 10:03:00', 'add_cart', 0),
    (1, '2025-01-15 10:07:00', 'purchase', 149.99),
    (2, '2025-01-15 11:00:00', 'view',     0),
    (2, '2025-01-15 11:02:00', 'click',    0),
    (3, '2025-01-15 12:00:00', 'view',     0),
    (3, '2025-01-15 12:01:00', 'purchase', 89.50),
    (4, '2025-01-15 13:00:00', 'view',     0),
    (4, '2025-01-15 13:05:00', 'view',     0),
    (4, '2025-01-15 13:06:00', 'click',    0),
    (4, '2025-01-15 13:20:00', 'add_cart', 0),
    (4, '2025-01-15 13:25:00', 'purchase', 249.00);

SELECT count() AS events, uniqExact(user_id) AS users FROM funnel_events;

-- ============================================
-- 2. sequenceMatchEvents — Which Events Matched
-- ============================================

SELECT '========== 2. sequenceMatchEvents ==========';

-- sequenceMatch tells you *whether* a pattern occurred. sequenceMatchEvents
-- returns the timestamps of the events that made up the match, so you can see
-- which rows the pattern actually selected.
SELECT
    user_id,
    sequenceMatchEvents('(?1)(?2)(?3)')(
        ts,
        event_type = 'view',
        event_type = 'click',
        event_type = 'purchase'
    ) AS matched_at
FROM funnel_events
GROUP BY user_id
ORDER BY user_id;

-- ============================================
-- 3. Compared With sequenceMatch
-- ============================================

SELECT '========== 3. sequenceMatch Only Says Yes or No ==========';

SELECT
    user_id,
    sequenceMatch('(?1)(?2)(?3)')(
        ts,
        event_type = 'view',
        event_type = 'click',
        event_type = 'purchase'
    ) AS matched,
    length(sequenceMatchEvents('(?1)(?2)(?3)')(
        ts,
        event_type = 'view',
        event_type = 'click',
        event_type = 'purchase'
    )) AS events_returned
FROM funnel_events
GROUP BY user_id
ORDER BY user_id;

-- ============================================
-- 4. Time Between the Matched Steps
-- ============================================

SELECT '========== 4. Funnel Duration From the Matched Events ==========';

SELECT
    user_id,
    matched_at[1] AS viewed,
    matched_at[3] AS purchased,
    dateDiff('second', matched_at[1], matched_at[3]) AS seconds_to_purchase
FROM
(
    SELECT
        user_id,
        sequenceMatchEvents('(?1)(?2)(?3)')(
            ts,
            event_type = 'view',
            event_type = 'click',
            event_type = 'purchase'
        ) AS matched_at
    FROM funnel_events
    GROUP BY user_id
)
WHERE length(matched_at) = 3
ORDER BY user_id;

-- ============================================
-- 5. arrayNormalizedGini — Ranking Quality
-- ============================================

SELECT '========== 5. arrayNormalizedGini ==========';

-- Takes predicted scores and actual labels, and returns
-- (gini_of_predictions, gini_of_a_perfect_ranking, normalized_gini).
-- The third value is the one to read: 1 means the ranking is perfect.
SELECT arrayNormalizedGini([0.9, 0.3, 0.8, 0.7], [1, 0, 1, 0]) AS perfect_ranking;

SELECT arrayNormalizedGini([0.1, 0.9, 0.2, 0.8], [1, 0, 1, 0]) AS inverted_ranking;

SELECT arrayNormalizedGini([0.5, 0.5, 0.5, 0.5], [1, 0, 1, 0]) AS no_signal;

-- ============================================
-- 6. Scoring a Model Held in a Table
-- ============================================

SELECT '========== 6. Gini Over Stored Predictions ==========';

DROP TABLE IF EXISTS model_scores;

CREATE TABLE model_scores (model String, score Float64, converted UInt8)
ENGINE = MergeTree ORDER BY model;

INSERT INTO model_scores VALUES
    ('model_a', 0.92, 1), ('model_a', 0.71, 1), ('model_a', 0.35, 0), ('model_a', 0.12, 0),
    ('model_b', 0.44, 1), ('model_b', 0.81, 0), ('model_b', 0.22, 1), ('model_b', 0.65, 0);

SELECT
    model,
    arrayNormalizedGini(groupArray(score), groupArray(converted)) AS gini,
    round(gini.3, 4) AS normalized_gini
FROM model_scores
GROUP BY model
ORDER BY normalized_gini DESC;

-- ============================================
-- 7. currentQueryID
-- ============================================

SELECT '========== 7. currentQueryID ==========';

-- Returns the id of the running query, so a result set can carry the handle
-- needed to look itself up in system.query_log afterwards.
SELECT
    currentQueryID() AS query_id,
    length(query_id) AS id_length,
    query_id != ''   AS is_populated;

-- current_query_id is the snake_case alias.
SELECT currentQueryID() = current_query_id() AS alias_matches;

-- ============================================
-- 8. Tagging Rows With the Query That Produced Them
-- ============================================

SELECT '========== 8. Carrying the Query Id Into a Result ==========';

SELECT
    currentQueryID() AS produced_by,
    event_type,
    count() AS events
FROM funnel_events
GROUP BY event_type
ORDER BY event_type;

-- ============================================
-- Cleanup (commented out for inspection)
-- ============================================

-- DROP TABLE IF EXISTS funnel_events;
-- DROP TABLE IF EXISTS model_scores;

SELECT '========== Test Complete ==========';
SELECT 'sequenceMatchEvents returns the matched rows, not just a yes or no.' AS summary;
