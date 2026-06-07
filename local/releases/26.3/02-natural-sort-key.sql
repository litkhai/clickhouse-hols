-- ClickHouse 26.3 LTS: naturalSortKey Function Test
-- New Feature: naturalSortKey(s) produces a sort key for human-friendly ordering
--              (digits compared numerically, e.g. 'file2' < 'file10')
-- Reference: https://github.com/ClickHouse/ClickHouse/pull/90322

-- ============================================
-- 1. The Problem: Default Lexical Sort
-- ============================================

SELECT '========== 1. Lexical Sort Puts "10" Before "2" ==========';

SELECT name
FROM (
    SELECT arrayJoin(['file1', 'file2', 'file10', 'file20', 'file100', 'file3']) AS name
)
ORDER BY name;

-- ============================================
-- 2. The Fix: naturalSortKey
-- ============================================

SELECT '========== 2. Natural Sort Order ==========';

SELECT name
FROM (
    SELECT arrayJoin(['file1', 'file2', 'file10', 'file20', 'file100', 'file3']) AS name
)
ORDER BY naturalSortKey(name);

-- ============================================
-- 3. Inspect the Key Itself
-- ============================================

SELECT '========== 3. naturalSortKey Output ==========';

SELECT
    name,
    hex(naturalSortKey(name)) AS key_hex
FROM (
    SELECT arrayJoin(['v1.2', 'v1.10', 'v2.1', 'v10.0', 'v1.2.3']) AS name
)
ORDER BY naturalSortKey(name);

-- ============================================
-- 4. Software Version Strings
-- ============================================

SELECT '========== 4. Sorting Software Versions ==========';

DROP TABLE IF EXISTS releases;
CREATE TABLE releases (version String, released Date) ENGINE = MergeTree() ORDER BY released;

INSERT INTO releases VALUES
    ('25.5',  '2025-05-29'),
    ('25.6',  '2025-06-30'),
    ('25.10', '2025-10-30'),
    ('25.11', '2025-11-27'),
    ('25.12', '2025-12-18'),
    ('26.1',  '2026-01-29'),
    ('26.2',  '2026-02-26'),
    ('26.3',  '2026-03-26'),
    ('26.4',  '2026-04-30'),
    ('26.5',  '2026-05-21');

-- Lexical sort puts 25.10 before 25.5 — WRONG
SELECT 'Lexical (broken):' AS sort_type, version, released
FROM releases
ORDER BY version
LIMIT 10;

-- Natural sort puts 25.5 before 25.10 — CORRECT
SELECT 'Natural (correct):' AS sort_type, version, released
FROM releases
ORDER BY naturalSortKey(version)
LIMIT 10;

-- ============================================
-- 5. File-Name-Style Mixed Content
-- ============================================

SELECT '========== 5. Mixed File Names with Padding ==========';

WITH files AS (
    SELECT arrayJoin([
        'log-2026-1.txt',
        'log-2026-10.txt',
        'log-2026-2.txt',
        'log-2026-100.txt',
        'log-2025-12.txt',
        'log-2026-3.txt'
    ]) AS name
)
SELECT name, naturalSortKey(name) AS sort_key
FROM files
ORDER BY naturalSortKey(name);

-- ============================================
-- 6. Use as ORDER BY Key in a MergeTree Table
-- ============================================

SELECT '========== 6. naturalSortKey as Stored Column ==========';

DROP TABLE IF EXISTS chapters;
CREATE TABLE chapters (
    title String,
    sort_key String MATERIALIZED naturalSortKey(title)
) ENGINE = MergeTree() ORDER BY sort_key;

INSERT INTO chapters (title) VALUES
    ('Chapter 1'),
    ('Chapter 10'),
    ('Chapter 2'),
    ('Chapter 20'),
    ('Chapter 100'),
    ('Chapter 3'),
    ('Chapter 11');

-- Stored order respects the materialized natural sort key
SELECT title FROM chapters ORDER BY sort_key;

-- ============================================
-- 7. Mixed Case Sensitivity & Padding
-- ============================================

SELECT '========== 7. Comparing Mixed-Case Identifiers ==========';

SELECT name
FROM (
    SELECT arrayJoin(['Alpha-1', 'alpha-2', 'Alpha-10', 'beta-3', 'Beta-1', 'Beta-20']) AS name
)
ORDER BY naturalSortKey(name);

-- ============================================
-- Cleanup (commented out for inspection)
-- ============================================

-- DROP TABLE IF EXISTS releases;
-- DROP TABLE IF EXISTS chapters;

SELECT '========== Test Complete ==========';
SELECT 'naturalSortKey enables human-friendly ordering of mixed letter/number strings.' AS summary;
