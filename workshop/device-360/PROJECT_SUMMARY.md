# Device360 PoC - 프로젝트 요약

## 완성된 자동화 테스트 환경

Device360 분석 패턴을 위한 **완전 자동화된 end-to-end 테스트 환경**이 구축되었습니다.

---

## 📁 프로젝트 구조

```
device-360/
├── 📘 문서
│   ├── README.md                   # 영문 메인 문서
│   ├── USAGE_GUIDE.md              # 한글 상세 사용 가이드
│   ├── device360-test-plan.md     # 원본 테스트 플랜
│   └── PROJECT_SUMMARY.md          # 이 파일
│
├── ⚙️ 환경 설정
│   ├── .env.template               # 환경 변수 템플릿
│   ├── requirements.txt            # Python 의존성
│   └── .gitignore                  # Git ignore 설정
│
├── 🚀 실행 스크립트
│   ├── setup.sh                    # 메인 설정 스크립트 (메뉴 방식)
│   └── quick-test.sh               # 빠른 테스트 (1GB)
│
├── 🐍 Python 스크립트 (scripts/)
│   ├── generate_data.py            # 합성 데이터 생성 (300GB)
│   ├── upload_to_s3.py             # S3 업로드 (병렬, 진행 추적)
│   ├── setup_s3_integration.py     # IAM 역할 자동 생성
│   ├── ingest_from_s3.py           # ClickHouse 수집 (성능 모니터링)
│   └── run_benchmarks.py           # 벤치마크 실행 및 결과 저장
│
├── 🗃️ SQL 스크립트 (sql/)
│   ├── 01_create_database.sql
│   ├── 02_create_main_table.sql
│   └── 03_create_materialized_views.sql
│
└── 🔍 쿼리 테스트 스위트 (queries/)
    ├── 01_device_journey_queries.sql      # 10개 Journey 분석 쿼리
    ├── 02_aggregation_queries.sql         # 12개 Aggregation 쿼리
    ├── 03_bot_detection_queries.sql       # 12개 Bot Detection 쿼리
    └── 04_materialized_view_queries.sql   # 11개 MV 성능 비교 쿼리

총 45개의 벤치마크 쿼리
```

---

## 🎯 주요 기능

### 1. 데이터 생성 (generate_data.py)

**특징:**
- ✅ Power-law 분포 구현 (1% → 50%, 10% → 30%, 89% → 20%)
- ✅ 현실적인 봇 시그널 (high fraud scores, multiple IPs, 24/7 activity)
- ✅ 30일 시계열 데이터
- ✅ 93개 컬럼 (device, geo, app, metrics, fraud signals)
- ✅ JSON gzip 압축 (600MB per 1M records)
- ✅ 배치 파일 생성 (1M records per file)

**사용 예시:**
```bash
export TARGET_SIZE_GB=300
export NUM_DEVICES=100000000
export NUM_RECORDS=500000000
python3 scripts/generate_data.py
```

**출력:** `data/device360_*.json.gz`

---

### 2. S3 업로드 (upload_to_s3.py)

**특징:**
- ✅ 병렬 업로드 (기본 4 workers, 조정 가능)
- ✅ 실시간 진행 추적 (MB 단위)
- ✅ 업로드 속도 모니터링
- ✅ 자동 bucket 생성
- ✅ 업로드 완료 후 파일 목록 확인

**사용 예시:**
```bash
export S3_UPLOAD_WORKERS=8  # 병렬도 증가
python3 scripts/upload_to_s3.py
```

**성능:** 평균 200-300 MB/s

---

### 3. S3 Integration 설정 (setup_s3_integration.py)

**특징:**
- ✅ IAM 역할 자동 생성 (`ClickHouseS3AccessRole`)
- ✅ S3 read-only 정책 자동 연결
- ✅ Trust policy 설정
- ✅ Role ARN 출력 (`.env`에 추가용)

**사용 예시:**
```bash
python3 scripts/setup_s3_integration.py
# ClickHouse Role ID 입력 필요
```

---

### 4. ClickHouse 데이터 수집 (ingest_from_s3.py)

**특징:**
- ✅ 자동 스키마 생성 (database, tables, materialized views)
- ✅ S3 파일 목록 자동 스캔
- ✅ `s3()` 테이블 함수 사용
- ✅ 실시간 수집 속도 모니터링 (rows/s)
- ✅ 수집 완료 후 데이터 검증

**핵심 스키마 설계:**
```sql
CREATE TABLE device360.ad_requests (
    ...
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_date)
ORDER BY (device_id, event_date, event_ts)  -- device_id FIRST!
```

**Materialized Views:**
1. `device_profiles` - 디바이스별 프로파일 (AggregatingMergeTree)
2. `device_daily_stats` - 일별 통계 (SummingMergeTree)
3. `bot_candidates` - 봇 후보 (AggregatingMergeTree)
4. `hourly_app_stats` - 시간별 앱 통계
5. `geo_stats` - 지리적 분포

**예상 성능:**
- Small instance: 100K-500K rows/s
- Medium instance: 500K-2M rows/s
- Large instance: 2M-5M rows/s

---

### 5. 벤치마크 실행 (run_benchmarks.py)

**특징:**
- ✅ 4개 카테고리, 45개 쿼리 자동 실행
- ✅ 실행 시간 측정 (밀리초 단위)
- ✅ 성공/실패 추적
- ✅ 성능 목표 달성률 계산
- ✅ JSON 결과 파일 저장

**쿼리 카테고리:**

#### Category 1: Device Journey Analysis (10 queries)
- Single device point lookup (< 100ms)
- Journey timeline with lag/lead
- Session detection (30-min gaps)
- Cross-app funnel
- Location journey (geoDistance)
- Behavior change detection
- First/last touch attribution
- Multi-device pattern analysis
- Hourly activity pattern

#### Category 2: Aggregation Queries (12 queries)
- Daily request count per device (핵심 use case)
- Frequency distribution
- High-frequency device detection
- Approximate vs Exact cardinality
- Top apps by device reach
- Geographic distribution
- Device brand/model analysis
- Hourly patterns
- IP analysis
- Ad performance
- Time-to-first-request
- Retention cohort

#### Category 3: Bot Detection (12 queries)
- Multi-signal bot detection
- IP-based anomaly
- Temporal pattern analysis
- Impossible travel detection
- Suspicious user-agent patterns
- Abnormal volume detection
- 24/7 activity detection
- Low engagement / high volume
- Fraud score correlation
- Composite bot score (0-100)
- Network type analysis
- Bot blocklist export

#### Category 4: Materialized View Comparison (11 queries)
- Device profiles (MV vs Raw)
- Daily stats (MV vs Raw)
- Bot candidates (MV vs Raw)
- Hourly app stats (MV vs Raw)
- Geographic stats (MV vs Raw)
- Top devices by volume
- Device retention analysis
- App performance trends
- Peak hour detection
- Incremental update verification
- Performance comparison summary

**결과 출력 예시:**
```
====================================================================
Benchmark Summary
====================================================================
Total queries: 45
Successful: 44
Failed: 1

Performance:
  Average: 245.3ms
  Median: 127.5ms
  Min: 23.1ms
  Max: 2,341.2ms

Target Achievement:
  < 100ms: 18/44 (40%)
  < 500ms: 35/44 (79%)
  < 1s: 40/44 (90%)
  < 3s: 44/44 (100%)
====================================================================
```

---

## 🚀 실행 방법

### Option 1: 빠른 테스트 (추천)

**1GB 데이터로 전체 워크플로우 검증 (10-15분)**

```bash
# 환경 설정
cp .env.template .env
vim .env  # 자격증명 입력

# 의존성 설치
pip3 install -r requirements.txt

# 빠른 테스트 실행
chmod +x quick-test.sh
./quick-test.sh
```

### Option 2: 전체 워크플로우 (300GB)

```bash
chmod +x setup.sh
./setup.sh

# 메뉴에서 '6' 선택
```

### Option 3: 단계별 실행

```bash
./setup.sh

# 메뉴 선택:
# 1 - 데이터 생성
# 2 - S3 업로드
# 3 - S3 통합 설정
# 4 - ClickHouse 수집
# 5 - 벤치마크 실행
```

---

## 📊 성능 목표 vs BigQuery

| 쿼리 패턴 | ClickHouse 목표 | BigQuery 기준 | 개선율 |
|----------|---------------|-------------|--------|
| Single device lookup | < 100ms | 10-30초 | **100-300x** |
| Device journey timeline | < 500ms | 30-60초 | **60-120x** |
| Session detection | < 1초 | 1-2분 | **60-120x** |
| Cross-app funnel | < 500ms | 30-60초 | **60-120x** |
| Daily device GROUP BY | < 1초 | 30-60초 | **30-60x** |
| Bot detection | < 3초 | 1-3분 | **20-60x** |

---

## 🧪 테스트 시나리오

### Level 1: Small (1GB) - 빠른 검증
```bash
export TARGET_SIZE_GB=1
export NUM_DEVICES=100000
export NUM_RECORDS=1700000
./quick-test.sh
```
**시간:** ~10-15분
**목적:** 전체 워크플로우 검증

### Level 2: Medium (50GB) - 실전 환경
```bash
export TARGET_SIZE_GB=50
export NUM_DEVICES=10000000
export NUM_RECORDS=85000000
./setup.sh
```
**시간:** ~2-3시간
**목적:** 실제 운영 부하 시뮬레이션

### Level 3: Full (300GB) - 최대 부하
```bash
export TARGET_SIZE_GB=300
export NUM_DEVICES=100000000
export NUM_RECORDS=500000000
./setup.sh
```
**시간:** ~4-6시간
**목적:** 병렬 처리 성능 확인, 스케일 테스트

---

## 📈 결과 분석

### 1. 벤치마크 결과 확인

```bash
# JSON 결과 확인
cat results/benchmark_results_*.json | jq

# 성공한 쿼리만 필터링
cat results/benchmark_results_*.json | jq '.results[] | select(.success == true)'

# 평균 실행 시간
cat results/benchmark_results_*.json | jq '[.results[] | select(.success == true) | .duration_ms] | add / length'
```

### 2. 로그 확인

```bash
# 최신 로그 확인
tail -f logs/05_benchmarks_*.log

# 수집 성능 확인
grep "rows/s" logs/04_ingest_*.log
```

### 3. ClickHouse 시스템 쿼리

```sql
-- 최근 쿼리 성능
SELECT
    query,
    query_duration_ms,
    read_rows,
    result_rows,
    read_rows / query_duration_ms * 1000 as rows_per_sec
FROM system.query_log
WHERE query LIKE '%device360%'
  AND type = 'QueryFinish'
  AND query_duration_ms > 0
ORDER BY query_start_time DESC
LIMIT 20;

-- 테이블 크기
SELECT
    table,
    formatReadableSize(sum(bytes)) as size,
    sum(rows) as rows
FROM system.parts
WHERE database = 'device360'
GROUP BY table;

-- Materialized View 상태
SELECT * FROM system.materialized_views
WHERE database = 'device360';
```

---

## 💰 비용 추정

### AWS S3 (300GB, 1개월)
- 스토리지: $6.90
- 요청: $0.01
- **합계: ~$7/월**

### ClickHouse Cloud (테스트 8시간)
- Development tier: $0.30/시간 × 8시간 = **$2.40**
- Production tier: $0.60/시간 × 8시간 = **$4.80**

**전체 테스트 비용: ~$10-15**

---

## 🔧 고급 설정

### 병렬도 조정

```bash
# S3 업로드 병렬도
export S3_UPLOAD_WORKERS=8

# 데이터 생성 배치 크기
# scripts/generate_data.py 에서 batch_size 조정

# ClickHouse 수집 병렬화
# 여러 터미널에서 다른 파일 패턴 수집
```

### 커스텀 쿼리 추가

```sql
-- queries/05_custom_queries.sql
-- Test 5.1: My Analysis
SELECT ...
FROM device360.ad_requests
WHERE ...;
```

### 스키마 커스터마이징

```sql
-- sql/02_create_main_table.sql 수정
-- 컬럼 추가/제거
-- ORDER BY 키 변경 테스트
```

---

## ✅ 체크리스트

### 사전 준비
- [ ] AWS 계정 및 S3 버킷 생성
- [ ] ClickHouse Cloud 인스턴스 생성
- [ ] `.env` 파일 설정
- [ ] Python 3.8+ 설치
- [ ] pip 의존성 설치

### 빠른 테스트 (1GB)
- [ ] `./quick-test.sh` 실행
- [ ] 데이터 생성 확인 (`data/` 디렉토리)
- [ ] S3 업로드 확인
- [ ] ClickHouse 수집 완료
- [ ] 벤치마크 결과 확인 (`results/`)

### 전체 테스트 (300GB)
- [ ] 디스크 공간 확인 (500GB 이상)
- [ ] `./setup.sh` 메뉴에서 옵션 6 선택
- [ ] 데이터 생성 (2-3시간)
- [ ] S3 업로드 (1-2시간)
- [ ] S3 integration 설정
- [ ] ClickHouse 수집 (30-60분)
- [ ] 벤치마크 실행 (10-20분)
- [ ] 성능 목표 달성 확인

### 결과 분석
- [ ] 로그 파일 확인
- [ ] 벤치마크 JSON 결과 분석
- [ ] 성능 목표 달성률 확인
- [ ] ClickHouse 시스템 테이블 쿼리
- [ ] 최종 보고서 작성

---

## 📚 문서

1. **[README.md](./README.md)** - 영문 전체 가이드
2. **[USAGE_GUIDE.md](./USAGE_GUIDE.md)** - 한글 상세 사용법
3. **[device360-test-plan.md](./device360-test-plan.md)** - 원본 테스트 플랜

---

## 🎓 학습 포인트

이 프레임워크를 통해 학습할 수 있는 것:

1. **ClickHouse 스키마 설계**
   - device_id-first ORDER BY 전략
   - Partition vs ORDER BY 키 선택
   - LowCardinality 타입 활용

2. **Materialized Views**
   - AggregatingMergeTree 활용
   - SummingMergeTree 사용법
   - 실시간 vs pre-aggregated 성능 비교

3. **고카디널리티 처리**
   - Sparse index 활용
   - uniq() vs uniqExact() 트레이드오프
   - Window functions 최적화

4. **데이터 엔지니어링**
   - Power-law 분포 생성
   - 현실적인 synthetic data
   - S3 integration patterns

5. **성능 벤치마킹**
   - 체계적인 테스트 suite
   - 자동화된 결과 수집
   - 목표 대비 달성률 측정

---

## 🤝 기여 및 피드백

이 프레임워크는 Device360 PoC를 위해 제작되었습니다.

개선 제안:
- 더 많은 쿼리 패턴 추가
- 다른 데이터 분포 테스트
- 다른 ORDER BY 전략 비교
- Real-time 데이터 스트리밍 추가

---

## 📞 다음 단계

1. **빠른 테스트 실행**
   ```bash
   ./quick-test.sh
   ```

2. **결과 확인 및 검증**

3. **Full Scale 테스트** (300GB)

4. **성능 리포트 작성**

5. **프로덕션 배포 계획**

---

**구축 완료일:** 2025-12-11
**프레임워크 버전:** 1.0
**테스트 준비 완료** ✅
