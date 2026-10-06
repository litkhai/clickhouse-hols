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

[MIT](../../LICENSE) — same as the rest of the repository.

### 👤 Author

Ken (ClickHouse Solution Architect)
Created: 2025-12-06

### From the notes site (migrated, not verified)

> Moved on 2026-10-06 from the author's notes site (clickhouse.kr); not re-run here. English is an LLM-assisted translation. The figures below are as written in the note and may differ from the dataset scale above.

#### What is Customer 360?

Customer 360 is not just about collecting customer data; it enables a multi-dimensional understanding of the customer:

- **Profile data**: demographics, preferences, segments
- **Transaction data**: purchase history, payment information, per-channel transactions
- **Behavioral data**: web/app activity, session information, search patterns
- **Interaction data**: customer-service tickets, inquiry history
- **Marketing data**: campaign responses, conversion paths
- **Feedback data**: reviews, ratings, NPS scores

#### Fit-Gap analysis: test environment and storage efficiency

The note's test used a six-month dataset (2025-06-09 to 2025-12-06, 180 days).

| Table | Compressed | Uncompressed | Ratio | Rows |
| --- | --- | --- | --- | --- |
| transactions | 3.55 GiB | 31.05 GiB | 8.73x | 463M |
| customer_events | 907.34 MiB | 18.42 GiB | 20.79x | 200M |
| campaign_responses | 450.69 MiB | 5.68 GiB | 12.90x | 100M |
| customers | 268.03 MiB | 2.76 GiB | 10.56x | 30M |
| product_reviews | 52.50 MiB | 889.85 MiB | 16.95x | 10M |
| support_tickets | 11.50 MiB | 190.91 MiB | 16.60x | 5M |
| **Total** | **5.68 GiB** | **58.85 GiB** | **10.36x** | **808M** |

The note points out that more than 59 GB of data compressed to 5.7 GB, which it says could cut storage cost in a cloud environment by about 90%.

#### Weak patterns: where to be careful

**1. Complex self-joins and recursive queries**

Complex self-joins on the same table (for example recommendation-network analysis) can degrade performance.

```sql
-- Be careful with this pattern
SELECT
    t1.product_category AS category_a,
    t2.product_category AS category_b
FROM transactions t1
JOIN transactions t2
    ON t1.customer_id = t2.customer_id
    AND t1.transaction_id < t2.transaction_id
    AND dateDiff('day', t1.transaction_date, t2.transaction_date) <= 7
```

Workarounds: use sampling (`WHERE customer_id % 1000 = 0`), pre-aggregate with a Materialized View, limit the analysis scope by time or segment.

**2. Real-time updates and OLTP workloads**

ClickHouse is optimized for OLAP, so frequent UPDATE/DELETE of individual records is inefficient. Workarounds: insert changes as new records and pick the latest version at query time, use the ReplacingMergeTree engine, batch updates (thousands of rows at a time).

```sql
-- Pattern for reading the latest customer record
SELECT *
FROM (
    SELECT *, row_number() OVER (PARTITION BY customer_id ORDER BY last_updated DESC) AS rn
    FROM customers
)
WHERE rn = 1
```

**3. Transactions and strong consistency**

ClickHouse does not support multi-table transactions. Workarounds: manage consistency at the application level, accept an eventual-consistency model, handle critical transactions in an OLTP database and replicate them to ClickHouse.

**4. Join reordering**

The note says that from ClickHouse 25.10 the join order is optimized automatically, so less manual tuning is needed, but earlier versions still require thinking about join order. In a LEFT JOIN the left table is scanned first and the right table is loaded into memory, so put the large table on the left.

```sql
-- Recommended: large table on the LEFT
SELECT ...
FROM transactions t  -- large table
LEFT JOIN customers c ON t.customer_id = c.customer_id
```

Join algorithms: `hash` (default, fits most cases), `direct` (small dimension tables, with a Dictionary), `parallel_hash` (very large tables).

#### Performance benchmark results (as recorded in the note)

| Query type | Data scale | Run time | Throughput |
| --- | --- | --- | --- |
| Single-customer 360 view | 1 customer, 5-way JOIN | < 0.1 s | - |
| RFM segmentation | 30M customers | 2-3 s | 10M rows/sec |
| Cohort analysis | 30M customers, 60 days | 3-5 s | 8M rows/sec |
| Revenue by channel | 250M transactions | 1-2 s | 120M rows/sec |
| Funnel analysis | 100M events, 7 days | 2-4 s | 25M rows/sec |
| Multi-touch attribution | 50M campaign responses | 3-5 s | 10M rows/sec |

#### Conclusion

Why ClickHouse fits Customer 360:

1. **Large-scale processing**: hundreds of millions of records can be queried and analyzed in seconds.
2. **High compression**: 11x or more compression cuts storage cost substantially.
3. **Flexible schema**: flexible data modelling for integrating many data sources.
4. **SQL-friendly**: existing analysts can use it with no learning curve.
5. **Real-time analytics**: Materialized Views and incremental processing enable near-real-time analysis.

Things to consider when adopting:

1. **Workload shape**: it is optimized for OLAP-centric workloads; if you need OLTP, consider a hybrid architecture.
2. **Data modelling**: partitioning and sort-key design matched to query patterns is the key to performance.
3. **Security requirements**: a thorough security policy for handling sensitive personal data is essential.
4. **Cost optimization**: in the cloud, monitor storage and compute resources to optimize cost.

Extensions: similar-customer discovery with vector search, BI integration for real-time monitoring, churn and CLV prediction models, and an A/B testing platform that analyzes experiment results in real time.

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

[MIT](../../LICENSE) — same as the rest of the repository.

### 👤 작성자

Ken (ClickHouse Solution Architect)
작성일: 2025-12-06

### 노트 사이트에서 옮긴 내용 (이관본, 미검증)

> 2026-10-06 작성자의 노트 사이트(clickhouse.kr)에서 옮겼습니다. 이 저장소에서 다시 실행하지 않았습니다. 영어본은 LLM 도움으로 번역한 것입니다. 아래 수치는 노트 원문 그대로이며 위 데이터셋 규모와 다를 수 있습니다.

#### Customer 360이란?

Customer 360은 단순히 고객 데이터를 모으는 것이 아니라, 다음과 같은 다차원적인 고객 이해를 가능하게 합니다.

- **프로필 데이터**: 인구통계학적 정보, 선호도, 세그먼트
- **거래 데이터**: 구매 이력, 결제 정보, 채널별 거래
- **행동 데이터**: 웹/앱 활동, 세션 정보, 검색 패턴
- **상호작용 데이터**: 고객 서비스 티켓, 문의 이력
- **마케팅 데이터**: 캠페인 반응, 전환 경로
- **피드백 데이터**: 리뷰, 평점, NPS 점수

#### Fit-Gap 분석: 테스트 환경과 저장 효율

노트의 테스트는 6개월(2025년 6월 9일 ~ 12월 6일, 180일) 기간의 데이터셋을 사용했습니다.

| 테이블 | 압축 크기 | 원본 크기 | 압축률 | 레코드 수 |
| --- | --- | --- | --- | --- |
| transactions | 3.55 GiB | 31.05 GiB | 8.73x | 463M |
| customer_events | 907.34 MiB | 18.42 GiB | 20.79x | 200M |
| campaign_responses | 450.69 MiB | 5.68 GiB | 12.90x | 100M |
| customers | 268.03 MiB | 2.76 GiB | 10.56x | 30M |
| product_reviews | 52.50 MiB | 889.85 MiB | 16.95x | 10M |
| support_tickets | 11.50 MiB | 190.91 MiB | 16.60x | 5M |
| **전체** | **5.68 GiB** | **58.85 GiB** | **10.36x** | **808M** |

노트는 59GB가 넘는 데이터가 5.7GB로 압축되어, 클라우드 환경에서 스토리지 비용을 약 90% 절감할 수 있다고 설명합니다.

#### 약점 패턴: 주의해야 할 영역

**1. 복잡한 셀프 조인과 재귀 쿼리**

동일 테이블의 복잡한 셀프 조인(예: 추천 네트워크 분석)은 성능이 저하될 수 있습니다.

```sql
-- 이런 패턴은 주의 필요
SELECT
    t1.product_category AS category_a,
    t2.product_category AS category_b
FROM transactions t1
JOIN transactions t2
    ON t1.customer_id = t2.customer_id
    AND t1.transaction_id < t2.transaction_id
    AND dateDiff('day', t1.transaction_date, t2.transaction_date) <= 7
```

해결책: 샘플링 사용(`WHERE customer_id % 1000 = 0`), Materialized View로 사전 집계, 분석 범위를 시간/세그먼트로 제한.

**2. 실시간 업데이트와 OLTP 워크로드**

ClickHouse는 OLAP에 최적화되어 있어, 개별 레코드의 빈번한 UPDATE/DELETE는 비효율적입니다. 해결책: 변경 이력을 새 레코드로 삽입하고 쿼리 시점에 최신 버전 선택, ReplacingMergeTree 엔진 활용, 배치 업데이트(수천 건 단위).

```sql
-- 최신 고객 정보 조회 패턴
SELECT *
FROM (
    SELECT *, row_number() OVER (PARTITION BY customer_id ORDER BY last_updated DESC) AS rn
    FROM customers
)
WHERE rn = 1
```

**3. 트랜잭션과 강한 일관성**

ClickHouse는 멀티 테이블 트랜잭션을 지원하지 않습니다. 해결책: 애플리케이션 레벨에서 일관성 관리, 결과적 일관성 모델 수용, 중요한 트랜잭션은 OLTP DB에서 처리한 뒤 ClickHouse로 복제.

**4. 조인 리오더링 최적화**

노트는 ClickHouse 25.10부터 조인 순서가 자동으로 최적화되어 수동 최적화가 덜 필요하지만, 그 이전 버전에서는 여전히 조인 순서를 고려해야 한다고 설명합니다. LEFT JOIN에서는 왼쪽 테이블을 먼저 스캔하고 오른쪽 테이블을 메모리에 올리므로 큰 테이블을 왼쪽에 둡니다.

```sql
-- 권장 패턴: 큰 테이블을 LEFT에 배치
SELECT ...
FROM transactions t  -- 큰 테이블
LEFT JOIN customers c ON t.customer_id = c.customer_id
```

조인 알고리즘: `hash`(기본값, 대부분의 경우), `direct`(작은 차원 테이블, Dictionary 활용), `parallel_hash`(매우 큰 테이블 조인).

#### 성능 벤치마크 결과 (노트 기재값)

| 쿼리 유형 | 데이터 규모 | 실행 시간 | 처리량 |
| --- | --- | --- | --- |
| 단일 고객 360도 뷰 | 1명, 5-way JOIN | < 0.1초 | - |
| RFM 세그멘테이션 | 3천만 고객 | 2-3초 | 1천만 rows/sec |
| 코호트 분석 | 3천만 고객, 60일 | 3-5초 | 8백만 rows/sec |
| 채널별 매출 집계 | 2.5억 거래 | 1-2초 | 1.2억 rows/sec |
| 퍼널 분석 | 1억 이벤트, 7일 | 2-4초 | 2.5천만 rows/sec |
| 멀티터치 어트리뷰션 | 5천만 캠페인 응답 | 3-5초 | 1천만 rows/sec |

#### 결론

ClickHouse가 Customer 360에 적합한 이유:

1. **대규모 데이터 처리**: 수억 건의 레코드를 초 단위로 조회하고 분석할 수 있습니다.
2. **뛰어난 압축률**: 11x 이상의 압축으로 스토리지 비용을 대폭 절감할 수 있습니다.
3. **유연한 스키마**: 다양한 데이터 소스를 통합하기 위한 유연한 데이터 모델링이 가능합니다.
4. **SQL 친화적**: 기존 분석가들이 학습 곡선 없이 바로 활용 가능합니다.
5. **실시간 분석**: Materialized View와 증분 처리로 실시간에 가까운 분석이 가능합니다.

적용 시 고려사항:

1. **워크로드 특성**: OLAP 중심 워크로드에 최적화되어 있으므로, OLTP가 필요한 경우 하이브리드 아키텍처를 고려해야 합니다.
2. **데이터 모델링**: 쿼리 패턴에 맞춘 파티셔닝과 정렬 키 설계가 성능의 핵심입니다.
3. **보안 요구사항**: 민감한 개인정보 처리를 위한 철저한 보안 정책 수립이 필수입니다.
4. **비용 최적화**: 클라우드 환경에서는 스토리지와 컴퓨팅 리소스를 모니터링하여 비용을 최적화해야 합니다.

확장 방안: 벡터 검색을 활용한 유사 고객 발굴, BI 통합 실시간 모니터링, 이탈 예측·CLV 예측 모델, 실험 결과를 실시간으로 분석하는 A/B 테스트 플랫폼.
