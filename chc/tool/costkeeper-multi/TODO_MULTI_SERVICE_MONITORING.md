# TODO: Multi-Service Monitoring

## Current Limitation

현재 CostKeeper는 **단일 서비스 모니터링**만 지원합니다:

- ✅ **Billing 데이터**: 모든 서비스 수집 (CHC API 사용)
- ❌ **Hourly Metrics**: 설정된 단일 서비스만 수집 (system.asynchronous_metric_log 제한)

### Why?

`system.asynchronous_metric_log`는 **현재 접속한 서비스의 메트릭만** 포함합니다.
다른 서비스의 메트릭을 수집하려면 해당 서비스에 직접 접속해야 합니다.

## Proposed Solution: remoteSecure Function

ClickHouse의 `remoteSecure()` 함수를 사용하여 여러 서비스에 접속하고 메트릭을 수집할 수 있습니다.

### Architecture Design

```
┌─────────────────────────────────────────────────────────────┐
│ Primary Service (Seoul)                                      │
│ - CostKeeper Database                                        │
│ - RMV collects local metrics                                │
│ - RMV collects remote metrics via remoteSecure()            │
│   ├─> remoteSecure('seoul-dev.clickhouse.cloud', ...)      │
│   ├─> remoteSecure('production.clickhouse.cloud', ...)     │
│   └─> remoteSecure('staging.clickhouse.cloud', ...)        │
└─────────────────────────────────────────────────────────────┘
```

### Implementation Plan

#### 1. Update Credentials File Structure

`.credentials` 파일에 여러 서비스 정보 저장:

```bash
# Primary Service (where CostKeeper runs)
CH_HOST=seoul.ap-northeast-2.aws.clickhouse.cloud
CH_PORT=8443
CH_USER=default
CH_PASSWORD=primary_password

# Additional Services (for remote monitoring)
CH_SERVICES=(
  "seoul-dev|seoul-dev.ap-northeast-2.aws.clickhouse.cloud|password1"
  "production|production.us-east-1.aws.clickhouse.cloud|password2"
  "staging|staging.eu-west-1.aws.clickhouse.cloud|password3"
)

# CHC API Configuration (unchanged)
CHC_ORG_ID=xxx
CHC_API_KEY_ID=xxx
CHC_API_KEY_SECRET=xxx
```

#### 2. Update setup-costkeeper.sh

서비스 선택 단계에서 멀티 서비스 모니터링 옵션 추가:

```bash
# Service selection logic
echo "모니터링 모드를 선택하세요:"
echo "  [1] 단일 서비스 모니터링 (현재 서비스만)"
echo "  [2] 멀티 서비스 모니터링 (remoteSecure 사용)"
prompt_input "선택 (1/2)" "1" MONITORING_MODE

if [ "$MONITORING_MODE" = "2" ]; then
    # Multi-service setup
    echo "모니터링할 추가 서비스 정보를 입력하세요..."
    # Loop to collect multiple service credentials
fi
```

#### 3. Update rmv_hourly_metrics Template

멀티 서비스 메트릭 수집을 위한 새로운 쿼리 구조:

```sql
CREATE MATERIALIZED VIEW ${DATABASE_NAME}.rmv_hourly_metrics
REFRESH EVERY 1 HOUR
TO ${DATABASE_NAME}.hourly_metrics
AS
WITH
    target_hour AS (
        SELECT toStartOfHour(now() - INTERVAL 1 HOUR) as h
    ),
    -- Local service metrics
    local_metrics AS (
        SELECT
            '${SERVICE_NAME}' AS service_name,
            (SELECT h FROM target_hour) as hour,
            -- CPU metrics
            avgIf(value, metric = 'CGroupUserTimeNormalized') +
            avgIf(value, metric = 'CGroupSystemTimeNormalized') as cpu_usage_avg,
            -- ... other metrics ...
        FROM system.asynchronous_metric_log
        WHERE event_time >= (SELECT h FROM target_hour)
          AND event_time < (SELECT h + INTERVAL 1 HOUR FROM target_hour)
    ),
    -- Remote service 1 metrics (Seoul-dev)
    remote_metrics_1 AS (
        SELECT
            'Seoul-dev' AS service_name,
            (SELECT h FROM target_hour) as hour,
            -- CPU metrics from remote service
            avgIf(value, metric = 'CGroupUserTimeNormalized') +
            avgIf(value, metric = 'CGroupSystemTimeNormalized') as cpu_usage_avg,
            -- ... other metrics ...
        FROM remoteSecure(
            '${REMOTE_SERVICE_1_HOST}:8443',
            'system.asynchronous_metric_log',
            '${REMOTE_SERVICE_1_USER}',
            '${REMOTE_SERVICE_1_PASSWORD}'
        )
        WHERE event_time >= (SELECT h FROM target_hour)
          AND event_time < (SELECT h + INTERVAL 1 HOUR FROM target_hour)
    ),
    -- Combine all services
    all_metrics AS (
        SELECT * FROM local_metrics
        UNION ALL
        SELECT * FROM remote_metrics_1
        -- UNION ALL for more remote services...
    ),
    -- Fetch specs for each service from API
    service_specs AS (
        SELECT
            JSONExtractString(service_data, 'id') AS service_id,
            JSONExtractString(service_data, 'name') AS service_name,
            JSONExtractFloat(service_data, 'maxTotalMemoryGb') AS allocated_memory_gb,
            JSONExtractFloat(service_data, 'maxTotalMemoryGb') / 4.0 AS allocated_cpu
        FROM (
            SELECT arrayJoin(
                JSONExtractArrayRaw(
                    json,
                    'result'
                )
            ) AS service_data
            FROM url(
                'https://api.clickhouse.cloud/v1/organizations/${CHC_ORG_ID}/services',
                'JSONAsString',
                'json String',
                headers('Authorization' = concat('Basic ', base64Encode('${CHC_API_KEY_ID}:${CHC_API_KEY_SECRET}')))
            )
        )
    )
SELECT
    m.hour,
    COALESCE(s.allocated_cpu, 0) AS allocated_cpu,
    COALESCE(s.allocated_memory_gb, 0) AS allocated_memory_gb,
    m.cpu_usage_avg,
    -- ... other metrics ...
    m.service_name
FROM all_metrics AS m
LEFT JOIN service_specs AS s ON m.service_name = s.service_name;
```

#### 4. Security Considerations

- ⚠️ 각 서비스의 비밀번호를 `.credentials` 파일에 저장해야 함
- ⚠️ remoteSecure 연결은 네트워크 트래픽 발생
- ⚠️ 각 서비스의 user가 system 테이블 읽기 권한 필요

#### 5. Performance Considerations

- remoteSecure는 매시간 모든 서비스에 접속하여 메트릭 조회
- 서비스가 많을수록 RMV refresh 시간이 길어짐
- 각 서비스당 약 1-2초 추가 소요 예상

### Alternative Approaches

#### Option A: Separate CostKeeper per Service
각 서비스마다 별도의 CostKeeper 설치
- 장점: 독립적 운영, 단순한 구조
- 단점: 통합 대시보드 불가, 관리 복잡도 증가

#### Option B: Central Collector Service
전용 수집 서비스 생성
- 장점: 명확한 책임 분리
- 단점: 추가 서비스 비용, 복잡한 설정

#### Option C: ClickHouse Cloud Platform Integration (Future)
CHC가 Organization 레벨에서 통합 메트릭 제공 시
- 장점: 간단하고 효율적
- 단점: CHC 기능 개선 필요 (현재 불가)

## Next Steps

1. [ ] remoteSecure 함수 프로토타입 테스트
2. [ ] setup-costkeeper.sh 멀티 서비스 모드 구현
3. [ ] .credentials 파일 구조 변경
4. [ ] costkeeper-template.sql 멀티 서비스 지원 추가
5. [ ] README.md 업데이트 (멀티 서비스 가이드)
6. [ ] 성능 테스트 (5개, 10개 서비스 시나리오)

## References

- [ClickHouse remoteSecure Function](https://clickhouse.com/docs/en/sql-reference/table-functions/remote)
- [system.asynchronous_metric_log](https://clickhouse.com/docs/en/operations/system-tables/asynchronous_metric_log)
- [CHC API Services Endpoint](https://clickhouse.com/docs/en/cloud/manage/api/services-api-reference)

---

**Status**: 📋 Planning Phase
**Priority**: Medium
**Estimated Effort**: 2-3 days
**Created**: 2025-12-06
