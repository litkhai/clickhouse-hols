-- ============================================
-- ReplacingMergeTree Lab - Basic Operations
-- 2. 기본 실험 - FINAL 키워드 검증
-- ============================================

-- 테이블 초기화 (재실행 시)
TRUNCATE TABLE blog_test.user_events_replacing;

-- 첫 번째 삽입: 초기 데이터
INSERT INTO blog_test.user_events_replacing (user_id, event_type, event_value, updated_at)
VALUES
    (1, 'login', 100, '2024-01-01 10:00:00'),
    (2, 'login', 200, '2024-01-01 10:00:00'),
    (3, 'login', 300, '2024-01-01 10:00:00');

-- 두 번째 삽입: 동일 키에 업데이트된 값 (별도 파트 생성)
INSERT INTO blog_test.user_events_replacing (user_id, event_type, event_value, updated_at)
VALUES
    (1, 'login', 150, '2024-01-01 11:00:00'),
    (2, 'login', 250, '2024-01-01 11:00:00');

-- 세 번째 삽입: 또 다른 업데이트
INSERT INTO blog_test.user_events_replacing (user_id, event_type, event_value, updated_at)
VALUES
    (1, 'login', 999, '2024-01-01 12:00:00');

-- FINAL 없이 조회 (중복 행 노출)
SELECT
    user_id,
    event_type,
    event_value,
    updated_at,
    _part
FROM blog_test.user_events_replacing
ORDER BY user_id, updated_at;

-- FINAL 키워드 사용 조회 (중복 제거된 최신 결과)
SELECT
    user_id,
    event_type,
    event_value,
    updated_at
FROM blog_test.user_events_replacing FINAL
ORDER BY user_id;

-- 현재 파트 상태 확인
SELECT
    name,
    rows,
    bytes_on_disk,
    modification_time,
    active
FROM system.parts
WHERE database = 'blog_test'
    AND table = 'user_events_replacing'
    AND active = 1
ORDER BY name;
