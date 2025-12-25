# MySQL vs ClickHouse Point Query 성능 비교 보고서

**테스트 일시**: 2025-12-25
**ClickHouse 버전**: 25.10
**MySQL 버전**: 8.0

---

## 📊 Executive Summary

게임 서버에서 플레이어 마지막 접속 정보 조회(Point Query) 성능을 MySQL과 ClickHouse MySQL Protocol을 통해 비교 테스트했습니다.

### 핵심 결과

- **MySQL이 ClickHouse보다 약 1.85배 빠른 성능**을 보였습니다
- MySQL: 평균 **4,921 QPS**, 중간값 레이턴시 **0.65ms**
- ClickHouse: 평균 **2,690 QPS**, 중간값 레이턴시 **3.95ms**
- ClickHouse는 MySQL 대비 **54-57%의 성능**을 보임

---

## 🧪 테스트 환경

### 데이터셋
- **총 레코드 수**: 2,000,000 rows
- **player_id 범위**: 1 ~ 2,000,000
- **테이블 구조**: 26개 컬럼 (게임 플레이어 정보)

### 테스트 조건
- **동시성 레벨**: 8, 16, 24, 32 concurrent connections
- **쿼리당 횟수**: 500 queries per worker
- **총 쿼리 수**:
  - Concurrency 8: 4,000 queries
  - Concurrency 16: 8,000 queries
  - Concurrency 24: 12,000 queries
  - Concurrency 32: 16,000 queries
- **쿼리 타입**: Primary Key 기반 단일 row SELECT

### MySQL 설정
- Engine: InnoDB
- Primary Key: player_id
- Buffer Pool: 1GB
- Max Connections: 500

### ClickHouse 설정
- Engine: MergeTree
- ORDER BY: player_id
- Bloom Filter Index: player_id (False Positive Rate: 0.01, Granularity: 1)
- Index Granularity: 8192

---

## 📈 성능 테스트 결과

### 1. QPS (Queries Per Second) 비교

| Concurrency | MySQL QPS | ClickHouse QPS | CH/MySQL Ratio |
|-------------|-----------|----------------|----------------|
| 8           | 4,840.76  | 2,763.43       | 0.57x          |
| 16          | 4,937.39  | 2,643.74       | 0.54x          |
| 24          | 4,940.25  | 2,677.72       | 0.54x          |
| 32          | 4,966.07  | 2,674.63       | 0.54x          |

**분석**:
- MySQL은 동시성이 증가해도 QPS가 거의 일정하게 유지됨 (4,840 → 4,966)
- ClickHouse는 동시성 8에서 가장 높은 QPS를 보이고, 이후 약간 감소함 (2,763 → 2,674)
- ClickHouse는 MySQL 대비 54-57% 수준의 처리량을 보임

### 2. 평균 레이턴시 (Average Latency) 비교

| Concurrency | MySQL Avg (ms) | ClickHouse Avg (ms) | 차이 |
|-------------|----------------|---------------------|------|
| 8           | 0.87           | 2.62                | 3.01x|
| 16          | 1.33           | 3.73                | 2.80x|
| 24          | 1.85           | 4.67                | 2.52x|
| 32          | 2.29           | 5.74                | 2.51x|

**분석**:
- MySQL의 평균 레이턴시는 매우 낮음 (0.87 ~ 2.29ms)
- ClickHouse는 MySQL 대비 2.5 ~ 3배 높은 레이턴시
- 동시성이 증가할수록 두 DB 모두 레이턴시가 증가하나, MySQL이 더 완만하게 증가

### 3. P50 레이턴시 (중간값) 비교

| Concurrency | MySQL P50 (ms) | ClickHouse P50 (ms) | 차이 |
|-------------|----------------|---------------------|------|
| 8           | 0.65           | 2.48                | 3.82x|
| 16          | 0.65           | 3.25                | 5.00x|
| 24          | 0.65           | 4.23                | 6.51x|
| 32          | 0.65           | 5.69                | 8.75x|

**분석**:
- MySQL의 P50 레이턴시는 모든 동시성 레벨에서 **0.65ms로 일정**
- ClickHouse는 동시성 증가에 따라 P50이 선형적으로 증가 (2.48ms → 5.69ms)
- 동시성 32에서는 ClickHouse가 MySQL보다 8.75배 느림

### 4. P95 레이턴시 (95th Percentile) 비교

| Concurrency | MySQL P95 (ms) | ClickHouse P95 (ms) | 차이 |
|-------------|----------------|---------------------|------|
| 8           | 1.75           | 3.85                | 2.20x|
| 16          | 3.41           | 6.69                | 1.96x|
| 24          | 5.14           | 9.35                | 1.82x|
| 32          | 6.74           | 12.15               | 1.80x|

**분석**:
- MySQL P95는 1.75ms ~ 6.74ms 범위
- ClickHouse P95는 3.85ms ~ 12.15ms 범위
- 고동시성 환경에서도 ClickHouse의 P95 레이턴시는 MySQL 대비 약 1.8배 수준

### 5. P99 레이턴시 (99th Percentile) 비교

| Concurrency | MySQL P99 (ms) | ClickHouse P99 (ms) | 차이 |
|-------------|----------------|---------------------|------|
| 8           | 2.53           | 4.61                | 1.82x|
| 16          | 5.78           | 9.21                | 1.59x|
| 24          | 8.82           | 12.91               | 1.46x|
| 32          | 11.62          | 17.05               | 1.47x|

**분석**:
- P99 레이턴시에서는 두 DB의 차이가 가장 적음
- MySQL P99: 2.53ms ~ 11.62ms
- ClickHouse P99: 4.61ms ~ 17.05ms
- 동시성 32에서 ClickHouse P99는 17.05ms로 여전히 20ms 이내

---

## 🔍 상세 분석

### 1. MySQL의 강점

#### A. 일관된 낮은 레이턴시
- P50 레이턴시가 모든 동시성에서 0.65ms로 일정
- Primary Key 기반 조회에 최적화된 B-Tree 인덱스
- InnoDB의 효율적인 버퍼 풀 관리

#### B. 안정적인 스케일링
- 동시성 8 → 32로 4배 증가 시:
  - QPS: 4,840 → 4,966 (2.6% 증가)
  - P50: 0.65ms → 0.65ms (변화 없음)
  - P99: 2.53ms → 11.62ms (4.6배 증가)

#### C. Point Query에 특화된 설계
- OLTP 워크로드에 최적화
- Row 단위 빠른 접근
- 효율적인 락 관리

### 2. ClickHouse의 특징

#### A. 동시성 증가에 따른 성능 저하
- Concurrency 8: 2,763 QPS (가장 높음)
- Concurrency 16-32: 약 2,644-2,678 QPS (4.3% 감소)
- P50 레이턴시가 동시성에 따라 선형 증가

#### B. Bloom Filter Index의 한계
- Bloom Filter는 False Positive를 줄이지만 완벽하지 않음
- Granule 단위 스킵으로 인한 오버헤드
- Point Query에는 B-Tree만큼 효율적이지 않음

#### C. MySQL Protocol 오버헤드
- ClickHouse Native Protocol이 아닌 MySQL Protocol 사용
- Protocol 변환 오버헤드
- Connection pool reset_session 미지원

#### D. 컬럼 스토어의 특성
- 단일 row 조회 시 모든 컬럼 파일에 접근 필요
- OLAP 워크로드에 최적화되어 있어 OLTP 스타일 쿼리에는 불리

### 3. 레이턴시 분포 패턴

#### MySQL 레이턴시 분포
```
동시성 32 기준:
- P50: 0.65ms
- P95: 6.74ms (P50의 10.4배)
- P99: 11.62ms (P50의 17.9배)
```
→ 대부분의 쿼리는 1ms 이내, 일부 쿼리만 느려짐

#### ClickHouse 레이턴시 분포
```
동시성 32 기준:
- P50: 5.69ms
- P95: 12.15ms (P50의 2.1배)
- P99: 17.05ms (P50의 3.0배)
```
→ 레이턴시가 더 균일하게 분포

---

## 🎯 결론 및 권장사항

### 결론

1. **Point Query 성능**: MySQL이 ClickHouse보다 **약 1.85배 우수**
2. **레이턴시 안정성**: MySQL이 훨씬 더 안정적이고 예측 가능
3. **동시성 처리**: MySQL이 고동시성 환경에서 더 나은 성능
4. **ClickHouse의 약점**: OLTP 스타일 Point Query는 ClickHouse의 설계 목적과 맞지 않음

### 권장사항

#### MySQL을 사용해야 하는 경우
✅ 실시간 플레이어 정보 조회 (게임 서버)
✅ 낮은 레이턴시가 중요한 OLTP 워크로드
✅ Primary Key 기반 단일 row 조회가 주요 패턴
✅ 높은 동시성 지원 필요

#### ClickHouse를 사용해야 하는 경우
✅ 대량 데이터 분석 (통계, 리포트)
✅ 시계열 데이터 집계
✅ 대규모 배치 쿼리
✅ OLAP 워크로드

#### 하이브리드 아키텍처 제안

**실시간 조회**: MySQL 사용
- player_last_login 테이블 (Hot Data)
- Point Query 최적화
- 낮은 레이턴시 보장

**분석 및 통계**: ClickHouse 사용
- MySQL에서 ClickHouse로 주기적 복제
- 집계 쿼리, 리포트 생성
- 대량 데이터 분석

---

## 📝 테스트 제한사항

1. **네트워크 오버헤드 없음**: 모든 테스트는 localhost에서 수행
2. **단일 노드**: 클러스터 환경 미테스트
3. **캐시 효과**: 200만 rows는 메모리에 캐싱 가능
4. **쿼리 패턴**: 단일 타입의 SELECT 쿼리만 테스트
5. **MySQL Protocol**: ClickHouse Native Protocol 미사용

---

## 🔬 추가 테스트 고려사항

1. **대용량 데이터셋**: 1억 rows 이상 테스트
2. **복잡한 쿼리**: JOIN, 집계 쿼리 비교
3. **Write 성능**: INSERT/UPDATE 성능 비교
4. **네트워크 환경**: 원격 서버 테스트
5. **클러스터**: 분산 환경에서의 성능
6. **Native Protocol**: ClickHouse Native Protocol vs MySQL Protocol

---

## 📚 참고 정보

### ClickHouse 최적화 시도

본 테스트에서 ClickHouse는 다음 최적화를 적용했습니다:

1. **PRIMARY KEY (ORDER BY player_id)**
   - player_id 기반 정렬 및 인덱싱
   - Sparse Index로 빠른 범위 탐색

2. **Bloom Filter Index**
   ```sql
   INDEX idx_player_id_bloom player_id
   TYPE bloom_filter(0.01)
   GRANULARITY 1
   ```
   - False Positive Rate: 1%
   - Granularity: 1 (각 granule마다 별도 필터)

3. **Index Granularity: 8192**
   - 200만 rows → 약 244 granules
   - Granule당 약 8,192 rows

이러한 최적화에도 불구하고, Point Query 성능은 MySQL에 미치지 못했습니다.

### 성능 차이의 근본 원인

1. **스토리지 구조**:
   - MySQL InnoDB: Row-oriented (단일 row 접근에 최적화)
   - ClickHouse: Column-oriented (대량 컬럼 스캔에 최적화)

2. **인덱스 구조**:
   - MySQL: B-Tree (O(log n) 정확한 탐색)
   - ClickHouse: Sparse Index + Bloom Filter (Granule 단위 스킵)

3. **설계 철학**:
   - MySQL: OLTP (낮은 레이턴시, 고동시성)
   - ClickHouse: OLAP (대량 처리, 집계 최적화)

---

**보고서 작성**: Claude Code
**테스트 수행일**: 2025-12-25
**문의**: 추가 테스트나 분석이 필요한 경우 문의 주세요.
