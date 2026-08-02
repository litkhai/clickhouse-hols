-- ClickHouse 25.1: Merge Tables Unify Differing Column Types as Variant
-- New Feature: when a Merge table spans tables whose columns share a name but
--              not a type, the column is exposed as Variant instead of failing.
-- Reference: https://clickhouse.com/blog/clickhouse-release-25-01

-- Before this, a Merge table over schemas that had drifted apart was awkward:
-- the common type had to exist, or the query broke. Variant lets the union keep
-- both types and hands the reader the tools to separate them again.

-- ============================================
-- 1. Three Tables Whose Schemas Drifted
-- ============================================

SELECT '========== 1. Source Tables With Different Types ==========';

DROP TABLE IF EXISTS events_v1;
DROP TABLE IF EXISTS events_v2;
DROP TABLE IF EXISTS events_v3;

-- v1 stored the id as a number
CREATE TABLE events_v1 (event_id UInt64, user_id UInt32, payload String)
ENGINE = MergeTree ORDER BY event_id;

-- v2 switched the user id to a string (a UUID-ish key)
CREATE TABLE events_v2 (event_id UInt64, user_id String, payload String)
ENGINE = MergeTree ORDER BY event_id;

-- v3 kept the string but widened the event id
CREATE TABLE events_v3 (event_id UInt64, user_id String, payload String)
ENGINE = MergeTree ORDER BY event_id;

INSERT INTO events_v1 VALUES (1, 1001, 'legacy numeric ids'), (2, 1002, 'legacy numeric ids');
INSERT INTO events_v2 VALUES (3, 'usr-a3f1', 'migrated to string ids'), (4, 'usr-b7c2', 'migrated to string ids');
INSERT INTO events_v3 VALUES (5, 'usr-c9d4', 'current schema');

SELECT table, name AS column, type
FROM system.columns
WHERE database = currentDatabase()
  AND table IN ('events_v1', 'events_v2', 'events_v3')
  AND name = 'user_id'
ORDER BY table;

-- ============================================
-- 2. The Merge Table Produces a Variant
-- ============================================

SELECT '========== 2. Merge Exposes user_id as Variant ==========';

SELECT
    event_id,
    user_id,
    toTypeName(user_id) AS unified_type
FROM merge(currentDatabase(), '^events_v')
ORDER BY event_id;

-- ============================================
-- 3. Inspecting Which Alternative a Row Holds
-- ============================================

SELECT '========== 3. variantType and variantElement ==========';

SELECT
    event_id,
    user_id,
    variantType(user_id)                    AS holds,
    variantElement(user_id, 'UInt32')       AS as_uint32,
    variantElement(user_id, 'String')       AS as_string
FROM merge(currentDatabase(), '^events_v')
ORDER BY event_id;

-- ============================================
-- 4. Filtering by Alternative
-- ============================================

SELECT '========== 4. Rows From the Legacy Schema ==========';

SELECT event_id, user_id
FROM merge(currentDatabase(), '^events_v')
WHERE variantType(user_id) = 'UInt32'
ORDER BY event_id;

SELECT '========== 4b. Rows From the Migrated Schema ==========';

SELECT event_id, user_id
FROM merge(currentDatabase(), '^events_v')
WHERE variantType(user_id) = 'String'
ORDER BY event_id;

-- ============================================
-- 5. Normalising Back to One Type
-- ============================================

SELECT '========== 5. One Comparable Column Again ==========';

-- Casting the Variant to String gives a single key usable for grouping or
-- joining, whichever schema the row came from.
SELECT
    event_id,
    toString(user_id)      AS user_key,
    toTypeName(user_key)   AS key_type
FROM merge(currentDatabase(), '^events_v')
ORDER BY event_id;

SELECT '========== 5b. Aggregate Over the Normalised Key ==========';

SELECT
    toString(user_id) AS user_key,
    count()           AS events
FROM merge(currentDatabase(), '^events_v')
GROUP BY user_key
ORDER BY user_key;

-- ============================================
-- 6. Columns That Agree Are Left Alone
-- ============================================

SELECT '========== 6. Only the Conflicting Column Becomes Variant ==========';

SELECT
    toTypeName(event_id) AS event_id_type,
    toTypeName(user_id)  AS user_id_type,
    toTypeName(payload)  AS payload_type
FROM merge(currentDatabase(), '^events_v')
LIMIT 1;

-- ============================================
-- 7. A Merge Engine Table Follows Its Declared Schema
-- ============================================

SELECT '========== 7. Merge Engine Table vs merge() Function ==========';

DROP TABLE IF EXISTS events_all;

-- Declaring the table AS events_v2 fixes user_id to String, so the engine
-- casts each row into that type rather than inferring a Variant. The Variant
-- comes from letting the merge() function infer the schema, as above.
CREATE TABLE events_all AS events_v2
ENGINE = Merge(currentDatabase(), '^events_v');

SELECT event_id, user_id, toTypeName(user_id) AS declared_type
FROM events_all
ORDER BY event_id
LIMIT 3;

-- ============================================
-- 8. Where the Row Came From
-- ============================================

SELECT '========== 8. _table Virtual Column ==========';

SELECT
    _table,
    count()                          AS rows,
    groupArray(variantType(user_id)) AS types
FROM merge(currentDatabase(), '^events_v')
GROUP BY _table
ORDER BY _table;

-- ============================================
-- Cleanup (commented out for inspection)
-- ============================================

-- DROP TABLE IF EXISTS events_v1;
-- DROP TABLE IF EXISTS events_v2;
-- DROP TABLE IF EXISTS events_v3;
-- DROP TABLE IF EXISTS events_all;

SELECT '========== Test Complete ==========';
SELECT 'Schema drift across merged tables becomes a Variant, not an error.' AS summary;
