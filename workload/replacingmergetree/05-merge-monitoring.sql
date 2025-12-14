-- ============================================
-- ReplacingMergeTree Lab - Merge Monitoring
-- 5. Merge 지연 관찰 및 설정 확인
-- ============================================

-- 파트 상태 및 경과 시간 확인
SELECT
    name,
    rows,
    formatReadableSize(bytes_on_disk) as size,
    modification_time,
    now() as current_time,
    dateDiff('second', modification_time, now()) as age_seconds
FROM system.parts
WHERE database = 'blog_test'
    AND table = 'user_events_large'
    AND active = 1
ORDER BY modification_time;

-- 현재 진행 중인 merge 확인
SELECT
    database,
    table,
    elapsed,
    progress,
    num_parts,
    total_size_bytes_compressed,
    merge_type
FROM system.merges
WHERE database = 'blog_test';

-- Merge 히스토리 확인
SELECT
    event_type,
    event_time,
    table,
    part_name,
    merged_from,
    rows,
    duration_ms
FROM system.part_log
WHERE database = 'blog_test'
    AND event_time > now() - INTERVAL 1 HOUR
ORDER BY event_time DESC
LIMIT 30;

-- Merge 관련 세션 설정
SELECT name, value, description
FROM system.settings
WHERE name LIKE '%merge%'
    AND name NOT LIKE '%storage%'
ORDER BY name
LIMIT 20;

-- MergeTree 테이블 설정
SELECT name, value
FROM system.merge_tree_settings
WHERE name LIKE '%merge%'
ORDER BY name
LIMIT 30;

-- 강제 merge 관련 설정
SELECT name, value
FROM system.merge_tree_settings
WHERE name LIKE '%age%force%' OR name LIKE '%interval%'
ORDER BY name;

-- Background pool 설정
SELECT name, value
FROM system.merge_tree_settings
WHERE name LIKE '%background%' OR name LIKE '%pool%';
