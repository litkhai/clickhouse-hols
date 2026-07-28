# Customer 360 Lab with ClickHouse

[English](#english) | [한국어](#한국어)

---

## English

A comprehensive hands-on laboratory for large-scale Customer 360 analytics using ClickHouse, featuring 815 million records across 6 months of customer activity data.

### 🎯 Purpose

This lab provides practical experience with ClickHouse for Customer 360 analytics:
- Large-scale customer data integration (815M+ records)
- Multi-dimensional customer behavior analysis
- Advanced analytics: RFM, cohort analysis, CLV prediction
- Performance optimization with Materialized Views
- Data governance: RBAC, data masking, GDPR compliance

Whether you're building a customer data platform or exploring analytical capabilities for customer insights, this lab demonstrates production-ready patterns with realistic data volumes.

### 📊 Dataset Scale

- **Customers**: 30M (30 million)
- **Transactions**: 500M (500 million)
- **Events**: 200M (200 million)
- **Support Tickets**: 5M (5 million)
- **Campaign Responses**: 100M (100 million)
- **Product Reviews**: 10M (10 million)
- **Total Records**: ~815M
- **Time Period**: 180 days (6 months)

### 📁 File Structure

```
customer360/
├── README.md                      # This file
├── 01-schema.sql                  # Database and table creation
├── 02-load.sql                    # Test data generation
├── 03-basic-queries.sql           # Basic analysis queries
├── 04-advanced-queries.sql        # Advanced analysis queries
├── 05-optimization.sql            # Materialized views and optimization
└── 06-management.sql              # Data management and security
```

### 🚀 Quick Start

Execute all scripts in sequence:

```bash
cd usecase/customer360

# Sequential execution
clickhouse-client --queries-file 01-schema.sql
clickhouse-client --queries-file 02-load.sql
clickhouse-client --queries-file 03-basic-queries.sql
clickhouse-client --queries-file 04-advanced-queries.sql
clickhouse-client --queries-file 05-optimization.sql
clickhouse-client --queries-file 06-management.sql
```

Or in a loop:

```bash
for file in 01-schema.sql 02-load.sql 03-basic-queries.sql 04-advanced-queries.sql 05-optimization.sql 06-management.sql; do
    echo "Executing $file..."
    clickhouse-client --queries-file "$file"
    echo ""
done
```

### 📖 Detailed Lab Steps

#### 1. Schema Creation

```bash
clickhouse-client --queries-file 01-schema.sql
```

**What it does**:
- Creates `customer360` database
- Creates 6 tables:
  - `customers`: Customer profile information
  - `transactions`: Transaction history (partitioned by month)
  - `customer_events`: Web/app activity events
  - `support_tickets`: Customer service tickets
  - `campaign_responses`: Marketing campaign responses
  - `product_reviews`: Product reviews and ratings

**Expected time**: ~1 second

---

#### 2. Data Loading

```bash
clickhouse-client --queries-file 02-load.sql
```

**What it does**:
- Generates 30M customer records
- Generates 500M transaction records (2 batches)
- Generates 200M event records (2 batches)
- Generates 5M support tickets
- Generates 100M campaign responses (2 batches)
- Generates 10M product reviews

**Expected time**: 30-60 minutes (system dependent)

**Warning**: Large-scale data generation. Ensure sufficient disk space (minimum 100GB).

---

#### 3. Basic Analytics

```bash
clickhouse-client --queries-file 03-basic-queries.sql
```

**Query scenarios**:
- **Customer 360 Unified View**: 5-way JOIN for complete customer activity
- **Channel Analysis**: Revenue and customer behavior by channel
- **Product Preferences by Segment**: Category preferences by customer segment
- **Monthly Business Trends**: 6-month revenue and growth trends
- **Channel Growth Trends**: Monthly performance by channel
- **Conversion Funnel**: Conversion rates from visit to purchase

**Expected time**: 1-10 seconds per query

---

#### 4. Advanced Analytics

```bash
clickhouse-client --queries-file 04-advanced-queries.sql
```

**What it analyzes**:
- **RFM Analysis**: Customer segmentation by Recency, Frequency, Monetary
- **Cohort Analysis**: Retention rates by registration month
- **CLV Prediction**: Customer lifetime value prediction metrics
- **LTV Analysis**: 6-month customer lifetime value
- **Churn Risk Identification**: Predict customer churn risk
- **Multi-touch Attribution**: Campaign effectiveness analysis
- **Customer Journey Mapping**: Customer interaction pattern analysis

**Expected time**: 5-30 seconds per query

---

#### 5. Optimization

```bash
clickhouse-client --queries-file 05-optimization.sql
```

**What it does**:
- **Create Materialized View**: Pre-aggregated customer KPIs
- **MV Query Examples**: Queries using pre-aggregated data
- **Storage Analysis**: Compression ratio and storage space
- **Query Execution Plan**: EXPLAIN ESTIMATE for query cost analysis
- **Table Optimization**: OPTIMIZE TABLE execution
- **Partition Management**: Partition list and status
- **Performance Monitoring**: Query performance metrics tracking

**Expected time**: 5-10 minutes for optimization tasks

---

#### 6. Management & Security

```bash
clickhouse-client --queries-file 06-management.sql
```

**What it covers**:
- **Partition Management**: Delete old partitions
- **TTL Settings**: Automatic data deletion and aggregation
- **RBAC**: Role-based access control setup
- **Data Masking**: PII masking views
- **Row Level Security**: Row-level security policies
- **GDPR Compliance**: Personal data deletion and anonymization
- **Audit Log**: Access history tracking
- **System Monitoring**: Disk usage and query statistics

**Expected time**: Immediate execution for most commands

### 🔍 Key Learning Points

#### 1. Schema Design
- MergeTree engine utilization
- Partition key configuration (`PARTITION BY toYYYYMM`)
- Sorting key optimization (`ORDER BY`)
- LowCardinality type utilization

#### 2. Large-scale Data Processing
- Test data generation with `numbers()` function
- Parallel INSERT with `max_insert_threads`
- Batch INSERT strategy

#### 3. Complex Analytical Queries
- Multi-table JOINs
- Window Functions
- CTE (Common Table Expressions)
- Aggregate function utilization

#### 4. Performance Optimization
- Materialized Views
- AggregatingMergeTree
- Query execution plan analysis
- Partition pruning

#### 5. Operations Management
- TTL settings
- Partition management
- RBAC
- Data masking
- Audit logging

### 🛠 Prerequisites

- **CPU**: Minimum 4 cores, recommended 8+ cores
- **Memory**: Minimum 16GB, recommended 32GB+
- **Disk**: Minimum 100GB free space
- **ClickHouse Version**: 23.x or higher

### 💡 Performance Tips

#### During Data Loading
- Adjust `max_insert_threads` setting
- Optimize batch size

#### During Query Execution
- Utilize partition keys in WHERE clause
- Use sampling (`WHERE customer_id % 100 = 0`)
- Use appropriate LIMIT

#### Monitoring
- Utilize `system.query_log` table
- Check partitions with `system.parts`
- Monitor running queries with `system.processes`

### 🔧 Troubleshooting

#### Out of Memory Error
```sql
SET max_memory_usage = 10000000000; -- 10GB
```

#### Query Timeout
```sql
SET max_execution_time = 300; -- 5 minutes
```

#### Insufficient Disk Space
- Delete old partitions
- Set TTL for automatic cleanup
- Drop unnecessary tables

### 🧹 Clean Up

Delete the test database after completion:

```sql
DROP DATABASE IF EXISTS customer360;
```

### 📚 Reference

- [ClickHouse Official Documentation](https://clickhouse.com/docs)
- [MergeTree Engine Guide](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/)
- [Query Optimization Guide](https://clickhouse.com/docs/optimize/query-optimization)

### 📝 License

MIT License

### 👤 Author

Ken (ClickHouse Solution Architect)
Created: 2025-12-06

---

## 한국어

ClickHouse를 활용한 대규모 고객 360도 분석 종합 실습으로, 6개월간의 고객 활동 데이터를 포함한 8억 1천 5백만 레코드를 제공합니다.

### 🎯 목적

이 랩은 ClickHouse를 활용한 Customer 360 분석에 대한 실무 경험을 제공합니다:
- 대규모 고객 데이터 통합 (8억 1천 5백만+ 레코드)
- 다차원 고객 행동 분석
- 고급 분석: RFM, 코호트 분석, CLV 예측
- Materialized View를 통한 성능 최적화
- 데이터 거버넌스: RBAC, 데이터 마스킹, GDPR 준수

고객 데이터 플랫폼을 구축하거나 고객 인사이트를 위한 분석 기능을 탐구하는 경우, 이 랩은 실제 데이터 볼륨으로 프로덕션 수준의 패턴을 시연합니다.

### 📊 데이터셋 규모

- **고객**: 30M (3천만)
- **거래**: 500M (5억)
- **이벤트**: 200M (2억)
- **서포트 티켓**: 5M (5백만)
- **캠페인 응답**: 100M (1억)
- **제품 리뷰**: 10M (1천만)
- **총 레코드**: ~815M
- **기간**: 180일 (6개월)

### 📁 파일 구성

```
customer360/
├── README.md                      # 이 파일
├── 01-schema.sql                  # 데이터베이스 및 테이블 생성
├── 02-load.sql                    # 테스트 데이터 생성
├── 03-basic-queries.sql           # 기본 분석 쿼리
├── 04-advanced-queries.sql        # 고급 분석 쿼리
├── 05-optimization.sql            # Materialized View 및 최적화
└── 06-management.sql              # 데이터 관리 및 보안
```

### 🚀 빠른 시작

모든 스크립트를 순서대로 실행:

```bash
cd usecase/customer360

# 순차 실행
clickhouse-client --queries-file 01-schema.sql
clickhouse-client --queries-file 02-load.sql
clickhouse-client --queries-file 03-basic-queries.sql
clickhouse-client --queries-file 04-advanced-queries.sql
clickhouse-client --queries-file 05-optimization.sql
clickhouse-client --queries-file 06-management.sql
```

또는 반복문으로:

```bash
for file in 01-schema.sql 02-load.sql 03-basic-queries.sql 04-advanced-queries.sql 05-optimization.sql 06-management.sql; do
    echo "Executing $file..."
    clickhouse-client --queries-file "$file"
    echo ""
done
```

### 📖 상세 실습 단계

#### 1. 스키마 생성

```bash
clickhouse-client --queries-file 01-schema.sql
```

**수행 작업**:
- `customer360` 데이터베이스 생성
- 6개 테이블 생성:
  - `customers`: 고객 프로필 정보
  - `transactions`: 거래 이력 (월별 파티션)
  - `customer_events`: 웹/앱 활동 이벤트
  - `support_tickets`: 고객 서비스 티켓
  - `campaign_responses`: 마케팅 캠페인 응답
  - `product_reviews`: 제품 리뷰 및 평점

**예상 시간**: ~1초

---

#### 2. 데이터 로딩

```bash
clickhouse-client --queries-file 02-load.sql
```

**수행 작업**:
- 30M 고객 레코드 생성
- 500M 거래 레코드 생성 (2회 분할)
- 200M 이벤트 레코드 생성 (2회 분할)
- 5M 서포트 티켓 생성
- 100M 캠페인 응답 생성 (2회 분할)
- 10M 제품 리뷰 생성

**예상 시간**: 30-60분 (시스템 사양에 따라 다름)

**주의**: 대용량 데이터 생성 작업입니다. 충분한 디스크 공간(최소 100GB)을 확보하세요.

---

#### 3. 기본 분석

```bash
clickhouse-client --queries-file 03-basic-queries.sql
```

**쿼리 시나리오**:
- **고객 360 통합 뷰**: 5-way JOIN으로 전체 고객 활동 조회
- **채널 분석**: 채널별 매출 및 고객 행동 분석
- **세그먼트별 제품 선호도**: 고객 세그먼트별 카테고리 선호도
- **월별 비즈니스 트렌드**: 6개월간 매출 및 성장률 추이
- **채널 성장 추이**: 채널별 월별 성과 분석
- **전환 퍼널**: 방문에서 구매까지의 전환율 분석

**예상 시간**: 각 쿼리당 1-10초

---

#### 4. 고급 분석

```bash
clickhouse-client --queries-file 04-advanced-queries.sql
```

**분석 내용**:
- **RFM 분석**: Recency, Frequency, Monetary 기반 고객 세그먼테이션
- **코호트 분석**: 등록 월별 리텐션율 계산
- **CLV 예측**: 고객 생애 가치 예측 지표
- **LTV 분석**: 6개월 기간 고객 생애 가치
- **이탈 위험 식별**: 고객 이탈 위험 예측
- **멀티터치 어트리뷰션**: 캠페인 효과 분석
- **고객 여정 매핑**: 고객 상호작용 패턴 분석

**예상 시간**: 각 쿼리당 5-30초

---

#### 5. 최적화

```bash
clickhouse-client --queries-file 05-optimization.sql
```

**수행 작업**:
- **Materialized View 생성**: 실시간 고객 KPI 집계
- **MV 쿼리 예제**: 사전 집계 데이터 활용
- **스토리지 분석**: 압축률 및 저장 공간 확인
- **쿼리 실행 계획**: EXPLAIN ESTIMATE로 쿼리 비용 분석
- **테이블 최적화**: OPTIMIZE TABLE 실행
- **파티션 관리**: 파티션 목록 및 상태 확인
- **성능 모니터링**: 쿼리 성능 지표 추적

**예상 시간**: 최적화 작업 5-10분

---

#### 6. 관리 및 보안

```bash
clickhouse-client --queries-file 06-management.sql
```

**다루는 내용**:
- **파티션 관리**: 오래된 파티션 삭제
- **TTL 설정**: 자동 데이터 삭제 및 집계
- **RBAC**: 역할 기반 접근 제어 설정
- **데이터 마스킹**: 개인정보 마스킹 뷰
- **행 수준 보안**: 행 수준 보안 정책
- **GDPR 준수**: 개인정보 삭제 및 익명화
- **감사 로그**: 접근 이력 추적
- **시스템 모니터링**: 디스크 사용량 및 쿼리 통계

**예상 시간**: 대부분 즉시 실행

### 🔍 주요 학습 포인트

#### 1. 스키마 설계
- MergeTree 엔진 활용
- 파티션 키 설정 (`PARTITION BY toYYYYMM`)
- 정렬 키 최적화 (`ORDER BY`)
- LowCardinality 타입 활용

#### 2. 대용량 데이터 처리
- `numbers()` 함수로 테스트 데이터 생성
- `max_insert_threads`로 병렬 INSERT
- 배치 INSERT 전략

#### 3. 복잡한 분석 쿼리
- 다중 테이블 JOIN
- Window Functions
- CTE (Common Table Expressions)
- 집계 함수 활용

#### 4. 성능 최적화
- Materialized View
- AggregatingMergeTree
- 쿼리 실행 계획 분석
- 파티션 프루닝

#### 5. 운영 관리
- TTL 설정
- 파티션 관리
- RBAC
- 데이터 마스킹
- 감사 로그

### 🛠 사전 요구사항

- **CPU**: 최소 4코어, 권장 8코어 이상
- **메모리**: 최소 16GB, 권장 32GB 이상
- **디스크**: 최소 100GB 여유 공간
- **ClickHouse 버전**: 23.x 이상

### 💡 성능 팁

#### 데이터 로드 시
- `max_insert_threads` 설정 조정
- 배치 크기 최적화

#### 쿼리 실행 시
- WHERE 절에서 파티션 키 활용
- 샘플링 활용 (`WHERE customer_id % 100 = 0`)
- 적절한 LIMIT 사용

#### 모니터링
- `system.query_log` 테이블 활용
- `system.parts`로 파티션 확인
- `system.processes`로 실행 중인 쿼리 확인

### 🔧 트러블슈팅

#### 메모리 부족 오류
```sql
SET max_memory_usage = 10000000000; -- 10GB
```

#### 쿼리 타임아웃
```sql
SET max_execution_time = 300; -- 5분
```

#### 디스크 공간 부족
- 오래된 파티션 삭제
- TTL 설정으로 자동 정리
- 불필요한 테이블 삭제

### 🧹 정리

테스트 완료 후 데이터베이스 삭제:

```sql
DROP DATABASE IF EXISTS customer360;
```

### 📚 참고 자료

- [ClickHouse Official Documentation](https://clickhouse.com/docs)
- [MergeTree Engine Guide](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/)
- [Query Optimization Guide](https://clickhouse.com/docs/optimize/query-optimization)

### 📝 라이선스

MIT License

### 👤 작성자

Ken (ClickHouse Solution Architect)
작성일: 2025-12-06
