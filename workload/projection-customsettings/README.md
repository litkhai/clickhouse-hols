# ClickHouse Projection Custom Settings Lab

Projection의 Custom Settings (특히 index_granularity) 설정 방법과 효과를 학습하는 실습입니다.

## 📋 개요

ClickHouse 25.12+ 버전부터 Projection에 대해 독립적인 설정(index_granularity 등)을 지정할 수 있습니다. 이 기능을 통해 원본 테이블과 다른 granularity를 가진 Projection을 생성하여 특정 쿼리 패턴에 최적화할 수 있습니다.

## 🎯 학습 목표

1. Projection에 Custom Settings 적용하는 방법 이해
2. Index Granularity가 Point Query 성능에 미치는 영향 분석
3. 다양한 Granularity 설정의 트레이드오프 파악
4. 실제 성능 측정 및 모니터링 방법 학습

## 📁 파일 구조

```
projection-customsettings/
├── 01-setup.sql                      # 데이터베이스 및 테이블 생성
├── 02-add-projections.sql            # Projection 생성 및 Custom Settings
├── 03-granularity-comparison.sql     # Granularity별 성능 비교
├── 04-performance-tests.sql          # 성능 테스트 쿼리
├── 05-monitoring.sql                 # 모니터링 및 분석
├── 99-cleanup.sql                    # 정리
└── README.md                         # 본 문서
```

## 🚀 실습 순서

### 1. 환경 준비 및 데이터 생성
```bash
# 01-setup.sql 실행
```
- 테스트 데이터베이스 생성
- 이벤트 테이블 생성 (기본 granularity=8192)
- 100만 행의 샘플 데이터 삽입

### 2. Projection 생성
```bash
# 02-add-projections.sql 실행
```
- 기본 Projection 생성 (현재 버전)
- Custom Settings를 사용한 Projection 예제 (25.12+)
- Projection 상태 확인

### 3. Granularity 비교 분석
```bash
# 03-granularity-comparison.sql 실행
```
- 기존 granularity_test DB 활용
- G=256, 1024, 4096, 8192 비교
- 스토리지 및 인덱스 오버헤드 분석

### 4. 성능 테스트
```bash
# 04-performance-tests.sql 실행
```
- Point Query 성능 측정
- Range Query 성능 측정
- 집계 쿼리 성능 비교

### 5. 모니터링
```bash
# 05-monitoring.sql 실행
```
- Query Log 분석
- Projection 사용률 확인
- Parts 및 Merges 모니터링

## 🔑 핵심 개념

### Projection Custom Settings (25.12+)

```sql
ALTER TABLE events
ADD PROJECTION user_lookup (
    SELECT * ORDER BY user_id, event_time
) WITH SETTINGS (
    index_granularity = 256
);
```

### Index Granularity 효과

| Granularity | Marks | 인덱스 오버헤드 | Point Query | Range Scan |
|-------------|-------|----------------|-------------|------------|
| 256         | 많음   | 높음 (~0.09%)  | 매우 빠름    | 느림       |
| 1024        | 중간   | 중간 (~0.02%)  | 빠름        | 보통       |
| 4096        | 적음   | 낮음 (~0.005%) | 보통        | 빠름       |
| 8192        | 매우적음| 매우낮음 (~0.004%)| 느림     | 매우 빠름  |

### 권장 사항

**쿼리 패턴별 최적 Granularity:**
- Point Query (단일 키 조회): 256~512
- Small Range Query: 512~1024
- Medium Range Query: 1024~2048
- Large Range Scan: 4096~8192
- Full Table Scan: 8192~16384

## 📊 실측 결과 예시

### Point Query (player_id = 500000)
```
G=256:  약 256 rows 읽음
G=8192: 약 8192 rows 읽음
→ 32배 성능 차이
```

### Storage Overhead (200만 행 기준)
```
G=256:  7,814 marks, 66.34 MiB, 0.09% 인덱스 오버헤드
G=8192:   245 marks, 54.02 MiB, 0.004% 인덱스 오버헤드
```

## ⚠️ 버전 호환성

- **25.10 이하**: WITH SETTINGS 문법 미지원
  - Projection은 원본 테이블의 granularity를 상속
- **25.12 이상**: WITH SETTINGS 문법 지원
  - Projection별 독립적인 granularity 설정 가능

## 🧪 실전 시나리오

### 다중 Projection 전략
```sql
-- Point Query 최적화
ADD PROJECTION user_lookup (...) WITH SETTINGS (index_granularity = 256);

-- Session 분석 최적화
ADD PROJECTION session_analysis (...) WITH SETTINGS (index_granularity = 512);

-- 집계 쿼리 최적화
ADD PROJECTION event_stats (...) WITH SETTINGS (index_granularity = 2048);
```

## 📚 참고 자료

- [ClickHouse Projections](https://clickhouse.com/docs/en/sql-reference/statements/alter/projection)
- [Index Granularity](https://clickhouse.com/docs/en/optimize/sparse-primary-indexes)
- [Performance Optimization](https://clickhouse.com/docs/en/operations/optimizing-performance)

## 🧹 정리

```bash
# 99-cleanup.sql 실행
```
테스트 데이터베이스 및 모든 테이블을 삭제합니다.

---

**작성일**: 2025-01-09
**테스트 환경**: ClickHouse Cloud 25.10.1
**대상 버전**: ClickHouse 25.12+ (Custom Settings 지원)
