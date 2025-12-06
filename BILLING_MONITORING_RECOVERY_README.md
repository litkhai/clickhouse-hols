# ClickHouse Billing Monitoring 시스템 복구 가이드

## 📋 문서 개요
이 문서는 billing_monitoring 스키마의 데이터 손실 문제를 해결하고, 향후 동일한 문제가 발생하지 않도록 하는 방법을 설명합니다.

## 🚨 문제 상황

### 발견된 문제
- `hourly_raw_metrics` 테이블: 데이터 0건
- `hourly_cost_analysis` 테이블: 데이터 0건
- Refreshable Materialized View(RMV)가 실행되었지만 `written_rows = 0`

### 원인 분석
1. RMV의 쿼리 로직에 문제가 있어 데이터가 테이블에 삽입되지 않음
2. quantile 함수 사용 시 문법 오류 (`quantile(0.5, value, condition)` → `quantileIf(0.5)(value, condition)`)
3. 시간 범위 설정 문제로 타겟 시간대의 데이터가 올바르게 수집되지 않음

## ✅ 해결 방법

### 1. 자동 복구 (권장)
복구 스크립트를 실행하여 자동으로 문제를 해결합니다:

```bash
# ClickHouse 클라이언트에서 실행
clickhouse-client --queries-file billing_monitoring_recovery.sql
```

### 2. 수동 복구
단계별로 수동 복구를 진행할 수 있습니다:

#### Step 1: RMV 재생성
```sql
-- hourly_raw_metrics RMV 삭제 및 재생성
DROP VIEW IF EXISTS billing_monitoring.rmv_hourly_raw_metrics;
CREATE MATERIALIZED VIEW billing_monitoring.rmv_hourly_raw_metrics
REFRESH EVERY 1 HOUR
TO billing_monitoring.hourly_raw_metrics
AS
-- (전체 쿼리는 billing_monitoring_recovery.sql 참조)
```

#### Step 2: 데이터 백필
```sql
-- 과거 24시간 데이터 백필
INSERT INTO billing_monitoring.hourly_raw_metrics
-- (전체 쿼리는 billing_monitoring_recovery.sql 참조)
```

#### Step 3: 검증
```sql
-- 데이터 확인
SELECT count(*) FROM billing_monitoring.hourly_raw_metrics;
SELECT * FROM billing_monitoring.v_dashboard ORDER BY hour DESC LIMIT 5;
```

## 🔍 시스템 구조

### 데이터 흐름
```
system.asynchronous_metric_log
    ↓
rmv_hourly_raw_metrics (RMV, 매 시간 실행)
    ↓
hourly_raw_metrics (테이블)
    ↓
rmv_hourly_cost_analysis (RMV, 매 시간 5분 offset)
    ↓
hourly_cost_analysis (테이블)
    ↓
v_dashboard (뷰)
```

### 주요 테이블

#### 1. hourly_raw_metrics
시스템 메트릭의 시간별 집계 데이터

**주요 컬럼:**
- `hour`: 집계 시간 (DateTime)
- `cpu_usage_avg`: 평균 CPU 사용량
- `memory_usage_pct_avg`: 평균 메모리 사용률
- `allocated_cpu`: 할당된 CPU 코어 수
- `service_name`: 서비스 이름 (기본값: 'Seoul')

**데이터 보존 기간:** 365일 (TTL)

#### 2. hourly_cost_analysis
비용 분석 및 효율성 메트릭

**주요 컬럼:**
- `estimated_hourly_total_chc`: 시간당 예상 비용
- `cpu_efficiency_pct`: CPU 효율성 (%)
- `unused_compute_cost_hourly`: 시간당 낭비 비용
- `alert_any`: 이상 감지 플래그 (0 또는 1)

**데이터 보존 기간:** 365일 (TTL)

#### 3. daily_billing
일별 청구 데이터 (ClickHouse Cloud API에서 수집)

**주요 컬럼:**
- `date`: 날짜
- `service_name`: 서비스 이름
- `total_chc`: 총 비용 (CHC)
- `compute_chc`: Compute 비용
- `storage_chc`: Storage 비용
- `network_chc`: Network 비용

**데이터 보존 기간:** 730일 (2년)

## 🔧 주요 수정 사항

### 1. quantile 함수 수정
```sql
-- 수정 전 (오류)
quantile(0.5, value, metric = 'CGroupUserTimeNormalized')

-- 수정 후 (정상)
quantileIf(0.5)(value, metric = 'CGroupUserTimeNormalized')
```

### 2. 시간 범위 조정
```sql
-- RMV는 이전 시간(now() - 1 HOUR)의 데이터를 수집하도록 변경
WITH target_hour AS (
    SELECT toStartOfHour(now() - INTERVAL 1 HOUR) as h
)
```

### 3. Lag 윈도우 함수 개선
```sql
-- 25시간 범위의 데이터를 읽어 24시간 이전 데이터와 비교
WHERE r.hour >= (SELECT h - INTERVAL 25 HOUR FROM target_hour)
  AND r.hour <= (SELECT h FROM target_hour)
```

## 📊 모니터링

### RMV 상태 확인
```sql
SELECT 
    database,
    view,
    status,
    last_success_time,
    next_refresh_time,
    exception
FROM system.view_refreshes
WHERE database = 'billing_monitoring'
ORDER BY view;
```

**기대 결과:**
- `status`: 'Scheduled' 또는 'Running'
- `exception`: 비어있어야 함
- `last_success_time`: 최근 시간

### 데이터 수집 확인
```sql
-- 시간별 데이터 개수 확인
SELECT 
    toDate(hour) as date,
    count(*) as hourly_records
FROM billing_monitoring.hourly_raw_metrics
GROUP BY date
ORDER BY date DESC
LIMIT 7;
```

**기대 결과:** 하루당 24개 레코드

### 대시보드 확인
```sql
SELECT * FROM billing_monitoring.v_dashboard 
ORDER BY hour DESC 
LIMIT 5;
```

## 🚀 성능 최적화

### 인덱스 및 정렬 키
모든 테이블은 `(hour, service_name)` 또는 `(date, service_id)`로 정렬되어 있어 시간 기반 쿼리가 최적화되어 있습니다.

### TTL 정책
- `hourly_raw_metrics`: 365일 후 자동 삭제
- `hourly_cost_analysis`: 365일 후 자동 삭제
- `daily_billing`: 730일 후 자동 삭제
- `cost_alerts`: 90일 후 자동 삭제

## 🔒 데이터 보호

### 백업 테이블
`daily_billing_backup` 테이블이 존재하여 청구 데이터의 백업본을 유지합니다.

### 데이터 복구 전략
1. **자동 백필:** RMV가 실패하더라도 수동 INSERT로 과거 데이터 복구 가능
2. **백업 스크립트:** 주기적으로 중요 테이블을 백업 테이블에 복사
3. **모니터링:** system.view_refreshes를 통한 RMV 상태 모니터링

## 📝 주의사항

### RMV 수정 시
1. **테스트 환경에서 먼저 테스트:** 프로덕션에 적용하기 전에 반드시 테스트
2. **기존 데이터 백업:** DROP 전에 테이블 데이터를 백업
3. **타이밍 고려:** RMV 재생성 시 다음 refresh 시간까지 대기

### 데이터 무결성
- `hourly_cost_analysis`는 `hourly_raw_metrics`에 의존하므로, 순서대로 복구해야 함
- `daily_billing`은 외부 API에서 가져오므로, 하루에 한 번만 업데이트됨

### 알림 설정
- `alert_any = 1`인 경우 Slack/이메일로 알림을 보내도록 설정 권장
- CPU/비용이 20% 이상 변동 시 알림 발생

## 🆘 트러블슈팅

### Q: RMV가 실행되지만 데이터가 들어오지 않음
**A:** 
1. `system.view_refreshes`에서 exception 필드 확인
2. 쿼리를 직접 실행해서 결과가 나오는지 확인
3. `system.asynchronous_metric_log`에 데이터가 있는지 확인

### Q: 과거 데이터가 누락됨
**A:**
1. 복구 스크립트의 백필 섹션 실행
2. `system.asynchronous_metric_log`의 보존 기간 확인 (기본 8일)

### Q: 비용 데이터가 0으로 나옴
**A:**
1. `rmv_daily_billing`의 마지막 실행 시간 확인
2. ClickHouse Cloud API 연결 상태 확인
3. Authorization 토큰이 유효한지 확인

## 📚 추가 리소스

- [ClickHouse Refreshable Materialized Views 문서](https://clickhouse.com/docs/en/sql-reference/statements/create/view#refreshable-materialized-view)
- [Window Functions in ClickHouse](https://clickhouse.com/docs/en/sql-reference/window-functions)
- [ClickHouse Cloud API](https://clickhouse.com/docs/en/cloud/manage/openapi)

## 🤝 지원

문제가 지속되면 다음을 수집하여 지원팀에 문의:
1. `system.view_refreshes`의 전체 출력
2. `system.query_log`에서 실패한 쿼리
3. 데이터 손실이 발생한 정확한 시간대

---

**작성일:** 2025-12-06  
**버전:** 1.0  
**작성자:** Ken (ClickHouse Solution Architect)
