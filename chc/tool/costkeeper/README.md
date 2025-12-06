# CostKeeper

**ClickHouse Cloud Cost Monitoring & Alerting System**

Version 1.0 | Last Updated: 2025-12-06

---

## 📋 목차

- [소개](#소개)
- [주요 기능](#주요-기능)
- [시스템 아키텍처](#시스템-아키텍처)
- [빠른 시작](#빠른-시작)
- [설치 가이드](#설치-가이드)
- [사용 가이드](#사용-가이드)
- [외부 시스템 연동](#외부-시스템-연동)
- [고급 설정](#고급-설정)
- [문제 해결](#문제-해결)
- [FAQ](#faq)

---

## 소개

**CostKeeper**는 ClickHouse Cloud의 비용과 리소스 사용량을 실시간으로 모니터링하고, 이상 징후 발생 시 자동으로 Alert를 생성하는 시스템입니다.

### 핵심 특징

✅ **100% ClickHouse Cloud 네이티브**
- Refreshable Materialized View (RMV) 기반 자동 갱신
- 외부 스케줄러나 cronjob 불필요
- TTL 정책을 통한 자동 데이터 관리

✅ **실시간 비용 모니터링**
- 시간별 CPU, 메모리, 스토리지, 네트워크 비용 추적
- 리소스 효율성 분석 및 낭비 비용 식별
- 1시간, 3시간, 24시간 전 대비 변화율 계산

✅ **자동 Alert 시스템**
- INFO, WARNING, CRITICAL 3단계 심각도 분류
- 임계값 기반 자동 Alert 생성
- 외부 시스템 연동을 위한 API 제공

---

## 주요 기능

### 1. 자동화된 비용 분석

- **시간별 메트릭 수집**: system.asynchronous_metric_log에서 CPU/메모리 사용량 자동 수집
- **비용 분석**: Cloud API 데이터와 메트릭을 결합하여 시간별 비용 계산
- **효율성 지표**: 할당 리소스 대비 실제 사용률 분석
- **낭비 비용 식별**: 미사용 리소스에 대한 비용 계산

### 2. 실시간 Alert 생성

- **다중 비교 기준**: 1h, 3h, 24h 전 대비 변화 감지
- **자동 심각도 분류**:
  - INFO: 20-30% 변화
  - WARNING: 30-50% 변화
  - CRITICAL: 50% 이상 변화
- **상세 Alert 메시지**: 변화율, 예상 비용 영향 포함

### 3. 대시보드 및 리포팅

- **실시간 대시보드**: 비용, 효율성, Alert 현황 조회
- **히스토리 분석**: 과거 데이터 기반 트렌드 분석
- **커스텀 View**: 다양한 관점의 데이터 조회

---

## 시스템 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│                         CostKeeper                              │
│          ClickHouse Cloud Native Cost Monitoring                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐     ┌─────────────────┐                   │
│  │  Cloud API      │     │  System Metrics │                   │
│  │  (Billing)      │     │  (CPU/Memory)   │                   │
│  └────────┬────────┘     └────────┬────────┘                   │
│           │                       │                             │
│           ▼                       ▼                             │
│  ┌─────────────────┐     ┌─────────────────┐                   │
│  │ daily_billing   │     │ hourly_metrics  │                   │
│  │ [RMV 매일]      │     │ [RMV 매시간]    │                   │
│  └────────┬────────┘     └────────┬────────┘                   │
│           │                       │                             │
│           └───────────┬───────────┘                             │
│                       ▼                                         │
│           ┌─────────────────────────┐                           │
│           │ rmv_hourly_analysis     │                           │
│           │ [RMV 매시간 +5분]       │                           │
│           │ • lagInFrame 기반       │                           │
│           │ • 1h/3h/24h 비교        │                           │
│           │ • Alert 플래그 계산     │                           │
│           └────────┬────────────────┘                           │
│                    ▼                                            │
│           ┌─────────────────────────┐                           │
│           │ hourly_analysis         │                           │
│           │ • 비용 분석             │                           │
│           │ • 효율성 지표           │                           │
│           │ • 변화율 계산           │                           │
│           └────────┬────────────────┘                           │
│                    │                                            │
│           ┌────────▼────────────────┐                           │
│           │ mv_alerts               │                           │
│           │ [Standard MV]           │                           │
│           │ WHERE alert_any = 1     │                           │
│           └────────┬────────────────┘                           │
│                    ▼                                            │
│           ┌─────────────────────────┐                           │
│           │ alerts                  │                           │
│           │ • severity 분류         │    External Systems       │
│           │ • message 생성          │◄──── (Polling)            │
│           │ • acknowledged 관리     │    Slack, PagerDuty, etc  │
│           └─────────────────────────┘                           │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Dashboard Views                      │   │
│  │  • v_dashboard: 실시간 비용 및 효율성                   │   │
│  │  • v_alerts: 최근 Alert 조회                            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 데이터 레이어

| Layer | 테이블/뷰 | 설명 | 갱신 주기 |
|-------|----------|------|----------|
| Layer 0 | `daily_billing` | Cloud API 일별 비용 데이터 | 매일 |
| Layer 1 | `hourly_metrics` | 시간별 시스템 메트릭 | 매시간 |
| Layer 2 | `hourly_analysis` | 시간별 비용 분석 및 Alert 플래그 | 매시간 +5분 |
| Layer 3 | `alerts` | 생성된 Alert 저장 | 실시간 (MV) |

---

## 빠른 시작

### 전제 조건

- **ClickHouse Cloud 인스턴스** (CHC 전용)
- **ClickHouse Cloud API Key** (Billing 데이터 수집용)
- `clickhouse-client` CLI 도구 설치
- Database 생성 및 테이블 관리 권한

### 설치 (3분 소요)

```bash
cd /path/to/clickhouse-hols/chc/tool/costkeeper
./setup-costkeeper.sh
```

**대화형 프롬프트에서 입력할 정보:**

1. **CHC 연결 정보**
   - CHC 호스트 (예: abc123.us-east-1.aws.clickhouse.cloud)
   - CHC 비밀번호 (숨김 입력)
   - ⚙️ 포트(8443), 사용자(default)는 자동 설정됨

2. **CHC API 정보**
   - Organization ID
   - API Key ID
   - API Key Secret (숨김 입력)

3. **서비스 설정** (기존 설정 파일이 있으면 재사용 가능)
   - Database 이름 (기본값: costkeeper)
   - 서비스 이름, CPU/메모리 할당량

4. **Alert 및 보관 기간 설정**

> ⚠️ **보안**: 민감한 정보(비밀번호, API Key)는 `.credentials` 파일에 안전하게 저장됩니다 (권한: 600)
>
> 💡 **Tip**: 기존 `.credentials`나 `costkeeper.conf` 파일이 있으면 재사용 여부를 물어봅니다

### 확인

```sql
-- Dashboard 확인
SELECT * FROM costkeeper.v_dashboard LIMIT 10;

-- Alert 확인
SELECT * FROM costkeeper.v_alerts LIMIT 10;

-- RMV 상태 확인
SELECT * FROM system.view_refreshes WHERE database = 'costkeeper';
```

---

## 설치 가이드

### 대화형 설치 (권장)

```bash
./setup-costkeeper.sh
```

**입력 정보:**

1. **CHC 연결 설정** (CHC 전용, Secure 연결 고정)
   - CHC 호스트 (예: abc123.us-east-1.aws.clickhouse.cloud)
   - CHC 비밀번호 (숨김 입력) 🔒
   - ⚙️ 포트(8443), 사용자(default)는 자동 설정됨 (CHC 표준)

2. **CHC API 설정**
   - Organization ID (CHC Console에서 확인)
   - API Key ID (CHC Console에서 발급)
   - API Key Secret (숨김 입력) 🔒

3. **서비스 설정**
   - Database 이름 (기본값: `costkeeper`)
   - 서비스 이름 (예: production, development)
   - 할당된 CPU 코어 수
   - 할당된 메모리 (GB)

4. **Alert 설정**
   - Alert 임계값 (%) - 기본값: 20%
   - Warning 임계값 (%) - 기본값: 30%
   - Critical 임계값 (%) - 기본값: 50%

5. **데이터 보관 설정**
   - 분석 데이터 보관 기간 (일) - 기본값: 365일
   - Alert 데이터 보관 기간 (일) - 기본값: 90일

### 보안 관련

**생성되는 파일:**

| 파일 | 권한 | 내용 | Git |
|------|------|------|-----|
| `.credentials` | 600 (소유자만 읽기/쓰기) | CHC 비밀번호, API Key ID/Secret | ❌ 제외 |
| `costkeeper.conf` | 644 (일반 읽기) | 비민감 설정 | ❌ 제외 |
| `.gitignore` | 644 | Git 제외 파일 목록 | ✅ 포함 |

**보안 체크리스트:**

- ✅ `.credentials` 파일은 자동으로 권한 600 설정
- ✅ `.gitignore`에 자동 추가되어 Git 커밋 방지
- ✅ 비밀번호와 API Key Secret은 터미널에 표시되지 않음
- ⚠️ `.credentials` 파일을 절대 공유하지 마세요
- ⚠️ 프로덕션 환경에서는 환경 변수 사용 권장

### 수동 설치

#### 1. 인증 정보 파일 생성

`.credentials` 파일을 생성 (민감 정보):

```bash
# ClickHouse Cloud Connection
CH_HOST=abc123.us-east-1.aws.clickhouse.cloud
CH_PORT=8443
CH_USER=default
CH_PASSWORD=your_chc_password

# CHC API Configuration
CHC_ORG_ID=your_org_id
CHC_API_KEY_ID=your_api_key_id
CHC_API_KEY_SECRET=your_api_key_secret
```

**보안 설정:**
```bash
chmod 600 .credentials
```

#### 2. 설정 파일 생성

`costkeeper.conf` 파일을 생성 (비민감 정보):

```bash
# Database Configuration
DATABASE_NAME=costkeeper

# Service Configuration
SERVICE_NAME=production
ALLOCATED_CPU=2.0
ALLOCATED_MEMORY=8.0

# Alert Configuration
ALERT_THRESHOLD_PCT=20.0
WARNING_THRESHOLD_PCT=30.0
CRITICAL_THRESHOLD_PCT=50.0

# Data Retention Configuration
DATA_RETENTION_DAYS=365
ALERT_RETENTION_DAYS=90

# Connection Settings (CHC Exclusive)
CH_SECURE=true
CH_PORT=8443
```

#### 3. SQL 스크립트 생성

```bash
source .credentials
source costkeeper.conf

sed -e "s/\${DATABASE_NAME}/${DATABASE_NAME}/g" \
    -e "s/\${SERVICE_NAME}/${SERVICE_NAME}/g" \
    -e "s/\${ALLOCATED_CPU}/${ALLOCATED_CPU}/g" \
    -e "s/\${ALLOCATED_MEMORY}/${ALLOCATED_MEMORY}/g" \
    -e "s/\${ALERT_THRESHOLD_PCT}/${ALERT_THRESHOLD_PCT}/g" \
    -e "s/\${WARNING_THRESHOLD_PCT}/${WARNING_THRESHOLD_PCT}/g" \
    -e "s/\${CRITICAL_THRESHOLD_PCT}/${CRITICAL_THRESHOLD_PCT}/g" \
    -e "s/\${DATA_RETENTION_DAYS}/${DATA_RETENTION_DAYS}/g" \
    -e "s/\${ALERT_RETENTION_DAYS}/${ALERT_RETENTION_DAYS}/g" \
    costkeeper-template.sql > costkeeper-setup.sql
```

#### 4. SQL 실행

```bash
source .credentials

clickhouse-client \
  --host=${CH_HOST} \
  --port=${CH_PORT} \
  --user=${CH_USER} \
  --password=${CH_PASSWORD} \
  --secure \
  --multiquery < costkeeper-setup.sql
```

> 💡 **Tip**: `.credentials` 파일을 source하여 환경 변수로 로드합니다.

---

## 사용 가이드

### Dashboard 조회

```sql
-- 최근 20시간 비용 및 효율성 현황
SELECT
    hour,
    service_name,
    daily_chc,
    hourly_chc,
    cpu_cores,
    cpu_eff_pct,
    waste_hourly_chc,
    alert_trigger
FROM costkeeper.v_dashboard
LIMIT 20;
```

**컬럼 설명:**
- `daily_chc`: 일일 총 비용 (CHC)
- `hourly_chc`: 시간당 예상 비용
- `cpu_cores`: 평균 CPU 코어 사용량
- `cpu_eff_pct`: CPU 효율성 (%)
- `waste_hourly_chc`: 시간당 낭비 비용
- `alert_trigger`: Alert 발생 원인 (1h/3h/24h)

### Alert 조회

```sql
-- 미확인 Alert 조회
SELECT
    alert_time,
    severity,
    alert_type,
    message,
    daily_impact_chc
FROM costkeeper.v_alerts
WHERE acknowledged = 0
ORDER BY alert_time DESC;
```

### 비용 트렌드 분석

```sql
-- 최근 7일간 일별 비용 및 효율성
SELECT
    toDate(hour) as date,
    round(avg(estimated_hourly_total_chc * 24), 2) as avg_daily_cost,
    round(avg(cpu_efficiency_pct), 1) as avg_cpu_eff,
    round(avg(memory_efficiency_pct), 1) as avg_mem_eff,
    round(sum(unused_compute_cost_hourly), 2) as total_waste_hourly
FROM costkeeper.hourly_analysis
WHERE hour >= now() - INTERVAL 7 DAY
GROUP BY date
ORDER BY date DESC;
```

### Alert 통계

```sql
-- 최근 30일 Alert 통계
SELECT
    severity,
    alert_type,
    count(*) as alert_count,
    round(avg(pct_change), 1) as avg_change_pct,
    round(sum(potential_daily_impact_chc), 2) as total_impact
FROM costkeeper.alerts
WHERE alert_time >= now() - INTERVAL 30 DAY
GROUP BY severity, alert_type
ORDER BY alert_count DESC;
```

### RMV 상태 확인

```sql
-- Refreshable Materialized View 상태
SELECT
    view,
    status,
    last_success_time,
    next_refresh_time,
    exception
FROM system.view_refreshes
WHERE database = 'costkeeper'
ORDER BY view;
```

---

## 외부 시스템 연동

CostKeeper는 외부 시스템과의 연동을 위해 polling 방식을 권장합니다.

### Slack 연동 예시

```bash
#!/bin/bash
# check-alerts.sh

WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

# Query unacknowledged alerts
ALERTS=$(clickhouse-client --host=your-host --secure \
  --query="SELECT message, alert_id FROM costkeeper.alerts \
  WHERE acknowledged = 0 AND alert_time >= now() - INTERVAL 5 MINUTE \
  FORMAT JSONEachRow")

# Send to Slack
echo "$ALERTS" | while read -r alert; do
  MESSAGE=$(echo "$alert" | jq -r '.message')
  ALERT_ID=$(echo "$alert" | jq -r '.alert_id')

  curl -X POST "$WEBHOOK_URL" \
    -H 'Content-Type: application/json' \
    -d "{\"text\": \"$MESSAGE\"}"

  # Mark as acknowledged
  clickhouse-client --host=your-host --secure \
    --query="ALTER TABLE costkeeper.alerts \
    UPDATE acknowledged = 1, acknowledged_at = now64(3) \
    WHERE alert_id = '$ALERT_ID'"
done
```

**실행:**
```bash
chmod +x check-alerts.sh
# 매 5분마다 실행 (외부 스케줄러 사용)
```

### PagerDuty 연동 예시

```python
#!/usr/bin/env python3
# send_to_pagerduty.py

import requests
import json
from clickhouse_driver import Client

# ClickHouse connection
client = Client(host='your-host', secure=True, user='default', password='your-password')

# PagerDuty configuration
PAGERDUTY_API_KEY = "your-api-key"
PAGERDUTY_ROUTING_KEY = "your-routing-key"

# Query unacknowledged alerts
query = """
SELECT alert_id, severity, message, potential_daily_impact_chc
FROM costkeeper.alerts
WHERE acknowledged = 0 AND alert_time >= now() - INTERVAL 5 MINUTE
"""

alerts = client.execute(query)

for alert in alerts:
    alert_id, severity, message, impact = alert

    # Send to PagerDuty
    payload = {
        "routing_key": PAGERDUTY_ROUTING_KEY,
        "event_action": "trigger",
        "payload": {
            "summary": message,
            "severity": severity,
            "custom_details": {
                "daily_impact": f"${impact:.2f}"
            }
        }
    }

    response = requests.post(
        "https://events.pagerduty.com/v2/enqueue",
        json=payload,
        headers={"Content-Type": "application/json"}
    )

    if response.status_code == 202:
        # Mark as acknowledged
        client.execute(f"""
            ALTER TABLE costkeeper.alerts
            UPDATE acknowledged = 1, acknowledged_at = now64(3)
            WHERE alert_id = '{alert_id}'
        """)
```

---

## 고급 설정

### Alert 임계값 조정

설치 후 임계값을 변경하려면 테이블을 재생성해야 합니다:

```sql
-- 새로운 임계값으로 설정 파일 수정 후
-- setup-costkeeper.sh 재실행
```

### 다중 서비스 모니터링

여러 서비스를 모니터링하려면 각 서비스별로 별도 RMV를 생성:

```sql
-- Tokyo 서비스 모니터링 추가
CREATE MATERIALIZED VIEW costkeeper.rmv_hourly_metrics_tokyo
REFRESH EVERY 1 HOUR
TO costkeeper.hourly_metrics
AS
-- ... (SERVICE_NAME을 'Tokyo'로 변경)
```

### 커스텀 메트릭 추가

`hourly_metrics` 테이블에 컬럼을 추가하여 커스텀 메트릭 수집 가능:

```sql
ALTER TABLE costkeeper.hourly_metrics
ADD COLUMN custom_metric Float64;
```

### TTL 정책 변경

데이터 보관 기간을 변경하려면:

```sql
-- Analysis 데이터 보관 기간 변경 (180일)
ALTER TABLE costkeeper.hourly_analysis
MODIFY TTL hour + INTERVAL 180 DAY;

-- Alert 데이터 보관 기간 변경 (30일)
ALTER TABLE costkeeper.alerts
MODIFY TTL alert_time + INTERVAL 30 DAY;
```

---

## 문제 해결

### RMV가 실행되지 않음

```sql
-- RMV 상태 확인
SELECT view, status, exception
FROM system.view_refreshes
WHERE database = 'costkeeper' AND status != 'Scheduled';

-- RMV 수동 Refresh
SYSTEM REFRESH VIEW costkeeper.rmv_hourly_metrics;
SYSTEM REFRESH VIEW costkeeper.rmv_hourly_analysis;
```

### Alert가 생성되지 않음

```sql
-- Alert 플래그 확인
SELECT hour, alert_any, alert_cpu_spike_1h, alert_cost_spike_1h
FROM costkeeper.hourly_analysis
WHERE hour >= now() - INTERVAL 24 HOUR
ORDER BY hour DESC
LIMIT 20;

-- mv_alerts 동작 확인
SELECT count(*) FROM costkeeper.alerts
WHERE alert_time >= now() - INTERVAL 1 HOUR;
```

### 데이터가 수집되지 않음

```sql
-- hourly_metrics 데이터 확인
SELECT count(*), min(hour), max(hour)
FROM costkeeper.hourly_metrics;

-- system.asynchronous_metric_log 확인
SELECT count(*) FROM system.asynchronous_metric_log
WHERE event_time >= now() - INTERVAL 1 HOUR;
```

### 성능 이슈

```sql
-- 테이블 크기 확인
SELECT
    table,
    formatReadableSize(sum(bytes)) as size,
    sum(rows) as rows
FROM system.parts
WHERE database = 'costkeeper' AND active
GROUP BY table;

-- OPTIMIZE 실행 (병합)
OPTIMIZE TABLE costkeeper.hourly_analysis FINAL;
```

---

## FAQ

### Q: CostKeeper는 어떤 ClickHouse 버전에서 동작하나요?

**A:** ClickHouse 22.8 이상에서 동작합니다. Refreshable Materialized View는 ClickHouse Cloud와 23.2 이상에서 사용 가능합니다.

### Q: cronjob 없이 어떻게 자동으로 실행되나요?

**A:** ClickHouse의 Refreshable Materialized View (RMV) 기능을 사용합니다. RMV는 ClickHouse 내부 스케줄러에 의해 자동으로 실행됩니다.

### Q: 외부 알림은 어떻게 받을 수 있나요?

**A:** `costkeeper.alerts` 테이블을 주기적으로 polling하여 외부 시스템(Slack, PagerDuty 등)으로 전송할 수 있습니다. 예제 스크립트를 참조하세요.

### Q: 여러 서비스를 동시에 모니터링할 수 있나요?

**A:** 가능합니다. 각 서비스별로 별도의 RMV를 생성하거나, `service_name` 컬럼을 활용하여 구분할 수 있습니다.

### Q: 비용 데이터는 어디서 가져오나요?

**A:** `daily_billing` 테이블에서 가져옵니다. 이 테이블은 ClickHouse Cloud API에서 수집한 일별 비용 데이터를 저장합니다.

### Q: Alert 임계값을 변경하려면?

**A:** 설정 파일을 수정한 후 `setup-costkeeper.sh`를 재실행하여 테이블과 뷰를 재생성해야 합니다.

### Q: 데이터 보관 비용이 걱정됩니다.

**A:** TTL 정책이 자동으로 오래된 데이터를 삭제합니다. 기본적으로 분석 데이터는 365일, Alert는 90일 보관됩니다.

### Q: 실시간 모니터링이 가능한가요?

**A:** RMV는 매 시간 실행되므로 최대 1시간의 지연이 있습니다. 더 빠른 갱신이 필요한 경우 RMV 주기를 조정할 수 있습니다 (예: 15분).

---

## 기술 스택

- **Database**: ClickHouse Cloud (또는 ClickHouse 22.8+)
- **Table Engine**: SharedReplacingMergeTree, SharedMergeTree
- **Automation**: Refreshable Materialized View (RMV)
- **Data Management**: TTL (Time To Live) 정책
- **Window Functions**: lagInFrame (이전 시간대 비교)

---

## 프로젝트 구조

```
costkeeper/
├── README.md                    # 이 파일
├── setup-costkeeper.sh          # 대화형 설정 스크립트
├── costkeeper-template.sql      # SQL 템플릿 (변수 포함)
├── costkeeper.conf              # 설정 파일 (생성됨)
└── costkeeper-setup.sql         # 실행용 SQL 스크립트 (생성됨)
```

---

## 라이센스

이 프로젝트는 ClickHouse Cloud 사용자를 위해 제공됩니다.

---

## 지원 및 기여

문의사항이나 버그 리포트는 이슈 트래커에 등록해 주세요.

---

**CostKeeper** - Keep your ClickHouse Cloud costs under control! 💰

Version 1.0 | Last Updated: 2025-12-06
