# Device360 PoC 사용 가이드

## 개요

이 자동화 프레임워크는 Device360 분석 패턴에서 ClickHouse의 성능을 테스트하기 위해 만들어졌습니다. BigQuery에서 어려움을 겪는 고카디널리티 device ID 기반의 point lookup과 journey 분석을 검증합니다.

## 빠른 시작 (Quick Start)

### 1단계: 환경 설정

```bash
cd workshop/device-360

# 환경 변수 템플릿 복사
cp .env.template .env

# .env 파일 편집 (필수 설정값 입력)
vim .env
```

**필수 설정값:**
```bash
# AWS 자격증명
AWS_ACCESS_KEY_ID=your_key_here
AWS_SECRET_ACCESS_KEY=your_secret_here
AWS_REGION=us-east-1
S3_BUCKET_NAME=device360-test-data

# ClickHouse Cloud 자격증명
CLICKHOUSE_HOST=your-instance.clickhouse.cloud
CLICKHOUSE_PASSWORD=your_password
CLICKHOUSE_DATABASE=device360

# 데이터 생성 파라미터
TARGET_SIZE_GB=300
NUM_RECORDS=500000000
NUM_DEVICES=100000000
```

### 2단계: Python 의존성 설치

```bash
pip3 install -r requirements.txt
```

설치되는 패키지:
- `boto3`: AWS S3 연동
- `clickhouse-connect`: ClickHouse 클라이언트

### 3단계: 실행 방법 선택

#### 옵션 A: 빠른 테스트 (추천, 처음 실행 시)

1GB 데이터로 전체 워크플로우 테스트 (10-15분 소요):

```bash
chmod +x quick-test.sh
./quick-test.sh
```

#### 옵션 B: 전체 워크플로우 (300GB)

```bash
chmod +x setup.sh
./setup.sh
```

메뉴에서 `6` 선택 (Complete workflow)

#### 옵션 C: 단계별 실행

```bash
./setup.sh
```

메뉴 선택:
- `1`: 데이터 생성만
- `2`: S3 업로드만
- `3`: S3 통합 설정
- `4`: ClickHouse 수집
- `5`: 벤치마크 쿼리 실행

## 상세 실행 가이드

### Phase 1: 합성 데이터 생성

**목적:** Device360 분석에 적합한 현실적인 광고 요청 데이터 생성

```bash
export DATA_OUTPUT_DIR=./data
export TARGET_SIZE_GB=30  # 테스트용으로 작게 시작
export NUM_DEVICES=1000000
export NUM_RECORDS=5000000

python3 scripts/generate_data.py
```

**생성되는 데이터:**
- JSON 형식, gzip 압축
- Power-law 분포:
  - 1% 디바이스 → 50% 트래픽 (봇 및 헤비 유저)
  - 10% 디바이스 → 30% 트래픽 (일반 유저)
  - 89% 디바이스 → 20% 트래픽 (라이트 유저)
- 30일간의 시계열 데이터
- 봇 탐지 시그널 포함 (fraud scores, IP patterns 등)

**출력:**
```
data/
├── device360_heavy_0001.json.gz
├── device360_heavy_0002.json.gz
├── device360_medium_0001.json.gz
├── device360_medium_0002.json.gz
├── device360_light_0001.json.gz
└── device360_light_0002.json.gz
```

**예상 시간:**
- 1GB: ~2분
- 10GB: ~10분
- 50GB: ~30분
- 300GB: ~2-3시간

### Phase 2: S3 업로드

**목적:** 생성된 데이터를 S3에 업로드하여 ClickHouse에서 접근 가능하게 함

```bash
python3 scripts/upload_to_s3.py
```

**특징:**
- 병렬 업로드 (기본 4 workers)
- 진행상황 추적
- 업로드 속도 모니터링
- 자동 bucket 생성 (존재하지 않을 경우)

**출력 예시:**
```
Uploading device360_heavy_0001.json.gz (612.45 MB)...
✓ Uploaded device360_heavy_0001.json.gz
...
Total size: 10.23 GB
Duration: 45.3 seconds
Average speed: 231.5 MB/s
S3 Location: s3://device360-test-data/device360/
```

**병렬도 조정:**
```bash
export S3_UPLOAD_WORKERS=8  # 더 빠른 업로드
python3 scripts/upload_to_s3.py
```

### Phase 3: S3 통합 설정

**목적:** ClickHouse Cloud가 S3 버킷에 접근할 수 있도록 IAM 역할 생성

```bash
python3 scripts/setup_s3_integration.py
```

**수행 작업:**
1. IAM 역할 생성 (`ClickHouseS3AccessRole`)
2. S3 읽기 권한 정책 연결
3. Trust policy 설정
4. Role ARN 출력

**필요한 입력:**
- ClickHouse Role ID (ClickHouse Cloud 콘솔에서 확인)
  - 콘솔 경로: Settings → S3 Integration → Role ID

**출력:**
```
Role ARN: arn:aws:iam::123456789012:role/ClickHouseS3AccessRole

Add this to your .env file:
S3_ROLE_ARN=arn:aws:iam::123456789012:role/ClickHouseS3AccessRole
```

**수동 설정 (대안):**
ClickHouse Cloud 콘솔에서 직접 S3 integration 설정 가능

### Phase 4: ClickHouse 데이터 수집

**목적:** S3의 데이터를 ClickHouse에 로드하고 스키마 생성

```bash
python3 scripts/ingest_from_s3.py
```

**수행 작업:**
1. `device360` 데이터베이스 생성
2. `ad_requests` 메인 테이블 생성
   ```sql
   ORDER BY (device_id, event_date, event_ts)
   ```
   → device_id가 첫 번째 키 (밀리초 단위 point lookup 가능)

3. Materialized Views 생성:
   - `device_profiles`: 디바이스별 프로파일
   - `device_daily_stats`: 일별 통계
   - `bot_candidates`: 봇 후보
   - `hourly_app_stats`: 앱 시간별 통계
   - `geo_stats`: 지리적 분포

4. S3에서 데이터 로드 (s3() 테이블 함수 사용)

**수집 성능 모니터링:**
```
[1/50] Ingesting device360_heavy_0001.json.gz...
  ✓ Ingested 1,000,000 rows in 2.3s (434,782 rows/s)
...
Total rows ingested: 50,000,000
Total time: 115.3 seconds
Average rate: 433,651 rows/s
```

**예상 수집 속도:**
- Small instance: 100K-500K rows/s
- Medium instance: 500K-2M rows/s
- Large instance: 2M-5M rows/s

**병렬도 증가 방법:**
ClickHouse Cloud에서 스케일업 또는 여러 인스턴스 사용

### Phase 5: 벤치마크 쿼리 실행

**목적:** 다양한 Device360 쿼리 패턴의 성능 측정

```bash
python3 scripts/run_benchmarks.py
```

**테스트 카테고리:**

#### 1. Device Journey 분석 (01_device_journey_queries.sql)
```
[1/10] Test 1.1 - Single Device Point Lookup
  ✓ Duration: 45.2ms
  ✓ Rows: 1,234

[2/10] Test 1.2 - Device Journey Timeline
  ✓ Duration: 156.7ms
  ✓ Rows: 1,234
...
```

**주요 쿼리:**
- 단일 디바이스 point lookup (목표: <100ms)
- Journey timeline with time gaps
- Session detection (30분 비활성 기준)
- Cross-app funnel 분석
- Location journey 및 impossible travel 탐지

#### 2. Aggregation 쿼리 (02_aggregation_queries.sql)

**주요 쿼리:**
- 일별 디바이스 요청 수 (고객 핵심 use case)
- Frequency distribution
- High-cardinality GROUP BY
- Approximate vs Exact cardinality

#### 3. Bot Detection 쿼리 (03_bot_detection_queries.sql)

**주요 쿼리:**
- Multi-signal bot scoring
- IP anomaly detection
- Temporal pattern analysis
- 24/7 activity pattern
- Composite bot score 계산

#### 4. Materialized View 성능 비교 (04_materialized_view_queries.sql)

Pre-aggregated view vs 실시간 쿼리 성능 비교

**결과 출력:**
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

Slowest Queries:
  1. Test 4.4 - Impossible Travel Detection: 2,341.2ms
  2. Test 3.3 - High-Frequency Device Detection: 1,567.3ms
  ...
====================================================================
```

**결과 저장:**
```
results/benchmark_results_20250611_143022.json
```

## 성능 목표

테스트 플랜 기준:

| 쿼리 패턴 | 목표 시간 | BigQuery 기준 | 기대 개선율 |
|----------|---------|-------------|-----------|
| Single device lookup | < 100ms | 10-30초 | 100-300배 |
| Device journey timeline | < 500ms | 30-60초 | 60-120배 |
| Session detection | < 1초 | 1-2분 | 60-120배 |
| Daily device GROUP BY | < 1초 | 30-60초 | 30-60배 |
| Bot detection | < 3초 | 1-3분 | 20-60배 |

## 스케일 테스트 시나리오

### 테스트 1: Small Scale (1GB)
```bash
export TARGET_SIZE_GB=1
export NUM_DEVICES=100000
export NUM_RECORDS=1700000
./quick-test.sh
```

**목적:** 전체 워크플로우 검증, 빠른 테스트

### 테스트 2: Medium Scale (50GB)
```bash
export TARGET_SIZE_GB=50
export NUM_DEVICES=10000000
export NUM_RECORDS=85000000
./setup.sh
```

**목적:** 실제 운영 환경 시뮬레이션

### 테스트 3: Full Scale (300GB)
```bash
export TARGET_SIZE_GB=300
export NUM_DEVICES=100000000
export NUM_RECORDS=500000000
./setup.sh
```

**목적:** 최대 부하 테스트, 병렬 처리 성능 확인

## 결과 분석

### 1. 로그 확인

```bash
ls -lh logs/
tail -f logs/04_ingest_20250611_143022.log
```

### 2. 벤치마크 결과 분석

```bash
cat results/benchmark_results_20250611_143022.json | jq '.results[] | select(.success == true) | {name: .query_name, duration_ms: .duration_ms}'
```

### 3. ClickHouse 시스템 테이블 확인

```sql
-- 쿼리 로그
SELECT
    query,
    query_duration_ms,
    read_rows,
    result_rows
FROM system.query_log
WHERE query LIKE '%device360%'
  AND type = 'QueryFinish'
ORDER BY query_start_time DESC
LIMIT 10;

-- 테이블 통계
SELECT
    database,
    table,
    sum(rows) as total_rows,
    formatReadableSize(sum(bytes)) as size
FROM system.parts
WHERE database = 'device360'
GROUP BY database, table;

-- Materialized View 상태
SELECT
    database,
    view,
    total_rows,
    last_refresh_time
FROM system.materialized_views
WHERE database = 'device360';
```

## 문제 해결 (Troubleshooting)

### 데이터 생성이 느린 경우

더 작은 데이터셋으로 시작:
```bash
export TARGET_SIZE_GB=5
export NUM_RECORDS=8500000
```

### S3 업로드 실패

AWS 자격증명 확인:
```bash
aws s3 ls s3://$S3_BUCKET_NAME/
```

병렬도 감소:
```bash
export S3_UPLOAD_WORKERS=2
```

### ClickHouse 연결 오류

연결 테스트:
```bash
clickhouse-client --host $CLICKHOUSE_HOST \
  --user $CLICKHOUSE_USER \
  --password $CLICKHOUSE_PASSWORD \
  --secure \
  --query "SELECT version()"
```

### 쿼리 성능이 느린 경우

1. **데이터 분포 확인:**
```sql
SELECT count(), uniq(device_id)
FROM device360.ad_requests;
```

2. **ORDER BY 키 확인:**
```sql
SELECT partition, name, rows
FROM system.parts
WHERE database = 'device360' AND table = 'ad_requests'
ORDER BY partition, name;
```

3. **첫 실행은 캐시 때문에 느릴 수 있음** - 두 번째 실행으로 재확인

4. **ClickHouse 인스턴스 스케일업 고려**

## 비용 추정

### AWS S3 (us-east-1 기준)

- 스토리지: 300GB × $0.023/GB/월 = $6.90/월
- PUT 요청: ~500 파일 × $0.005/1000 = $0.003
- GET 요청: ~500 파일 × $0.0004/1000 = $0.0002

**총계:** ~$7/월

### ClickHouse Cloud

인스턴스 크기에 따라:
- Development: $0.15-0.30/시간
- Production: $0.60-2.00/시간

300GB 데이터 추천 스펙:
- 최소 16GB RAM
- 100GB 디스크
- Vertical autoscaling 활성화

**테스트 기간:** 8시간 × $0.30 = $2.40

## 고급 사용법

### 커스텀 쿼리 추가

`queries/` 디렉토리에 SQL 파일 추가:

```sql
-- queries/05_custom_analysis.sql

-- Test 5.1: My Custom Query
SELECT ...
FROM device360.ad_requests
WHERE ...;
```

벤치마크 실행:
```bash
python3 scripts/run_benchmarks.py
```

### 데이터 볼륨 조정

더 세밀한 제어:
```python
# scripts/generate_data.py 수정
# Line 23-28:
self.heavy_devices = int(num_devices * 0.02)   # 1% → 2%로 증가
self.heavy_records = int(num_records * 0.60)   # 50% → 60%로 증가
```

### 병렬 수집 성능 테스트

여러 파일을 동시에 수집:

```bash
# Terminal 1
python3 scripts/ingest_from_s3.py --file-pattern "heavy_*"

# Terminal 2
python3 scripts/ingest_from_s3.py --file-pattern "medium_*"

# Terminal 3
python3 scripts/ingest_from_s3.py --file-pattern "light_*"
```

## 참고 자료

- [상세 테스트 플랜](./device360-test-plan.md)
- [README](./README.md)
- [ClickHouse MergeTree 문서](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree)
- [ClickHouse S3 통합 가이드](https://clickhouse.com/docs/en/integrations/s3)

## 다음 단계

1. **빠른 테스트 실행** (1GB)
   ```bash
   ./quick-test.sh
   ```

2. **결과 확인**
   ```bash
   cat results/benchmark_results_*.json | jq
   ```

3. **성능 목표 달성 확인**
   - < 100ms: Point lookups
   - < 500ms: Journey timelines
   - < 1s: Session detection
   - < 3s: Bot detection

4. **스케일 업 테스트** (50GB → 300GB)

5. **프로덕션 배포 계획**
