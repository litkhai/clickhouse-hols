# ClickHouse Deduplication Test Results

**테스트 일시**: 2024-12-16
**ClickHouse 버전**: 25.10.1.6953
**환경**: ClickHouse Cloud (AWS ap-northeast-2)
**테스트 데이터**: 10,000 unique records + 30% duplicates (total: 13,000)

---

## 📊 Phase 1: Engine 비교 테스트 결과

### 목적
동일한 중복 데이터에 대해 각 Table Engine의 deduplication 효과 비교

### 실행 결과

| Engine | Raw Count | Dedup Count (FINAL) | After OPTIMIZE | Insert Time | 평가 |
|--------|-----------|---------------------|----------------|-------------|------|
| **MergeTree** | 13,000 | 10,000 | **13,000** | 0.18s | ❌ 중복 유지 (예상된 동작) |
| **ReplacingMT** | 10,000 | 10,000 | **10,000** | 0.16s | ✅ Dedup 성공 |
| **CollapsingMT** | 10,000 | 10,000 | **10,000** | 0.18s | ✅ Dedup 성공 |
| **AggregatingMT** | 10,000 | 10,000 | **10,000** | 0.24s | ✅ Dedup 성공 |

### 핵심 발견사항

1. **ReplacingMergeTree**
   - ✅ 가장 단순하고 효과적
   - OPTIMIZE 후 중복이 완전히 제거됨
   - INSERT 성능도 우수 (82,112 rows/sec)

2. **CollapsingMergeTree**
   - ✅ Dedup 성공 (이 테스트에서는)
   - 하지만 실제로는 Sign 관리가 필요
   - Update/Delete 시나리오에 더 적합

3. **AggregatingMergeTree**
   - ✅ Dedup 성공
   - SimpleAggregateFunction 사용 필요
   - 집계 시나리오에 적합

### 권장사항
**ReplacingMergeTree 사용 권장**
- 구현이 가장 간단
- 중복 제거 효과 확실
- 쿼리 시 FINAL 키워드 필수

---

## ⚡ Phase 2: Insert 패턴별 성능 테스트 결과

### 목적
Row-by-row vs Batch insert의 성능 차이 측정

### 실행 결과

| Method | Records | Time (s) | Rate (rows/s) | Baseline 대비 |
|--------|---------|----------|---------------|--------------|
| **row_by_row** | 1,000 | 61.31 | **16** | 100% (기준) |
| **micro_batch** (100) | 10,000 | 8.31 | **1,203** | **+7,275%** |
| **batch** (10,000) | 10,000 | 0.27 | **36,743** | **+225,166%** |
| **async_insert** | 1,000 | 10.23 | **98** | **+499%** |

### 핵심 발견사항

1. **Row-by-row Insert의 문제점**
   - 매우 느림: 16 rows/sec
   - 네트워크 오버헤드가 심각
   - 프로덕션 환경에서 사용 불가

2. **Batch Insert의 효과**
   - **2,251배 빠름!** (36,743 rows/sec)
   - 10,000개를 단 0.27초에 처리
   - 네트워크 오버헤드 최소화

3. **Micro-batch의 절충안**
   - 70배 이상 성능 개선
   - 메모리 사용량 제어 가능
   - 실시간성과 성능의 균형

4. **Async Insert**
   - Row-by-row보다 5배 빠름
   - 하지만 Batch에는 크게 못 미침
   - 코드 수정 최소화 옵션

### 권장사항
**Batch Insert 강력 권장**
- Application Layer에서 배칭 구현
- 최소 100-1,000 rows 단위로 insert
- 또는 Async Insert 활성화

---

## 🏗️ Phase 3: 권장 아키텍처 검증 결과

### 아키텍처
```
[App] → [Landing Table] → [Main Table] → [Refreshable MV]
        (MergeTree+TTL)    (ReplacingMT)    (Aggregation)
```

### 실행 결과

| 항목 | 레코드 수 | 설명 |
|------|-----------|------|
| **Landing** | 13,000 | 원본 데이터 (중복 포함) |
| **Main (Raw)** | 10,810 | MV로 전달된 데이터 |
| **Main (FINAL)** | **10,000** | ✅ Dedup 완료 |
| **Hourly Agg** | 6,088 | Refreshable MV (집계됨) |
| **Expected** | 10,000 | 목표값 |

### 검증 결과
- ✅ Main FINAL = Expected Unique (정확히 일치!)
- ✅ Main에서 Dedup 동작 확인 (Raw > FINAL)
- ✅ Materialized View 체인 정상 동작
- ✅ Refreshable MV로 정확한 집계 (FINAL 사용)

### 핵심 발견사항

1. **Landing Table의 역할**
   - 빠른 insert 처리
   - TTL로 자동 정리 (1시간 후)
   - 버퍼 역할

2. **Main Table (ReplacingMergeTree)**
   - MV를 통해 자동으로 데이터 전달
   - 자동으로 중복 제거
   - FINAL 쿼리로 정확한 데이터 조회

3. **Refreshable MV**
   - FINAL을 사용하여 정확한 집계
   - 주기적으로 자동 갱신
   - 일반 MV의 중복 전파 문제 해결

### 권장사항
이 아키텍처를 프로덕션 환경에 적용:
```sql
-- 1. Landing Table (빠른 insert)
CREATE TABLE landing (...)
ENGINE = MergeTree()
TTL _insert_time + INTERVAL 1 HOUR;

-- 2. Main Table (자동 dedup)
CREATE TABLE main (...)
ENGINE = ReplacingMergeTree(_version);

-- 3. MV (자동 전달)
CREATE MATERIALIZED VIEW landing_to_main_mv TO main AS
SELECT *, toUInt64(now64(3)) as _version FROM landing;

-- 4. Refreshable MV (정확한 집계)
CREATE MATERIALIZED VIEW hourly_agg
REFRESH EVERY 1 MINUTE
AS SELECT ... FROM main FINAL GROUP BY ...;
```

---

## 🎯 종합 결론

### 1. Engine 선택

| 요구사항 | 권장 Engine | 이유 |
|----------|-------------|------|
| 일반적인 Dedup | **ReplacingMergeTree** | 구현 간단, 효과 확실 |
| Update/Delete 처리 | CollapsingMergeTree | Sign 관리 필요 |
| 집계만 필요 | AggregatingMergeTree | 집계 함수 사용 |

### 2. Insert 패턴

| 시나리오 | 권장 방법 | 예상 성능 |
|----------|-----------|-----------|
| 신규 구현 | **Batch Insert** | 36,000+ rows/sec |
| 레거시 코드 | **Async Insert** | 100+ rows/sec |
| 실시간 + 성능 | **Micro-batch** | 1,000+ rows/sec |

### 3. 아키텍처 패턴

```
[Application]
    ↓ (Batch Insert, 1000+ rows)
[Landing Table: MergeTree + TTL]
    ↓ (Materialized View)
[Main Table: ReplacingMergeTree]
    ↓ (Refreshable MV with FINAL)
[Aggregation Tables]
```

### 4. 운영 체크리스트

- ✅ ReplacingMergeTree 사용
- ✅ Batch Insert 구현 (최소 100 rows)
- ✅ Landing → Main 아키텍처 적용
- ✅ Refreshable MV로 집계 (FINAL 사용)
- ✅ TTL로 Landing 자동 정리
- ✅ 쿼리에 FINAL 적용 확인

---

## 📈 성능 요약

### Insert 성능
- Row-by-row: **16 rows/sec** ❌
- Micro-batch: **1,203 rows/sec** ⚠️
- Batch: **36,743 rows/sec** ✅
- **개선율: 2,251배**

### Dedup 효과
- MergeTree: 중복 유지 (13,000 → 13,000)
- ReplacingMT: **완전 제거 (13,000 → 10,000)** ✅
- **제거율: 100%**

### 아키텍처 정확도
- Expected: 10,000
- Main FINAL: 10,000
- **정확도: 100%** ✅

---

## 🚀 다음 단계

### 프로덕션 적용 로드맵

1. **Phase 1: Batch Insert 구현** (1-2일)
   - Application Layer에서 배칭 로직 구현
   - 1000 rows 단위로 insert
   - 성능 모니터링

2. **Phase 2: Landing → Main 구조** (2-3일)
   - Landing Table 생성 (TTL 1시간)
   - Main Table 생성 (ReplacingMergeTree)
   - Materialized View 연결

3. **Phase 3: Refreshable MV 전환** (3-5일)
   - 기존 일반 MV를 Refreshable MV로 전환
   - FINAL 쿼리 적용
   - Refresh 주기 최적화

4. **Phase 4: 모니터링 및 최적화** (지속)
   - Part 개수 모니터링
   - OPTIMIZE 스케줄링
   - 성능 튜닝

---

## 📚 참고 자료

- [ReplacingMergeTree 공식 문서](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replacingmergetree)
- [Refreshable Materialized Views](https://clickhouse.com/docs/en/materialized-view/refreshable-materialized-view)
- [Async Insert Best Practices](https://clickhouse.com/docs/en/cloud/bestpractices/asynchronous-inserts)
- [TTL 설정 가이드](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree#table_engine-mergetree-ttl)

---

**테스트 완료 일시**: 2024-12-16 21:45 KST
**테스트 실행자**: ClickHouse Solutions Team
