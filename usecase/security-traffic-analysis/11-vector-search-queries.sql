-- ============================================================
-- Bug Bounty Vector Search - Step 4: Query Practice
-- 다양한 Vector Search 쿼리 실습
-- ============================================================

USE bug_bounty;

-- ============================================================
-- PART 1: 유사 공격 패턴 탐지
-- ============================================================

-- 1-1. 특정 요청과 가장 유사한 공격 패턴 찾기
-- 새로운 의심스러운 요청이 알려진 공격 패턴과 얼마나 유사한지 확인
SELECT
    r.packet_id,
    r.normalized_request,
    s.pattern_name,
    s.category,
    s.severity,
    s.cwe_id,
    round(cosineDistance(r.request_embedding, s.payload_embedding), 4) as distance,
    round(1 - cosineDistance(r.request_embedding, s.payload_embedding), 4) as similarity_score
FROM bug_bounty.request_embeddings r
CROSS JOIN bug_bounty.attack_signatures s
WHERE r.packet_id IN (
    SELECT packet_id FROM bug_bounty.request_embeddings LIMIT 1
)
ORDER BY distance ASC
LIMIT 5
FORMAT PrettyCompactMonoBlock;


-- 1-2. 모든 요청에 대해 가장 가까운 공격 패턴 찾기 (TOP-1)
-- 각 요청마다 가장 유사한 공격 유형 매칭
SELECT
    r.packet_id,
    substring(r.normalized_request, 1, 80) as request_preview,
    argMin(s.pattern_name, cosineDistance(r.request_embedding, s.payload_embedding)) as closest_pattern,
    argMin(s.category, cosineDistance(r.request_embedding, s.payload_embedding)) as attack_category,
    round(min(cosineDistance(r.request_embedding, s.payload_embedding)), 4) as min_distance
FROM bug_bounty.request_embeddings r
CROSS JOIN bug_bounty.attack_signatures s
GROUP BY r.packet_id, r.normalized_request
HAVING min_distance < 0.5  -- 유사도 임계값 (거리가 0.5 미만인 것만)
ORDER BY min_distance ASC
LIMIT 10
FORMAT PrettyCompactMonoBlock;


-- 1-3. 공격 카테고리별 매칭 요청 수 집계
-- 어떤 유형의 공격이 가장 많이 탐지되었는지 확인
WITH matched_attacks AS (
    SELECT
        r.packet_id,
        argMin(s.category, cosineDistance(r.request_embedding, s.payload_embedding)) as attack_category,
        min(cosineDistance(r.request_embedding, s.payload_embedding)) as min_distance
    FROM bug_bounty.request_embeddings r
    CROSS JOIN bug_bounty.attack_signatures s
    GROUP BY r.packet_id
    HAVING min_distance < 0.6
)
SELECT
    attack_category,
    count() as detection_count,
    round(avg(min_distance), 4) as avg_distance,
    round(min(min_distance), 4) as closest_match
FROM matched_attacks
GROUP BY attack_category
ORDER BY detection_count DESC
FORMAT PrettyCompactMonoBlock;


-- 1-4. 고위험 패턴 매칭 (CRITICAL/HIGH severity만)
-- 심각도가 높은 공격 패턴과 유사한 요청만 필터링
SELECT
    r.packet_id,
    substring(r.normalized_request, 1, 60) as request,
    s.pattern_name,
    s.severity,
    s.cvss_score,
    round(cosineDistance(r.request_embedding, s.payload_embedding), 4) as distance
FROM bug_bounty.request_embeddings r
CROSS JOIN bug_bounty.attack_signatures s
WHERE s.severity IN ('CRITICAL', 'HIGH')
  AND cosineDistance(r.request_embedding, s.payload_embedding) < 0.4  -- 높은 유사도만
ORDER BY s.cvss_score DESC, distance ASC
LIMIT 10
FORMAT PrettyCompactMonoBlock;


-- ============================================================
-- PART 2: 중복 리포트 탐지
-- ============================================================

-- 2-1. 특정 리포트와 유사한 기존 리포트 찾기
-- 새로운 리포트가 제출되었을 때 중복 여부 확인
WITH target_report AS (
    SELECT report_id, content_embedding
    FROM bug_bounty.report_knowledge_base
    WHERE report_id = 'RPT-2024-007'  -- 새로 제출된 리포트
)
SELECT
    r.report_id,
    r.title,
    r.vulnerability_type,
    r.status,
    r.bounty_amount,
    round(cosineDistance(r.content_embedding, t.content_embedding), 4) as distance,
    round(1 - cosineDistance(r.content_embedding, t.content_embedding), 4) as similarity
FROM bug_bounty.report_knowledge_base r
CROSS JOIN target_report t
WHERE r.report_id != t.report_id
  AND r.status IN ('ACCEPTED', 'FIXED', 'TRIAGED')  -- 유효한 리포트만
ORDER BY distance ASC
LIMIT 5
FORMAT PrettyCompactMonoBlock;


-- 2-2. 중복 가능성 높은 리포트 쌍 찾기
-- 시스템에 있는 모든 리포트 중 서로 유사한 것들 찾기
SELECT
    r1.report_id as report_1,
    r1.title as title_1,
    r1.status as status_1,
    r2.report_id as report_2,
    r2.title as title_2,
    r2.status as status_2,
    round(cosineDistance(r1.content_embedding, r2.content_embedding), 4) as distance
FROM bug_bounty.report_knowledge_base r1
CROSS JOIN bug_bounty.report_knowledge_base r2
WHERE r1.report_id < r2.report_id  -- 중복 조합 제거
  AND r1.vulnerability_type = r2.vulnerability_type  -- 같은 취약점 유형만
  AND cosineDistance(r1.content_embedding, r2.content_embedding) < 0.3  -- 높은 유사도
  AND r2.status != 'DUPLICATE'  -- 이미 중복으로 마크되지 않은 것
ORDER BY distance ASC
LIMIT 10
FORMAT PrettyCompactMonoBlock;


-- 2-3. 취약점 유형별 중복 리포트 비율
-- 어떤 유형의 취약점이 중복 리포트가 많은지 분석
SELECT
    vulnerability_type,
    count() as total_reports,
    countIf(status = 'DUPLICATE') as duplicate_count,
    round(countIf(status = 'DUPLICATE') * 100.0 / count(), 2) as duplicate_percentage,
    sum(bounty_amount) as total_paid
FROM bug_bounty.report_knowledge_base
GROUP BY vulnerability_type
ORDER BY duplicate_percentage DESC
FORMAT PrettyCompactMonoBlock;


-- ============================================================
-- PART 3: 시맨틱 검색
-- ============================================================

-- 3-1. 자연어 쿼리로 관련 리포트 검색
-- "authentication bypass" 관련 리포트 찾기 (mock embedding 사용)
WITH query_embedding AS (
    -- 실제로는 쿼리 텍스트를 임베딩 API로 변환해야 함
    -- 여기서는 데모용으로 기존 SQLi 패턴 사용
    SELECT bug_bounty.generateSQLiVector(999) as embedding
)
SELECT
    r.report_id,
    r.title,
    r.vulnerability_type,
    r.status,
    r.bounty_amount,
    round(cosineDistance(r.content_embedding, q.embedding), 4) as relevance_score
FROM bug_bounty.report_knowledge_base r
CROSS JOIN query_embedding q
WHERE cosineDistance(r.content_embedding, q.embedding) < 0.8  -- 관련성 임계값
ORDER BY relevance_score ASC
LIMIT 10
FORMAT PrettyCompactMonoBlock;


-- 3-2. 키워드와 벡터 검색 결합
-- 전통적인 텍스트 검색과 시맨틱 검색 결합하여 정확도 향상
WITH query_embedding AS (
    SELECT bug_bounty.generateXSSVector(888) as embedding
)
SELECT
    r.report_id,
    r.title,
    r.description,
    r.vulnerability_type,
    r.bounty_amount,
    -- 키워드 매칭 점수
    multiIf(
        positionCaseInsensitive(r.title, 'XSS') > 0, 1.0,
        positionCaseInsensitive(r.description, 'script') > 0, 0.8,
        positionCaseInsensitive(r.description, 'injection') > 0, 0.6,
        0.0
    ) as keyword_score,
    -- 벡터 유사도 점수
    round(1 - cosineDistance(r.content_embedding, q.embedding), 4) as semantic_score,
    -- 최종 점수 (가중 평균)
    round(keyword_score * 0.3 + (1 - cosineDistance(r.content_embedding, q.embedding)) * 0.7, 4) as final_score
FROM bug_bounty.report_knowledge_base r
CROSS JOIN query_embedding q
WHERE final_score > 0.5
ORDER BY final_score DESC
LIMIT 10
FORMAT PrettyCompactMonoBlock;


-- 3-3. 고액 바운티 리포트와 유사한 패턴 찾기
-- 과거 고액 바운티를 받은 리포트와 유사한 새 리포트 우선순위화
WITH high_bounty_reports AS (
    SELECT content_embedding
    FROM bug_bounty.report_knowledge_base
    WHERE bounty_amount >= 3000
)
SELECT
    r.report_id,
    r.title,
    r.vulnerability_type,
    r.status,
    r.bounty_amount,
    round(avg(cosineDistance(r.content_embedding, h.content_embedding)), 4) as avg_distance_to_high_bounty
FROM bug_bounty.report_knowledge_base r
CROSS JOIN high_bounty_reports h
WHERE r.status IN ('SUBMITTED', 'TRIAGED')  -- 아직 처리 중인 리포트
  AND r.bounty_amount = 0  -- 아직 바운티 결정 안됨
GROUP BY r.report_id, r.title, r.vulnerability_type, r.status, r.bounty_amount
ORDER BY avg_distance_to_high_bounty ASC
LIMIT 10
FORMAT PrettyCompactMonoBlock;


-- ============================================================
-- PART 4: 클러스터링 및 패턴 분석
-- ============================================================

-- 4-1. 공격 시그니처 클러스터링
-- 유사한 공격 패턴끼리 그룹화
SELECT
    s1.signature_id,
    s1.pattern_name,
    s1.category,
    groupArray((s2.pattern_name, round(cosineDistance(s1.payload_embedding, s2.payload_embedding), 3)))
        as similar_patterns
FROM bug_bounty.attack_signatures s1
LEFT JOIN bug_bounty.attack_signatures s2
    ON s1.signature_id != s2.signature_id
    AND cosineDistance(s1.payload_embedding, s2.payload_embedding) < 0.5
GROUP BY s1.signature_id, s1.pattern_name, s1.category
HAVING length(similar_patterns) > 0
ORDER BY length(similar_patterns) DESC
LIMIT 5
FORMAT PrettyCompactMonoBlock;


-- 4-2. 리포트 임베딩의 평균 벡터 계산 (프로토타입)
-- 특정 취약점 유형의 "전형적인" 패턴 계산
SELECT
    vulnerability_type,
    count() as report_count,
    -- 평균 벡터 계산 (centroid)
    arrayReduce('avg', groupArray(content_embedding)) as centroid_embedding,
    length(arrayReduce('avg', groupArray(content_embedding))) as centroid_dim
FROM bug_bounty.report_knowledge_base
WHERE status IN ('ACCEPTED', 'FIXED')
GROUP BY vulnerability_type
ORDER BY report_count DESC
FORMAT PrettyCompactMonoBlock;


-- 4-3. 이상치 탐지 (Outlier Detection)
-- 정상 패턴에서 크게 벗어난 요청 찾기
WITH normal_centroid AS (
    SELECT arrayReduce('avg', groupArray(request_embedding)) as centroid
    FROM bug_bounty.request_embeddings
    LIMIT 100  -- 정상 트래픽 샘플
)
SELECT
    r.packet_id,
    substring(r.normalized_request, 1, 80) as request,
    round(cosineDistance(r.request_embedding, c.centroid), 4) as distance_from_normal
FROM bug_bounty.request_embeddings r
CROSS JOIN normal_centroid c
ORDER BY distance_from_normal DESC
LIMIT 10
FORMAT PrettyCompactMonoBlock;


-- ============================================================
-- PART 5: 실전 활용 쿼리
-- ============================================================

-- 5-1. 실시간 위협 스코어링 시스템
-- Vector Search와 기존 공격 탐지 결합
WITH vector_threat_scores AS (
    SELECT
        r.packet_id,
        min(cosineDistance(r.request_embedding, s.payload_embedding)) as min_distance,
        argMin(s.category, cosineDistance(r.request_embedding, s.payload_embedding)) as matched_category,
        argMin(s.cvss_score, cosineDistance(r.request_embedding, s.payload_embedding)) as matched_cvss
    FROM bug_bounty.request_embeddings r
    CROSS JOIN bug_bounty.attack_signatures s
    GROUP BY r.packet_id
)
SELECT
    p.packet_id,
    p.source_ip,
    p.request_uri,
    p.request_method,
    -- Vector Search 기반 위협 점수
    round(1 - v.min_distance, 4) as vector_threat_score,
    v.matched_category,
    v.matched_cvss,
    -- 기존 휴리스틱 점수 (있다면)
    COALESCE(a.bruteforce_score, 0) as bruteforce_score,
    COALESCE(a.scanner_score, 0) as scanner_score,
    -- 최종 종합 점수
    round(
        (1 - v.min_distance) * 0.5 +
        COALESCE(a.bruteforce_score, 0) * 0.3 +
        COALESCE(a.scanner_score, 0) * 0.2,
    4) as final_threat_score
FROM bug_bounty.http_packets p
JOIN vector_threat_scores v ON p.packet_id = v.packet_id
LEFT JOIN bug_bounty.attack_detection_agg a ON a.source_ip_hash = cityHash64(p.source_ip)
WHERE v.min_distance < 0.5  -- 유사도 필터
ORDER BY final_threat_score DESC
LIMIT 20
FORMAT PrettyCompactMonoBlock;


-- 5-2. 자동 트리아지 우선순위 추천
-- 새 리포트에 우선순위를 자동으로 부여
WITH new_reports AS (
    SELECT * FROM bug_bounty.report_knowledge_base
    WHERE status = 'SUBMITTED'
),
historical_patterns AS (
    SELECT
        vulnerability_type,
        avg(bounty_amount) as avg_bounty,
        count() as historical_count
    FROM bug_bounty.report_knowledge_base
    WHERE status IN ('ACCEPTED', 'FIXED')
    GROUP BY vulnerability_type
)
SELECT
    nr.report_id,
    nr.title,
    nr.vulnerability_type,
    -- 히스토리 기반 예상 바운티
    COALESCE(hp.avg_bounty, 0) as expected_bounty,
    -- 과거 고액 리포트와의 유사도
    (SELECT round(min(cosineDistance(nr.content_embedding, hr.content_embedding)), 4)
     FROM bug_bounty.report_knowledge_base hr
     WHERE hr.bounty_amount >= 3000) as similarity_to_high_bounty,
    -- 최근 중복 가능성
    (SELECT count()
     FROM bug_bounty.report_knowledge_base dr
     WHERE dr.status != 'DUPLICATE'
       AND dr.vulnerability_type = nr.vulnerability_type
       AND cosineDistance(nr.content_embedding, dr.content_embedding) < 0.3) as potential_duplicates,
    -- 우선순위 점수
    multiIf(
        COALESCE(hp.avg_bounty, 0) >= 3000, 'HIGH',
        COALESCE(hp.avg_bounty, 0) >= 1500, 'MEDIUM',
        'LOW'
    ) as recommended_priority
FROM new_reports nr
LEFT JOIN historical_patterns hp ON nr.vulnerability_type = hp.vulnerability_type
ORDER BY expected_bounty DESC
FORMAT PrettyCompactMonoBlock;


-- 5-3. 공격 트렌드 분석
-- 시간에 따른 공격 패턴 변화 추적
SELECT
    toStartOfWeek(r.created_at) as week,
    argMin(s.category, cosineDistance(r.request_embedding, s.payload_embedding)) as attack_type,
    count() as detection_count,
    round(avg(1 - cosineDistance(r.request_embedding, s.payload_embedding)), 4) as avg_confidence
FROM bug_bounty.request_embeddings r
CROSS JOIN bug_bounty.attack_signatures s
WHERE cosineDistance(r.request_embedding, s.payload_embedding) < 0.6
GROUP BY week, attack_type
ORDER BY week DESC, detection_count DESC
FORMAT PrettyCompactMonoBlock;


-- ============================================================
-- PART 6: 성능 및 정확도 분석
-- ============================================================

-- 6-1. Vector Search vs 전통적 패턴 매칭 비교
-- (실제 시나리오에서는 ground truth 데이터 필요)
SELECT
    'Vector Search' as method,
    count(DISTINCT r.packet_id) as suspicious_requests,
    round(avg(1 - cosineDistance(r.request_embedding, s.payload_embedding)), 4) as avg_confidence
FROM bug_bounty.request_embeddings r
CROSS JOIN bug_bounty.attack_signatures s
WHERE cosineDistance(r.request_embedding, s.payload_embedding) < 0.5

UNION ALL

SELECT
    'Traditional Pattern' as method,
    count(DISTINCT packet_id) as suspicious_requests,
    0.0 as avg_confidence  -- 전통적 방법은 신뢰도 점수 없음
FROM bug_bounty.http_packets
WHERE request_uri LIKE '%OR%'
   OR request_uri LIKE '%<script%'
   OR request_uri LIKE '%../../%'
FORMAT PrettyCompactMonoBlock;


-- 6-2. 임베딩 품질 검증
-- 같은 카테고리끼리는 가까워야 하고, 다른 카테고리끼리는 멀어야 함
WITH intra_category_distance AS (
    SELECT
        'Same Category' as comparison,
        round(avg(cosineDistance(s1.payload_embedding, s2.payload_embedding)), 4) as avg_distance
    FROM bug_bounty.attack_signatures s1
    JOIN bug_bounty.attack_signatures s2
        ON s1.category = s2.category
        AND s1.signature_id < s2.signature_id
),
inter_category_distance AS (
    SELECT
        'Different Category' as comparison,
        round(avg(cosineDistance(s1.payload_embedding, s2.payload_embedding)), 4) as avg_distance
    FROM bug_bounty.attack_signatures s1
    JOIN bug_bounty.attack_signatures s2
        ON s1.category != s2.category
        AND s1.signature_id < s2.signature_id
)
SELECT * FROM intra_category_distance
UNION ALL
SELECT * FROM inter_category_distance
FORMAT PrettyCompactMonoBlock;


-- ============================================================
-- 요약 및 다음 단계
-- ============================================================
/*
이 쿼리들을 통해 다음을 학습했습니다:

1. 유사 공격 패턴 탐지: cosineDistance를 사용한 벡터 유사도 계산
2. 중복 리포트 탐지: 시맨틱 유사도 기반 중복 식별
3. 시맨틱 검색: 자연어 쿼리로 관련 콘텐츠 찾기
4. 클러스터링: 유사 패턴 그룹화 및 이상치 탐지
5. 하이브리드 접근: 전통적 방법과 Vector Search 결합

다음 단계:
- 12-vector-integration.sql: Python 통합 및 실전 임베딩 생성
- 실제 OpenAI API 또는 Sentence Transformers 사용
- 프로덕션 환경 배포 고려사항
*/


-- ============================================================
-- 다음 단계
-- ============================================================
-- 12-vector-integration.sql: Python/API 통합 및 실전 활용
-- ============================================================
