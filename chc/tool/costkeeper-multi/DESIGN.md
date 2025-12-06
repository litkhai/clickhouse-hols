# CostKeeper Multi-Service Monitoring Design

Version: 2.0-multi
Date: 2025-12-07

---

## Overview

CostKeeper Multi-Service는 단일 CostKeeper 인스턴스에서 같은 Organization 내 여러 ClickHouse Cloud 서비스를 동시에 모니터링할 수 있는 솔루션입니다.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│ Primary Service (CostKeeper 설치 위치)                              │
│ Host: primary.ap-northeast-2.aws.clickhouse.cloud                   │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │ Database: costkeeper                                           │ │
│  │                                                                │ │
│  │  ┌─────────────────────────────────────────────────────────┐  │ │
│  │  │ RMV 2: rmv_metrics_15min (EVERY 15 MIN)                 │  │ │
│  │  │                                                          │  │ │
│  │  │  ┌───────────────────────────────────────────────────┐  │  │ │
│  │  │  │ Local Metrics (Primary Service)                   │  │ │
│  │  │  │   SELECT FROM system.asynchronous_metric_log      │  │ │
│  │  │  └───────────────────────────────────────────────────┘  │  │ │
│  │  │                                                          │  │ │
│  │  │  ┌───────────────────────────────────────────────────┐  │  │ │
│  │  │  │ Remote Metrics (Service 1: Seoul-dev)             │  │ │
│  │  │  │   SELECT FROM remoteSecure(                       │  │ │
│  │  │  │     'seoul-dev.clickhouse.cloud:8443',            │  │ │
│  │  │  │     'system.asynchronous_metric_log',             │  │ │
│  │  │  │     'default', 'password'                         │  │ │
│  │  │  │   )                                               │  │ │
│  │  │  └───────────────────────────────────────────────────┘  │  │ │
│  │  │                                                          │  │ │
│  │  │  ┌───────────────────────────────────────────────────┐  │  │ │
│  │  │  │ Remote Metrics (Service 2: Tokyo)                 │  │ │
│  │  │  │   SELECT FROM remoteSecure(                       │  │ │
│  │  │  │     'tokyo.clickhouse.cloud:8443',                │  │ │
│  │  │  │     'system.asynchronous_metric_log',             │  │ │
│  │  │  │     'default', 'password'                         │  │ │
│  │  │  │   )                                               │  │ │
│  │  │  └───────────────────────────────────────────────────┘  │  │ │
│  │  │                                                          │  │ │
│  │  │  UNION ALL → metrics_15min (service_name별 구분)      │  │ │
│  │  └─────────────────────────────────────────────────────────┘  │ │
│  │                                                                │ │
│  │  RMV 3: rmv_hourly_metrics (EVERY 1 HOUR +2m)                 │ │
│  │    → hourly_metrics (service_name별 집계)                      │ │
│  │                                                                │ │
│  │  RMV 4: rmv_hourly_analysis (EVERY 1 HOUR +5m)                │ │
│  │    → hourly_analysis (service_name별 분석)                     │ │
│  └───────────────────────────────────────────────────────────────┘ │
│                                                                     │
│  CHC API (Organization-wide billing)                                │
│    → daily_billing (모든 서비스 비용)                               │
└─────────────────────────────────────────────────────────────────────┘
```

## Key Design Decisions

### 1. remoteSecure() 사용

**장점:**
- 각 서비스에 CostKeeper를 설치할 필요 없음
- 중앙 집중식 모니터링
- 통합 대시보드 구성 가능

**단점:**
- 매 15분마다 모든 서비스에 원격 접속 (네트워크 트래픽)
- 각 서비스의 credential 필요
- RMV refresh 시간 증가 (서비스당 ~1-2초)

**대안 검토:**
- ❌ 각 서비스에 개별 CostKeeper 설치: 통합 대시보드 불가
- ❌ Kafka/외부 큐 사용: CHC 네이티브 아님
- ✅ remoteSecure(): CHC 네이티브 기능, 간단한 구현

### 2. Organization 단일 지원

**제한사항:**
- ✅ 같은 Organization 내 서비스만 모니터링
- ❌ 다른 Organization 서비스는 지원 안 함

**이유:**
- CHC API는 Organization 단위로 동작
- 다른 Organization의 billing 데이터는 별도 API key 필요
- 복잡도 증가 대비 실용성 낮음

### 3. Service Name vs Service ID

**service_name 사용:**
- 사용자 친화적 (예: "Seoul-production", "Tokyo-staging")
- Dashboard에서 읽기 쉬움
- CHC Console 이름과 일치

**service_id는 metadata로 보관:**
- UUID 형태 (예: c5ccc996-e105-4f61...)
- API 조회 시 필요
- 테이블에 별도 컬럼으로 저장

## Data Flow

### 15분 단위 메트릭 수집 (RMV 2)

```sql
-- 1. Local service metrics
local_metrics AS (
    SELECT
        '${PRIMARY_SERVICE_NAME}' as service_name,
        toStartOfFifteenMinutes(now()) as collected_at,
        avgIf(value, metric='CGroupMaxCPU') as allocated_cpu,
        ...
    FROM system.asynchronous_metric_log
    WHERE event_time >= now() - INTERVAL 15 MINUTE
)

-- 2. Remote service 1 metrics
remote_metrics_service1 AS (
    SELECT
        '${REMOTE_SERVICE_1_NAME}' as service_name,
        toStartOfFifteenMinutes(now()) as collected_at,
        avgIf(value, metric='CGroupMaxCPU') as allocated_cpu,
        ...
    FROM remoteSecure(
        '${REMOTE_SERVICE_1_HOST}:8443',
        'system.asynchronous_metric_log',
        '${REMOTE_SERVICE_1_USER}',
        '${REMOTE_SERVICE_1_PASSWORD}'
    )
    WHERE event_time >= now() - INTERVAL 15 MINUTE
)

-- 3. Combine all services
all_metrics AS (
    SELECT * FROM local_metrics
    UNION ALL
    SELECT * FROM remote_metrics_service1
    UNION ALL
    SELECT * FROM remote_metrics_service2
    ...
)

-- 4. Insert into metrics_15min
SELECT * FROM all_metrics
```

### 시간별 집계 (RMV 3)

```sql
-- 각 service_name별로 4개 15분 데이터 집계
SELECT
    toStartOfHour(now() - INTERVAL 1 HOUR) as hour,
    service_name,
    avg(allocated_cpu) as allocated_cpu,
    avg(cpu_usage_avg) as cpu_usage_avg,
    ...
FROM metrics_15min
WHERE collected_at >= toStartOfHour(now() - INTERVAL 1 HOUR)
  AND collected_at < toStartOfHour(now())
GROUP BY service_name
```

### 비용 분석 (RMV 4)

```sql
-- service_name별로 daily_billing과 JOIN
SELECT
    m.hour,
    m.service_name,
    m.allocated_cpu,
    m.cpu_usage_avg,
    COALESCE(d.total_chc, 0) as daily_total_chc,
    (d.total_chc / 24) as estimated_hourly_total_chc,
    ...
FROM hourly_metrics m
LEFT JOIN daily_billing d
    ON toDate(m.hour) = d.date
    AND m.service_name = d.service_name
WHERE m.hour = toStartOfHour(now() - INTERVAL 1 HOUR)
```

## Credentials Structure

### .credentials 파일 형식

```bash
# ============================================================================
# CostKeeper Multi-Service Credentials
# ============================================================================

# Primary Service (CostKeeper 설치 위치)
CH_HOST=primary.ap-northeast-2.aws.clickhouse.cloud
CH_PORT=8443
CH_USER=default
CH_PASSWORD=primary_password

# CHC API Configuration (Organization-wide)
CHC_ORG_ID=<YOUR_ORG_ID>
CHC_API_KEY_ID=<YOUR_API_KEY_ID>
CHC_API_KEY_SECRET=<YOUR_API_KEY_SECRET>

# Monitoring Mode
MONITORING_MODE=multi  # 'single' or 'multi'

# Monitored Services (콤마로 구분)
# Format: name|host|user|password
CH_MONITORED_SERVICES=(
  "Primary|primary.ap-northeast-2.aws.clickhouse.cloud|default|primary_password"
  "Seoul-dev|seoul-dev.ap-northeast-2.aws.clickhouse.cloud|default|seoul_dev_password"
  "Tokyo|tokyo.ap-northeast-1.aws.clickhouse.cloud|default|tokyo_password"
)
```

### SQL Template 변수 생성

setup 스크립트에서 다음 변수 생성:

```bash
# Service 1 (Primary - local)
SERVICE_1_NAME="Primary"
SERVICE_1_HOST="primary.ap-northeast-2.aws.clickhouse.cloud"
SERVICE_1_USER="default"
SERVICE_1_PASSWORD="xxx"
SERVICE_1_IS_LOCAL="true"

# Service 2 (Remote)
SERVICE_2_NAME="Seoul-dev"
SERVICE_2_HOST="seoul-dev.ap-northeast-2.aws.clickhouse.cloud"
SERVICE_2_USER="default"
SERVICE_2_PASSWORD="xxx"
SERVICE_2_IS_LOCAL="false"

# Service 3 (Remote)
SERVICE_3_NAME="Tokyo"
...
```

## SQL Template Structure

### metrics_15min 수집 쿼리 생성

setup 스크립트가 동적으로 CTE 생성:

```bash
# Generate metrics collection CTE for each service
for i in "${!CH_MONITORED_SERVICES[@]}"; do
  IFS='|' read -r name host user password <<< "${CH_MONITORED_SERVICES[$i]}"

  if [ "$host" = "$CH_HOST" ]; then
    # Local service
    cat >> sql_template << EOF
    service_${i}_metrics AS (
        SELECT
            '${name}' as service_name,
            toStartOfFifteenMinutes(now()) as collected_at,
            avgIf(value, metric = 'CGroupMaxCPU') as allocated_cpu,
            ...
        FROM system.asynchronous_metric_log
        WHERE event_time >= now() - INTERVAL 15 MINUTE
    ),
EOF
  else
    # Remote service
    cat >> sql_template << EOF
    service_${i}_metrics AS (
        SELECT
            '${name}' as service_name,
            toStartOfFifteenMinutes(now()) as collected_at,
            avgIf(value, metric = 'CGroupMaxCPU') as allocated_cpu,
            ...
        FROM remoteSecure(
            '${host}:8443',
            'system.asynchronous_metric_log',
            '${user}',
            '${password}'
        )
        WHERE event_time >= now() - INTERVAL 15 MINUTE
    ),
EOF
  fi
done

# Combine all services
cat >> sql_template << EOF
all_metrics AS (
    SELECT * FROM service_0_metrics
    UNION ALL
    SELECT * FROM service_1_metrics
    UNION ALL
    SELECT * FROM service_2_metrics
    ...
)
EOF
```

## Performance Considerations

### RMV Execution Time

**단일 서비스 (기존):**
- system.asynchronous_metric_log 조회: ~0.5초
- 집계 계산: ~0.3초
- 총 실행 시간: ~1초

**멀티 서비스 (신규):**
- Local 조회: ~0.5초
- Remote 조회 (서비스당): ~1-2초
- 5개 서비스: ~6-11초
- 10개 서비스: ~11-21초

**제한사항:**
- RMV timeout (default: 10분)
- 안전한 최대 서비스 수: ~20개
- 권장 서비스 수: 5-10개

### Network Traffic

**15분마다 (RMV 2):**
- 서비스당 데이터 크기: ~100-500 rows (system.asynchronous_metric_log)
- 네트워크 전송량: 서비스당 ~10-50KB
- 5개 서비스: ~50-250KB/15분

**1시간당:**
- 총 네트워크 사용량: ~200KB-1MB (5개 서비스 기준)
- 무시할 수 있는 수준

## Security

### Credential Management

**저장 위치:**
- `.credentials` 파일 (권한: 600)
- Git에서 제외 (`.gitignore`)

**보안 고려사항:**
- ⚠️ 모든 서비스의 비밀번호를 한 곳에 저장
- ⚠️ Primary 서비스가 침해되면 모든 서비스 접근 가능
- ✅ read-only user 사용 권장 (system 테이블만 조회)

### Network Security

- remoteSecure()는 TLS 암호화 사용
- Port 8443 (HTTPS)
- ClickHouse Cloud 간 통신은 AWS/GCP private network 사용

## Migration from Single to Multi

### 기존 Single-Service CostKeeper

```bash
# 1. 백업
cp -r costkeeper costkeeper-backup

# 2. costkeeper-multi로 전환
cd costkeeper-multi
./setup-costkeeper-multi.sh

# 3. 기존 데이터 마이그레이션 (optional)
# - hourly_analysis, alerts 테이블을 새 DB로 복사
# - service_name 컬럼 추가 및 업데이트
```

## Limitations

### 현재 버전

- ✅ 같은 Organization 내 서비스만 지원
- ✅ 최대 20개 서비스 (권장: 5-10개)
- ✅ 모든 서비스가 같은 region일 필요 없음
- ❌ 다른 Organization 서비스는 미지원
- ❌ On-premise ClickHouse 미지원 (CHC only)

### Future Enhancements

1. **Auto-discovery**: API에서 Organization의 모든 서비스 자동 검색
2. **Dynamic Service Addition**: RMV 재생성 없이 서비스 추가/제거
3. **Per-Service Configuration**: 각 서비스별 Alert 임계값 설정
4. **Cross-Organization Support**: 여러 Organization 통합 모니터링

## Testing Plan

### Unit Tests

1. remoteSecure() 연결 테스트
2. 각 서비스별 메트릭 수집 검증
3. UNION ALL 결과 정합성 확인

### Integration Tests

1. 2개 서비스 모니터링 (최소)
2. 5개 서비스 모니터링 (권장)
3. 10개 서비스 모니터링 (최대)

### Performance Tests

1. RMV execution time 측정
2. Network bandwidth 측정
3. Resource usage (CPU, Memory) 모니터링

---

**Status**: 🚧 In Development
**Version**: 2.0-multi
**Last Updated**: 2025-12-07
