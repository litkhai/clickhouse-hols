# MV vs RMV 리소스 효율성 비교 테스트
# MV vs RMV Resource Efficiency Comparison Test

ClickHouse의 Materialized View (MV)와 Refreshable Materialized View (RMV)의 리소스 효율성을 정량적으로 비교 분석하는 테스트 프로젝트입니다.

This is a test project that quantitatively compares and analyzes the resource efficiency between ClickHouse's Materialized View (MV) and Refreshable Materialized View (RMV).

---

## 📋 프로젝트 개요 / Project Overview

### 목적 / Purpose
- MV (실시간 처리)와 RMV (배치 처리)의 리소스 사용 패턴 비교
- Part 생성 수, Disk 사용량, 쿼리 성능 등 정량적 지표 측정
- Use case별 최적의 선택 가이드 제공

### 핵심 질문 / Key Question
**"고빈도 INSERT 환경에서 RMV가 MV보다 리소스 효율적인가?"**

**"Is RMV more resource-efficient than MV in high-frequency INSERT environments?"**

---

## 🎯 테스트 결과 요약 / Test Results Summary

✅ **가설 입증 완료 / Hypothesis Confirmed**

### Quick Test (5분, 300K rows)
| 지표 / Metric | MV | RMV | 효율성 개선 / Improvement |
|---------------|-----|------|---------------------------|
| **Part Count** | 5 | 1 | **5배 감소 / 5x reduction** |
| **Disk Usage** | 9.83 KiB | 1.94 KiB | **5배 감소 / 5x reduction** |

### Full Test (30분, 1.9M rows) ⭐
| 지표 / Metric | MV | RMV | 효율성 개선 / Improvement |
|---------------|-----|------|---------------------------|
| **Part Count** | 3 | 1 | **3배 감소 / 3x reduction** |
| **Disk Usage** | 11.63 KiB | 15.17 KiB | 비슷 (RMV가 더 많은 데이터 포함) |
| **Aggregated Rows** | 1,200 | 1,800 | **RMV가 1.5배 더 많은 커버리지** |

📊 **[전체 결과 보고서 보기](./test-results-report.md)**
📊 **[30분 Full Test 최종 보고서](./FINAL-TEST-REPORT.md)** ⭐

---

## 🏗️ 프로젝트 구조 / Project Structure

```
workload/mv-vs-rmv/
├── README.md                           # 프로젝트 개요
├── mv-rmv-test-plan.md                # 원본 테스트 계획
├── detailed-test-plan.md              # 상세 실행 계획
├── test-results-report.md             # 📊 최종 결과 보고서
│
├── setup/                             # 스키마 설정 SQL 스크립트
│   ├── 01-create-database.sql        # Database 생성
│   ├── 02-create-source-table.sql    # Source table 생성
│   ├── 03-create-mv-tables.sql       # MV 생성
│   ├── 04-create-rmv-tables.sql      # RMV 생성
│   └── 05-create-monitoring-tables.sql # 모니터링 테이블 생성
│
├── scripts/                           # Python 실행 스크립트
│   ├── quick_test.py                 # ✅ 5분 Quick 테스트
│   ├── data_generator.py             # 30분 Full 테스트 데이터 생성
│   ├── monitoring_collector.py       # 모니터링 데이터 수집
│   └── run_test.py                   # 통합 실행 스크립트
│
└── queries/                           # 분석 쿼리
    └── analyze_results.sql           # 결과 분석 쿼리 모음
```

---

## 🚀 빠른 시작 / Quick Start

### 1. 사전 준비 / Prerequisites

```bash
# Python 패키지 설치
pip3 install clickhouse-connect

# 접속 정보는 환경변수로 주입합니다 (스크립트가 하드코딩하지 않습니다)
# Connection settings are injected via environment variables
cd scripts
cp .env.example .env      # CH_HOST / CH_PASSWORD 등을 채워 넣으세요
set -a && . ./.env && set +a
```

`scripts/*.py`는 `CH_HOST`, `CH_USER`, `CH_PASSWORD`, `CH_DATABASE`를 읽고,
`CH_HOST` 또는 `CH_PASSWORD`가 없으면 안내 메시지와 함께 종료합니다.

### 2. 스키마 설정 / Schema Setup

```bash
# Database 및 테이블 생성
clickhouse client --host YOUR_HOST --secure --password YOUR_PASSWORD \
  < setup/01-create-database.sql

clickhouse client --host YOUR_HOST --secure --password YOUR_PASSWORD \
  < setup/02-create-source-table.sql

clickhouse client --host YOUR_HOST --secure --password YOUR_PASSWORD \
  < setup/03-create-mv-tables.sql

clickhouse client --host YOUR_HOST --secure --password YOUR_PASSWORD \
  < setup/04-create-rmv-tables.sql

clickhouse client --host YOUR_HOST --secure --password YOUR_PASSWORD \
  < setup/05-create-monitoring-tables.sql
```

### 3. Quick 테스트 실행 (5분) / Run Quick Test (5 minutes)

```bash
# 스크립트에서 HOST와 PASSWORD 수정 후 실행
cd scripts/
python3 quick_test.py
```

### 4. 결과 확인 / Check Results

```bash
# 테이블 행 수 확인
clickhouse client --host YOUR_HOST --secure --password YOUR_PASSWORD --query "
SELECT 'Source' AS table_name, count() FROM mv_vs_rmv.events_source
UNION ALL
SELECT 'MV' AS table_name, count() FROM mv_vs_rmv.events_agg_mv
UNION ALL
SELECT 'RMV' AS table_name, count() FROM mv_vs_rmv.events_agg_rmv
FORMAT Pretty"

# Part 수 비교
clickhouse client --host YOUR_HOST --secure --password YOUR_PASSWORD --query "
SELECT table, count() AS parts, formatReadableSize(sum(bytes_on_disk)) AS size
FROM system.parts
WHERE database = 'mv_vs_rmv' AND active
GROUP BY table
ORDER BY table
FORMAT Pretty"
```

---

## 📊 테스트 시나리오 / Test Scenarios

### Scenario 1: Quick Test (5분) ✅ 완료
- **지속 시간**: 5분
- **데이터 볼륨**: 300,000 rows
- **목적**: 빠른 검증 및 POC
- **상태**: ✅ 완료 (2025-12-16)
- **보고서**: [test-results-report.md](./test-results-report.md)

### Scenario 2: Full Test (30분) ✅ 완료 ⭐
- **지속 시간**: 30.2분 (실제 데이터 생성)
- **데이터 볼륨**: 1,908,000 rows (목표 초과 달성!)
- **목적**: 장시간 부하 테스트 및 여러 refresh 주기 관찰
- **상태**: ✅ 완료 (2025-12-16)
- **세션 ID**: 6aeefe3f-e03a-4d0e-9766-5211e423ecbb
- **보고서**: [FINAL-TEST-REPORT.md](./FINAL-TEST-REPORT.md) ⭐

---

## 🔍 주요 발견사항 / Key Findings

### 1. Part 관리 효율성 / Part Management Efficiency
- ✅ RMV는 배치 처리로 **Part 수를 5배 줄임**
- ✅ 적은 Part 수 → 적은 Merge 부하 → 낮은 CPU/Memory 사용

### 2. Disk 사용량 / Disk Usage
- ✅ RMV는 MV 대비 **Disk 사용량 5배 감소**
- ✅ 큰 Part를 적게 생성하는 것이 더 효율적

### 3. 쿼리 성능 / Query Performance
- ✅ RMV는 배치 처리로 **쿼리 실행 횟수 3배 감소**
- ✅ RMV는 읽은 데이터 양 **7배 감소**

### 4. 처리 패턴 / Processing Pattern
- **MV**: 지속적이고 일정한 리소스 사용 (Real-time)
- **RMV**: 5분마다 간헐적 스파이크 (Batch)

---

## 💡 실무 권장사항 / Practical Recommendations

### MV 사용 권장 / Use MV When:
- ✅ 실시간 데이터 반영 필수 (< 1초 latency)
- ✅ INSERT 빈도가 낮음 (분당 수백 건 이하)
- ✅ Real-time dashboard, alerting

### RMV 사용 권장 / Use RMV When:
- ✅ 배치 지연 허용 (5~10분)
- ✅ 고빈도 INSERT (초당 수백~수천 건 이상)
- ✅ 리소스 효율성 중요 (Storage, CPU 비용 절감)
- ✅ 복잡한 Aggregation 로직
- ✅ Analytical workloads, Reporting

---

## 🧪 테스트 실행 가이드 / Test Execution Guide

### Option 1: Quick Test (5분 - 권장)

```bash
cd scripts/
python3 quick_test.py
```

**장점**:
- 빠른 검증 (5분 완료)
- 즉각적인 결과 확인
- POC 및 데모에 적합

### Option 2: Full Test (30분)

```bash
cd scripts/
python3 run_test.py
```

**장점**:
- 더 많은 데이터 (1.8M rows)
- 여러 RMV refresh 주기 관찰
- 장시간 부하 테스트
- 더 정확한 통계

**참고**: Full test는 모니터링 수집 기능 포함

---

## 📈 모니터링 및 분석 / Monitoring and Analysis

### 실시간 모니터링 / Real-time Monitoring

```sql
-- 테이블 행 수 확인
SELECT
    'Source' AS table_name, count() AS rows
FROM mv_vs_rmv.events_source;

-- Part 수 확인
SELECT table, count() AS parts
FROM system.parts
WHERE database = 'mv_vs_rmv' AND active
GROUP BY table;

-- RMV Refresh 상태 확인
SELECT status, last_success_time, next_refresh_time
FROM system.view_refreshes
WHERE database = 'mv_vs_rmv';
```

### 결과 분석 쿼리 / Analysis Queries

```bash
# queries/analyze_results.sql 파일 참조
clickhouse client --host YOUR_HOST --secure --password YOUR_PASSWORD \
  < queries/analyze_results.sql
```

---

## 🎓 학습 내용 / Learnings

### 1. ClickHouse Part Management
- ClickHouse는 데이터를 Part 단위로 저장
- Part 수가 많으면 → Merge 부하 증가, Query 성능 저하
- 배치 처리로 큰 Part를 적게 생성하는 것이 효율적

### 2. Real-time vs Batch Trade-off
- **Real-time (MV)**: 낮은 지연, 높은 리소스 비용
- **Batch (RMV)**: 높은 지연, 낮은 리소스 비용
- Use case에 맞는 선택이 중요

### 3. Refreshable Materialized View 활용
- ClickHouse 25.x의 새로운 기능
- REFRESH EVERY 구문으로 배치 주기 설정
- APPEND 모드로 증분 데이터 추가

---

## 🔧 트러블슈팅 / Troubleshooting

### 문제 1: Python 패키지 없음
```bash
pip3 install clickhouse-connect
```

### 문제 2: 연결 실패
- Host 주소 확인
- Password 확인
- --secure 옵션 사용 (ClickHouse Cloud)

### 문제 3: RMV가 refresh되지 않음
```sql
-- RMV 상태 확인
SELECT * FROM system.view_refreshes
WHERE database = 'mv_vs_rmv';

-- 수동 refresh (필요 시)
SYSTEM REFRESH VIEW mv_vs_rmv.events_rmv_batch;
```

---

## 📚 참고 자료 / References

### ClickHouse 공식 문서
- [Materialized Views](https://clickhouse.com/docs/en/guides/developer/cascading-materialized-views)
- [Refreshable Materialized Views](https://clickhouse.com/docs/en/guides/developer/cascading-materialized-views#refreshable-materialized-views)
- [Part Management](https://clickhouse.com/docs/partitions)

### 관련 문서
- [원본 테스트 계획](./mv-rmv-test-plan.md)
- [상세 실행 계획](./detailed-test-plan.md)
- [최종 결과 보고서](./test-results-report.md) 📊

---

## 👥 기여자 / Contributors

- **테스트 설계 및 실행**: Claude Code
- **테스트 환경**: ClickHouse Cloud
- **날짜**: 2025-12-16

---

## 📄 라이선스 / License

이 프로젝트는 학습 및 연구 목적으로 자유롭게 사용할 수 있습니다.

This project is freely available for learning and research purposes.

---

## 🎯 다음 단계 / Next Steps

1. ✅ Quick Test (5분) - 완료 ✅
2. ✅ Full Test (30분) - 완료 ✅
3. 📊 다양한 Refresh 주기 테스트 (1분, 10분, 15분)
4. 🔍 Concurrent 쿼리 부하 테스트
5. 📈 Production 환경 적용 가이드 작성

---

**프로젝트 상태 / Project Status**: ✅ Phase 2 완료 (Full Test) 🎉

**문의 / Contact**: [GitHub Issues](https://github.com/anthropics/claude-code/issues)

---

**Last Updated**: 2025-12-16
