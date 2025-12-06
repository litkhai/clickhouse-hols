# Customer 360 Lab with ClickHouse
# ClickHouse Customer 360 실습

## Overview / 개요

This lab demonstrates large-scale Customer 360 analytics using ClickHouse.

이 실습은 ClickHouse를 활용한 대규모 고객 360도 분석을 시연합니다.

**Dataset Scale / 데이터셋 규모**:
- Customers / 고객: 30M (3천만)
- Transactions / 거래: 500M (5억)
- Events / 이벤트: 200M (2억)
- Support Tickets / 서포트 티켓: 5M (5백만)
- Campaign Responses / 캠페인 응답: 100M (1억)
- Product Reviews / 제품 리뷰: 10M (1천만)
- **Total Records / 총 레코드**: ~815M
- **Time Period / 기간**: 180 days (6 months / 6개월)

## File Structure / 파일 구성

```
customer360/
├── README.md                      # This file / 이 파일
├── 01-schema.sql                  # Database and table creation / 데이터베이스 및 테이블 생성
├── 02-load.sql                    # Test data generation / 테스트 데이터 생성
├── 03-basic-queries.sql           # Basic analysis queries / 기본 분석 쿼리
├── 04-advanced-queries.sql        # Advanced analysis queries / 고급 분석 쿼리
├── 05-optimization.sql            # Materialized views and optimization / Materialized View 및 최적화
└── 06-management.sql              # Data management and security / 데이터 관리 및 보안
```

## Execution Order / 실행 순서

### 1. Schema Creation / 스키마 생성

```bash
clickhouse-client --queries-file 01-schema.sql
```

**What it does / 수행 작업**:
- Creates `customer360` database / `customer360` 데이터베이스 생성
- Creates 6 tables / 6개 테이블 생성:
  - `customers`: Customer profile information / 고객 프로필 정보
  - `transactions`: Transaction history (partitioned) / 거래 이력 (파티션 적용)
  - `customer_events`: Web/app activity events / 웹/앱 활동 이벤트
  - `support_tickets`: Customer service tickets / 고객 서비스 티켓
  - `campaign_responses`: Marketing campaign responses / 마케팅 캠페인 응답
  - `product_reviews`: Product reviews / 제품 리뷰

**Expected time / 예상 시간**: ~1 second / 1초

### 2. Data Loading / 데이터 로딩

```bash
clickhouse-client --queries-file 02-load.sql
```

**What it does / 수행 작업**:
- Generates 30M customer records / 30M 고객 데이터 생성
- Generates 500M transaction records (2 batches) / 500M 거래 데이터 생성 (2회 분할)
- Generates 200M event records (2 batches) / 200M 이벤트 데이터 생성 (2회 분할)
- Generates 5M support tickets / 5M 서포트 티켓 생성
- Generates 100M campaign responses (2 batches) / 100M 캠페인 응답 생성 (2회 분할)
- Generates 10M product reviews / 10M 제품 리뷰 생성

**Expected time / 예상 시간**: 30-60 minutes (system dependent / 시스템 사양에 따라 다름)

**Warning / 주의**: Large-scale data generation. Ensure sufficient disk space (minimum 100GB).

**주의**: 대용량 데이터 생성 작업입니다. 충분한 디스크 공간(최소 100GB)을 확보하세요.

### 3. Basic Analytics / 기본 분석

```bash
clickhouse-client --queries-file 03-basic-queries.sql
```

**What it does / 수행 작업**:
- **Customer 360 Unified View**: 5-way JOIN for complete customer activity / 고객의 모든 활동 조회
- **Channel Analysis**: Revenue and customer behavior by channel / 채널별 매출 및 고객 행동 분석
- **Product Preferences by Segment**: Category preferences by customer segment / 세그먼트별 제품 선호도
- **Monthly Business Trends**: 6-month revenue and growth trends / 6개월간 매출 및 성장률 추이
- **Channel Growth Trends**: Monthly performance by channel / 채널별 월별 성과 분석
- **Conversion Funnel**: Conversion rates from visit to purchase / 방문 -> 구매 전환율 분석

**Expected time / 예상 시간**: 1-10 seconds per query / 각 쿼리당 1-10초

### 4. Advanced Analytics / 고급 분석

```bash
clickhouse-client --queries-file 04-advanced-queries.sql
```

**What it does / 수행 작업**:
- **RFM Analysis**: Customer segmentation by Recency, Frequency, Monetary / RFM 기반 고객 세그먼테이션
- **Cohort Analysis**: Retention rates by registration month / 등록 월별 리텐션율 계산
- **CLV Prediction**: Customer lifetime value prediction metrics / 고객 생애 가치 예측 지표
- **LTV Analysis**: 6-month customer lifetime value analysis / 6개월 기간 LTV 분석
- **Churn Risk Identification**: Churn prediction / 이탈 위험 고객 식별
- **Multi-touch Attribution**: Campaign effectiveness analysis / 캠페인 효과 분석
- **Customer Journey Mapping**: Customer interaction pattern analysis / 고객 상호작용 패턴 분석

**Expected time / 예상 시간**: 5-30 seconds per query / 각 쿼리당 5-30초

### 5. Optimization / 최적화

```bash
clickhouse-client --queries-file 05-optimization.sql
```

**What it does / 수행 작업**:
- **Create Materialized View**: Pre-aggregated customer KPIs / 실시간 고객 KPI 집계
- **MV Query Examples**: Queries using pre-aggregated data / 사전 집계 데이터 활용
- **Storage Analysis**: Compression ratio and storage space / 압축률 및 저장 공간 확인
- **Query Execution Plan**: EXPLAIN ESTIMATE for query cost analysis / 쿼리 비용 분석
- **Table Optimization**: OPTIMIZE TABLE execution / 테이블 최적화 실행
- **Partition Management**: Partition list and status / 파티션 목록 및 상태 확인
- **Performance Monitoring**: Query performance metrics tracking / 쿼리 성능 지표 추적

**Expected time / 예상 시간**: 5-10 minutes for optimization tasks / 최적화 작업 5-10분

### 6. Management & Security / 관리 및 보안

```bash
clickhouse-client --queries-file 06-management.sql
```

**What it does / 수행 작업**:
- **Partition Management**: Delete old partitions / 오래된 파티션 삭제
- **TTL Settings**: Automatic data deletion and aggregation / 자동 데이터 삭제 및 집계
- **RBAC**: Role-based access control / 역할 기반 접근 제어
- **Data Masking**: PII masking views / 개인정보 마스킹 뷰
- **Row Level Security**: Row Level Security Policy / 행 수준 보안
- **GDPR Compliance**: Personal data deletion and anonymization / 개인정보 삭제 및 익명화
- **Audit Log**: Access history tracking / 접근 이력 추적
- **System Monitoring**: Disk usage and query statistics / 디스크 사용량 및 쿼리 통계

**Expected time / 예상 시간**: Immediate execution for most commands / 대부분 즉시 실행

## Complete Execution (All at once) / 전체 실행 (한 번에)

```bash
# Sequential execution / 순차 실행
clickhouse-client --queries-file 01-schema.sql
clickhouse-client --queries-file 02-load.sql
clickhouse-client --queries-file 03-basic-queries.sql
clickhouse-client --queries-file 04-advanced-queries.sql
clickhouse-client --queries-file 05-optimization.sql
clickhouse-client --queries-file 06-management.sql
```

Or in a loop / 또는 반복문으로:

```bash
for file in 01-schema.sql 02-load.sql 03-basic-queries.sql 04-advanced-queries.sql 05-optimization.sql 06-management.sql; do
    echo "Executing $file..."
    clickhouse-client --queries-file "$file"
    echo ""
done
```

## Key Learning Points / 주요 학습 포인트

### 1. Schema Design / 스키마 설계
- MergeTree engine utilization / MergeTree 엔진 활용
- Partition key configuration (`PARTITION BY toYYYYMM`) / 파티션 키 설정
- Sorting key optimization (`ORDER BY`) / 정렬 키 최적화
- LowCardinality type utilization / LowCardinality 타입 활용

### 2. Large-scale Data Processing / 대용량 데이터 처리
- Test data generation with `numbers()` function / `numbers()` 함수로 테스트 데이터 생성
- Parallel INSERT with `max_insert_threads` / `max_insert_threads`로 병렬 INSERT
- Batch INSERT strategy / 배치 INSERT 전략

### 3. Complex Analytical Queries / 복잡한 분석 쿼리
- Multi-table JOIN / 다중 테이블 JOIN
- Window Functions
- CTE (Common Table Expressions)
- Aggregate function utilization / 집계 함수 활용

### 4. Performance Optimization / 성능 최적화
- Materialized View
- AggregatingMergeTree
- Query execution plan analysis / 쿼리 실행 계획 분석
- Partition pruning / 파티션 프루닝

### 5. Operations Management / 운영 관리
- TTL settings / TTL 설정
- Partition management / 파티션 관리
- RBAC
- Data masking / 데이터 마스킹
- Audit log / 감사 로그

## System Requirements / 시스템 요구사항

- **CPU**: Minimum 4 cores, recommended 8+ cores / 최소 4코어, 권장 8코어 이상
- **Memory**: Minimum 16GB, recommended 32GB+ / 최소 16GB, 권장 32GB 이상
- **Disk**: Minimum 100GB free space / 최소 100GB 여유 공간
- **ClickHouse Version / 버전**: 23.x or higher / 23.x 이상

## Performance Tips / 성능 팁

### During Data Loading / 데이터 로드 시
- Adjust `max_insert_threads` setting / `max_insert_threads` 설정 조정
- Optimize batch size / 배치 크기 최적화

### During Query Execution / 쿼리 실행 시
- Utilize partition keys in WHERE clause / WHERE 절에서 파티션 키 활용
- Use sampling (`WHERE customer_id % 100 = 0`) / 샘플링 활용
- Use appropriate LIMIT / 적절한 LIMIT 사용

### Monitoring / 모니터링
- Utilize `system.query_log` table / `system.query_log` 테이블 활용
- Check partitions with `system.parts` / `system.parts`로 파티션 확인
- Monitor running queries with `system.processes` / `system.processes`로 실행 중인 쿼리 확인

## Troubleshooting / 트러블슈팅

### Out of Memory Error / 메모리 부족 오류
```sql
SET max_memory_usage = 10000000000; -- 10GB
```

### Query Timeout / 쿼리 타임아웃
```sql
SET max_execution_time = 300; -- 5 minutes / 5분
```

### Insufficient Disk Space / 디스크 공간 부족
- Delete old partitions / 오래된 파티션 삭제
- Set TTL for automatic cleanup / TTL 설정으로 자동 정리
- Drop unnecessary tables / 불필요한 테이블 삭제

## Clean Up / 정리

Delete the test database after completion:

테스트 완료 후 데이터베이스 삭제:

```sql
DROP DATABASE IF EXISTS customer360;
```

## Reference / 참고 자료

- [ClickHouse Official Documentation](https://clickhouse.com/docs)
- [MergeTree Engine Guide](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/)
- [Query Optimization Guide](https://clickhouse.com/docs/en/guides/improving-query-performance/)

## License / 라이선스

MIT License

## Author / 작성자

Ken (ClickHouse Solution Architect)
Created: 2025-12-06 / 작성일: 2025-12-06
