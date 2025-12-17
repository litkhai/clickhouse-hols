# Quick Start Guide

ClickHouse Deduplication Test Suite를 5분 안에 실행하는 방법

## 1. 사전 준비 (1분)

```bash
# 디렉토리 이동
cd /Users/kenlee/Documents/GitHub/clickhouse-hols/workload/dedup-engine

# Python 패키지 설치 (이미 설치되어 있으면 스킵)
pip3 install clickhouse-connect python-dotenv
```

## 2. 연결 정보 확인 (1분)

`.env` 파일이 이미 생성되어 있습니다:
```bash
cat .env
```

내용 확인:
```
CH_HOST=<your-service>.<region>.aws.clickhouse.cloud
CH_PORT=8443
CH_USERNAME=default
CH_PASSWORD=<YOUR_PASSWORD>
CH_DATABASE=default
CH_SECURE=true
```

## 3. 테스트 실행 (3분)

### 옵션 A: 대화형 모드
```bash
python3 run_all_tests.py
```

메뉴에서 선택:
- `1`: Phase 1 (Engine 비교)
- `2`: Phase 2 (Insert 패턴 성능)
- `3`: Phase 3 (아키텍처 검증)
- `4`: 전체 테스트
- `0`: 종료

### 옵션 B: CLI 모드

```bash
# Phase 1만 실행 (Engine 비교)
python3 run_all_tests.py 1

# Phase 2만 실행 (Insert 패턴)
python3 run_all_tests.py 2

# Phase 3만 실행 (아키텍처)
python3 run_all_tests.py 3

# 전체 테스트
python3 run_all_tests.py all
```

### 옵션 C: 개별 실행

```bash
# Phase 1: Engine 비교 테스트
python3 phase1_engine_comparison.py

# Phase 2: Insert 패턴 성능 테스트
python3 phase2_insert_patterns.py

# Phase 3: 권장 아키텍처 검증
python3 phase3_architecture.py
```

## 4. 결과 확인

각 Phase가 완료되면 다음과 같은 결과를 볼 수 있습니다:

### Phase 1 결과 예시
```
Engine        | Raw Count | Dedup Count | After OPTIMIZE | Success
---------------------------------------------------------------------
MergeTree     | 13,000    | 10,000      | 13,000         | ❌
ReplacingMT   | 10,000    | 10,000      | 10,000         | ✅
CollapsingMT  | 10,000    | 10,000      | 10,000         | ✅
AggregatingMT | 10,000    | 10,000      | 10,000         | ✅
```

### Phase 2 결과 예시
```
Method       | Records | Time (s) | Rate (rows/s)
--------------------------------------------------
row_by_row   | 1,000   | 61.31    | 16
micro_batch  | 10,000  | 8.31     | 1,203
batch        | 10,000  | 0.27     | 36,743
async_insert | 1,000   | 10.23    | 98
```

### Phase 3 결과 예시
```
항목              | 레코드 수  | 비고
-----------------------------------------
Landing         | 13,000 | 원본 데이터
Main (Raw)      | 10,810 | MV로 전달된 데이터
Main (FINAL)    | 10,000 | Dedup 후 데이터
Hourly Agg      | 6,088  | Refreshable MV
Expected Unique | 10,000 | 목표값

검증 결과:
  ✅ Main FINAL = Expected Unique
  ✅ Main에서 Dedup 동작 확인
```

## 5. 정리 (옵션)

테스트 완료 후 생성된 테이블을 정리하려면:

```bash
# ClickHouse 클라이언트 접속
clickhouse client --host <your-service>.<region>.aws.clickhouse.cloud \
  --secure --password <YOUR_PASSWORD>

# 데이터베이스 삭제
DROP DATABASE IF EXISTS dedup;

# 종료
exit
```

## 📊 주요 발견사항 요약

1. **Engine 선택**: ReplacingMergeTree 권장
2. **Insert 성능**: Batch가 Row-by-row보다 **2,251배 빠름**
3. **아키텍처**: Landing → Main → Refreshable MV 구조 권장

## 📚 더 알아보기

- [README.md](README.md): 전체 가이드
- [TEST_RESULTS.md](TEST_RESULTS.md): 상세 테스트 결과
- [dedup_test_plan.md](dedup_test_plan.md): 완전한 테스트 계획서

## 🐛 문제 해결

### 연결 오류
```
✗ ClickHouse 연결 실패
```
→ `.env` 파일의 연결 정보 확인

### 권한 오류
```
Not enough privileges
```
→ 사용자에게 데이터베이스 생성 권한 필요

### 패키지 오류
```
ModuleNotFoundError: No module named 'clickhouse_connect'
```
→ `pip3 install clickhouse-connect python-dotenv` 실행

---

**Happy Testing! 🚀**
