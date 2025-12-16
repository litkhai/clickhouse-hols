# MV vs RMV 리소스 효율성 비교 테스트 - 상세 실행 계획
# Detailed Test Plan: MV vs RMV Resource Efficiency Comparison

---

## 📋 테스트 개요 / Test Overview

### 목적 / Objective
실시간 Materialized View (MV)와 배치 방식 Refreshable Materialized View (RMV)의 리소스 효율성을 정량적으로 비교 분석

Quantitatively compare and analyze the resource efficiency between real-time Materialized Views (MV) and batch-style Refreshable Materialized Views (RMV)

### 테스트 환경 / Test Environment
- **Platform**: ClickHouse Cloud
- **Test Duration**: 30분 / 30 minutes
- **Data Volume**: ~1,800,000 rows (1,000 rows/sec)
- **Comparison Method**: 동일 소스 테이블에서 MV와 RMV 동시 실행 / Concurrent execution of MV and RMV from the same source table

---

## 🎯 테스트 가설 / Test Hypothesis

### 가설 / Hypothesis
**RMV (5분 주기 배치 처리)가 MV (실시간 처리)보다 리소스 효율성이 높을 것이다.**

**RMV (5-minute batch processing) will demonstrate higher resource efficiency than MV (real-time processing).**

### 이론적 근거 / Theoretical Basis

#### MV (Materialized View) - 실시간 처리 / Real-time Processing
- INSERT 시점마다 즉시 트리거 / Triggered immediately on every INSERT
- 개별 row/block 단위로 aggregation 수행 / Performs aggregation on individual row/block basis
- 매 INSERT마다 새로운 part 생성 / Creates new parts for every INSERT
- 잦은 merge 발생으로 높은 I/O 부하 / High I/O load due to frequent merges

#### RMV (Refreshable Materialized View) - 배치 처리 / Batch Processing
- 5분치 데이터를 한 번에 처리 / Processes 5 minutes worth of data at once
- 배치 처리로 인한 I/O 최적화 / I/O optimization through batch processing
- 적은 part 수로 효율적인 merge / Efficient merges with fewer parts
- 간헐적 리소스 사용 (스파이크 패턴) / Intermittent resource usage (spike pattern)

### 예상 결과 / Expected Results

| 메트릭 / Metric | MV (실시간) / MV (Real-time) | RMV (5분 배치) / RMV (5-min Batch) |
|----------------|------------------------------|-------------------------------------|
| CPU 사용량 / CPU Usage | 높음 (지속적) / High (continuous) | 낮음 (간헐적 스파이크) / Low (intermittent spikes) |
| Memory Peak | 낮지만 지속적 / Low but continuous | 높지만 간헐적 / High but intermittent |
| Disk I/O | 많음 (잦은 write) / High (frequent writes) | 적음 (배치 write) / Low (batch writes) |
| Part 수 / Part Count | 많음 / High | 적음 / Low |
| Merge 횟수 / Merge Count | 많음 / High | 적음 / Low |
| 총 처리 시간 / Total Processing Time | 높음 / High | 낮음 / Low |

---

## 🏗️ 테스트 아키텍처 / Test Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Source Table                              │
│              events_source (MergeTree)                       │
│   - 30분간 지속적 INSERT (1초당 ~1000 rows)                  │
│   - 30 minutes continuous INSERT (~1000 rows/sec)           │
└─────────────────┬───────────────────────┬───────────────────┘
                  │                       │
                  ▼                       ▼
    ┌─────────────────────┐   ┌─────────────────────────┐
    │   MV (실시간)        │   │   RMV (5분 주기)         │
    │   MV (Real-time)    │   │   RMV (5-min interval)  │
    │ events_mv_realtime  │   │ events_rmv_batch        │
    │ INSERT 시 즉시 실행  │   │ REFRESH EVERY 5 MINUTE  │
    │ Trigger on INSERT   │   │ Refresh every 5 minutes │
    └─────────────────────┘   └─────────────────────────┘
                  │                       │
                  ▼                       ▼
    ┌─────────────────────┐   ┌─────────────────────────┐
    │  Target Table       │   │   Target Table          │
    │ events_agg_mv       │   │ events_agg_rmv          │
    │ (SummingMergeTree)  │   │ (MergeTree)             │
    └─────────────────────┘   └─────────────────────────┘
                  │                       │
                  └───────────┬───────────┘
                              ▼
            ┌─────────────────────────────┐
            │   Monitoring Tables         │
            │ - resource_metrics          │
            │ - parts_history             │
            │ - merge_activity            │
            └─────────────────────────────┘
```

---

## 📊 측정 지표 / Metrics to Measure

### 1. 쿼리 성능 메트릭 / Query Performance Metrics
- 쿼리 실행 횟수 / Query execution count
- 총 처리 시간 / Total processing time
- 평균 쿼리 실행 시간 / Average query execution time

### 2. 메모리 사용량 / Memory Usage
- 총 메모리 사용량 / Total memory usage
- 피크 메모리 사용량 / Peak memory usage
- 시간대별 메모리 패턴 / Memory usage pattern over time

### 3. I/O 메트릭 / I/O Metrics
- 읽은 행 수 / Rows read
- 읽은 바이트 수 / Bytes read
- 쓴 행 수 / Rows written
- 쓴 바이트 수 / Bytes written

### 4. Part 관리 / Part Management
- Part 생성 횟수 / Part creation count
- Active part 수 / Active part count
- Disk 사용량 / Disk usage
- Part 크기 분포 / Part size distribution

### 5. Merge 활동 / Merge Activity
- Merge 횟수 / Merge count
- 총 Merge 시간 / Total merge time
- 평균 Merge 시간 / Average merge time
- Merge 중 메모리 사용량 / Memory usage during merge

---

## 🔧 테스트 준비 단계 / Test Preparation Steps

### Step 1: 환경 연결 확인 / Environment Connection Check
```bash
clickhouse client \
  --host a7rzc4b3c1.ap-northeast-2.aws.clickhouse.cloud \
  --secure \
  --password HTPiB0FXg8.3K \
  --query "SELECT version(), currentDatabase()"
```

### Step 2: 데이터베이스 및 테이블 생성 / Database and Table Creation
- Database 생성 / Create database
- Source table 생성 / Create source table
- MV target table 및 MV 생성 / Create MV target table and MV
- RMV target table 및 RMV 생성 / Create RMV target table and RMV
- Monitoring tables 생성 / Create monitoring tables

### Step 3: 데이터 생성 스크립트 준비 / Data Generation Script Preparation
- Python 스크립트 작성 / Write Python script
- 1초당 1,000 rows INSERT / INSERT 1,000 rows per second
- 30분 지속 실행 / Run for 30 minutes

### Step 4: 모니터링 스크립트 준비 / Monitoring Script Preparation
- 1분마다 메트릭 수집 / Collect metrics every minute
- Resource metrics 수집 / Collect resource metrics
- Parts history 수집 / Collect parts history
- Merge activity 수집 / Collect merge activity

---

## 🚀 테스트 실행 절차 / Test Execution Procedure

### Phase 1: 초기화 / Initialization (T+0)
1. ✅ 테스트 세션 생성 및 session_id 기록
   - Create test session and record session_id
2. ✅ MV/RMV 상태 확인
   - Verify MV/RMV status
3. ✅ 모든 테이블 비어있는지 확인
   - Verify all tables are empty

### Phase 2: 데이터 생성 시작 / Start Data Generation (T+0 ~ T+30m)
1. ✅ Python 데이터 생성 스크립트 실행
   - Start Python data generation script
2. ✅ 백그라운드에서 1초당 1,000 rows INSERT
   - INSERT 1,000 rows per second in background

### Phase 3: 모니터링 수집 / Monitoring Collection (T+0 ~ T+30m)
1. ✅ 1분마다 메트릭 수집 스크립트 실행
   - Run metrics collection script every minute
2. ✅ Resource metrics 수집
   - Collect resource metrics
3. ✅ Parts history 수집
   - Collect parts history
4. ✅ Merge activity 수집
   - Collect merge activity

### Phase 4: 데이터 생성 종료 / Stop Data Generation (T+30m)
1. ✅ Python 스크립트 중지
   - Stop Python script
2. ✅ 최종 메트릭 수집
   - Collect final metrics
3. ✅ 테스트 세션 종료 마킹
   - Mark test session as ended

### Phase 5: 결과 분석 / Results Analysis (T+30m ~ T+35m)
1. ✅ 전체 리소스 사용량 비교
   - Compare overall resource usage
2. ✅ 시간대별 리소스 추이 분석
   - Analyze resource trends over time
3. ✅ Part 증가 추이 비교
   - Compare part growth trends
4. ✅ Merge 활동 비교
   - Compare merge activity
5. ✅ 효율성 지표 계산
   - Calculate efficiency metrics

---

## 📈 분석 쿼리 목록 / Analysis Query List

### 1. 전체 리소스 사용량 비교 / Overall Resource Usage Comparison
```sql
-- 쿼리 실행 횟수, 총 처리 시간, 메모리 사용량 등
-- Query execution count, total processing time, memory usage, etc.
```

### 2. 시간대별 리소스 추이 / Resource Trends Over Time
```sql
-- 분 단위로 MV/RMV의 리소스 사용 패턴 비교
-- Compare MV/RMV resource usage patterns by minute
```

### 3. Part 증가 추이 비교 / Part Growth Comparison
```sql
-- 테이블별 part 수 변화, disk 사용량 변화
-- Part count changes and disk usage changes by table
```

### 4. Merge 활동 비교 / Merge Activity Comparison
```sql
-- Merge 횟수, 총 merge 시간, 평균 merge 시간
-- Merge count, total merge time, average merge time
```

### 5. 효율성 지표 계산 / Efficiency Metrics Calculation
```sql
-- MV vs RMV 효율성 비율 계산
-- Calculate MV vs RMV efficiency ratio
```

---

## 📝 예상 결과 시나리오 / Expected Result Scenarios

### 시나리오 A: RMV가 더 효율적인 경우 / Scenario A: RMV is More Efficient
- 총 처리 시간: RMV < MV / Total processing time: RMV < MV
- Part 수: RMV < MV / Part count: RMV < MV
- Merge 횟수: RMV < MV / Merge count: RMV < MV
- 결론: 배치 처리가 리소스 효율적 / Conclusion: Batch processing is more resource efficient

### 시나리오 B: MV가 더 효율적인 경우 / Scenario B: MV is More Efficient
- 메모리 사용량: MV < RMV / Memory usage: MV < RMV
- Peak 메모리: MV < RMV / Peak memory: MV < RMV
- 결론: 실시간 처리가 메모리 효율적 / Conclusion: Real-time processing is more memory efficient

### 시나리오 C: 혼합 결과 / Scenario C: Mixed Results
- 각 지표별로 장단점 존재 / Pros and cons for each metric
- Use case별 권장사항 도출 / Derive recommendations by use case

---

## ⚠️ 주의사항 / Precautions

### 1. RMV APPEND 모드 중복 방지 / RMV APPEND Mode Duplication Prevention
- WHERE 절에 시간 범위 명확히 지정 / Clearly specify time range in WHERE clause
- 데이터 검증 쿼리로 중복 확인 / Verify duplicates with data validation query

### 2. 테스트 환경 격리 / Test Environment Isolation
- 다른 워크로드의 영향 최소화 / Minimize impact from other workloads
- 테스트 전후 시스템 상태 확인 / Check system status before and after test

### 3. 메트릭 수집 주기 / Metrics Collection Interval
- 1분 주기가 너무 길면 세밀한 변화 놓칠 수 있음 / 1-minute interval may miss fine-grained changes
- 필요시 30초 또는 15초로 조정 / Adjust to 30 or 15 seconds if needed

### 4. RMV Refresh 주기 / RMV Refresh Interval
- 5분 주기가 적절한지 검증 / Verify if 5-minute interval is appropriate
- 필요시 1분, 10분 등 다른 주기 테스트 / Test other intervals (1 min, 10 min) if needed

---

## 🎯 성공 기준 / Success Criteria

### 정량적 기준 / Quantitative Criteria
- ✅ 30분간 약 1,800,000 rows 성공적으로 INSERT
  - Successfully INSERT approximately 1,800,000 rows over 30 minutes
- ✅ MV와 RMV 모두 정상 작동 확인
  - Verify both MV and RMV are functioning properly
- ✅ 모든 메트릭 성공적으로 수집 (누락 없음)
  - Successfully collect all metrics (no missing data)

### 정성적 기준 / Qualitative Criteria
- ✅ MV vs RMV의 리소스 효율성 차이 명확히 파악
  - Clearly identify resource efficiency differences between MV and RMV
- ✅ Use case별 권장사항 도출 가능
  - Derive recommendations by use case
- ✅ 재현 가능한 테스트 절차 확립
  - Establish reproducible test procedure

---

## 📋 체크리스트 / Checklist

### 테스트 준비 / Test Preparation
- [ ] ClickHouse Cloud 연결 확인 / Verify ClickHouse Cloud connection
- [ ] Database 생성 / Create database
- [ ] 모든 테이블 생성 / Create all tables
- [ ] MV/RMV 정의 생성 / Create MV/RMV definitions
- [ ] 데이터 생성 스크립트 작성 / Write data generation script
- [ ] 모니터링 스크립트 작성 / Write monitoring script

### 테스트 실행 / Test Execution
- [ ] 테스트 세션 생성 및 session_id 기록 / Create test session and record session_id
- [ ] 데이터 생성 시작 / Start data generation
- [ ] 모니터링 수집 시작 / Start monitoring collection
- [ ] 30분 대기 / Wait for 30 minutes
- [ ] 데이터 생성 중지 / Stop data generation
- [ ] 최종 메트릭 수집 / Collect final metrics
- [ ] 테스트 세션 종료 마킹 / Mark test session as ended

### 결과 분석 / Results Analysis
- [ ] 전체 리소스 사용량 비교 / Compare overall resource usage
- [ ] 시간대별 리소스 추이 분석 / Analyze resource trends over time
- [ ] Part 증가 추이 비교 / Compare part growth trends
- [ ] Merge 활동 비교 / Compare merge activity
- [ ] 효율성 지표 계산 / Calculate efficiency metrics
- [ ] 최종 보고서 작성 / Write final report

---

## 📄 테스트 결과 보고서 템플릿 / Test Results Report Template

**다음 파일에 작성 예정 / To be written in:**
`test-results-report.md`

---

## 🔗 참고 문서 / Reference Documents

- Original Test Plan: `mv-rmv-test-plan.md`
- Setup Scripts: `setup/` directory
- Data Generation Scripts: `scripts/` directory
- Analysis Queries: `queries/` directory
- Final Report: `test-results-report.md`

---

**작성일 / Created**: 2025-12-16
**작성자 / Author**: Claude Code
**버전 / Version**: 1.0
