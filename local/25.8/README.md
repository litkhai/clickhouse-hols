# ClickHouse 25.8 New Features Lab

[English](#english) | [한국어](#한국어)

---

## English

A hands-on laboratory for learning and testing ClickHouse 25.8 new features. This directory is designed for practical exercises with **integrated MinIO-based Data Lake environment**.

### 📋 Overview

ClickHouse 25.8 includes a new Parquet Reader (1.81x faster), enhanced Data Lake integration, Hive-style partitioning, S3 temporary data storage, and improved UNION ALL functionality.

### 🎯 Key Features

1. **New Parquet Reader** - 1.81x faster performance, 99.98% less data scanning
2. **MinIO Integration** - Data Lake implementation via S3-compatible storage
3. **Data Lake Enhancements** - Iceberg CREATE/DROP, Delta Lake writes, time travel
4. **Hive-Style Partitioning** - partition_strategy parameter, directory-based partitioning
5. **Temporary Data on S3** - Use S3 instead of local disk for temporary data storage
6. **Enhanced UNION ALL** - _table virtual column support

### 🚀 Quick Start

#### Prerequisites

- macOS (with Docker Desktop)
- [oss-mac-setup](../oss-mac-setup/) environment setup
- [datalake-minio-catalog](../datalake-minio-catalog/) auto-deployment (handled by setup script)

#### Setup and Run

```bash
# 1. Install ClickHouse 25.8 + MinIO Data Lake and start
cd local/25.8
./00-setup.sh   # Deploys ClickHouse 25.8, MinIO, and Nessie

# 2. Run tests for each feature
./01-new-parquet-reader.sh      # Local file-based Parquet Reader test
./06-minio-integration.sh       # MinIO S3 integration test (★ Recommended)
./02-hive-partitioning.sh
./03-temp-data-s3.sh
./04-union-all-table.sh
./05-data-lake-features.sh
```

#### What Gets Deployed

When running `./00-setup.sh`, the following are automatically deployed:

1. **MinIO** (ports 19000, 19001)
   - S3-compatible object storage
   - Web console: http://localhost:19001
   - Credentials: admin / password123

2. **Nessie** (port 19120)
   - Git-like data catalog
   - REST API: http://localhost:19120

3. **ClickHouse 25.8** (ports 2508, 25081)
   - Web UI: http://localhost:2508/play
   - TCP port: 25081

#### Manual Execution (SQL only)

To execute SQL files directly:

```bash
# Connect to ClickHouse client
cd ../oss-mac-setup
./client.sh 2508

# Execute SQL file
cd ../25.8
source 01-new-parquet-reader.sql
```

### 📚 Feature Details

#### 0. MinIO Integration (06-minio-integration) ★ Recommended

**New Feature:** Real-world Data Lake implementation with ClickHouse 25.8 + MinIO S3-compatible storage

**Test Content:**
- Generate 50,000 e-commerce order data
- Export data to MinIO in Parquet format
- Read data from MinIO using S3 functions
- Column pruning optimization (99.98% less data scanning)
- Split files by country and wildcard queries
- Daily revenue analysis (14 days)
- Product category performance analysis
- Customer segmentation analysis (VIP, Premium)

**Execute:**
```bash
./06-minio-integration.sh
```

**Key Learning Points:**
- Integration of S3-compatible storage (MinIO) with ClickHouse
- Data read/write via `s3()` function
- Real-world performance of new Parquet Reader (1.81x faster)
- Minimal data scanning through column pruning
- Multi-file queries using wildcards
- Data Lake implementation in local development environment

**Real-World Use Cases:**
- Local Data Lake development and testing
- Local validation before S3 migration
- Cost-effective data storage
- Data analytics pipeline prototyping
- E-commerce revenue analysis dashboard
- Customer behavior analysis and segmentation

**Dataset:**
- 50,000 orders (8 countries, 5,000 customers)
- 8 product categories
- 4 order statuses
- 38M+ total revenue

---

#### 1. New Parquet Reader (01-new-parquet-reader)

**New Feature:** New Parquet Reader with 1.81x faster performance and 99.98% less data scanning

**Test Content:**
- E-commerce event dataset generation (100,000 rows)
- Parquet file export
- Reading with new Parquet Reader
- Column pruning optimization (read only necessary columns)
- Complex analytical query performance
- Conversion funnel analysis
- User behavior analysis
- Device and channel performance analysis
- Geographic analysis
- Product category performance
- Time-based activity patterns

**Execute:**
```bash
./01-new-parquet-reader.sh
# Or
cat 01-new-parquet-reader.sql | docker exec -i clickhouse-25-8 clickhouse-client --multiline --multiquery
```

**Key Learning Points:**
- New Parquet Reader is 1.81x faster than previous version
- Column pruning scans 99.98% less data
- Improved memory efficiency by reading only necessary columns
- Full support for Parquet v2 format
- Reduced memory usage for large Parquet files
- Improved support for nested structures and arrays

**Real-World Use Cases:**
- Data Lake query acceleration
- Direct analysis of Parquet files on S3/GCS/Azure
- ETL pipeline optimization
- Large-scale log file analysis
- Data warehouse federated queries
- Machine learning feature engineering
- Real-time analytics dashboards
- Cost-effective cold storage queries

**Performance Comparison:**
| Task | Previous Version | ClickHouse 25.8 | Improvement |
|------|-----------------|-----------------|-------------|
| Full Parquet scan | Baseline | 1.81x faster | 81% improvement |
| Selective column read | Scans much data | 99.98% less scan | Scans only 0.02% |
| Memory usage | High | Significantly reduced | Improved efficiency |

---

#### 2. Hive-Style Partitioning (02-hive-partitioning)

**New Feature:** Hive-style directory structure support with partition_strategy parameter

**Test Content:**
- Sales transaction data generation (100,000 rows)
- Export data with Hive-style partitioning (year=YYYY/month=MM/)
- Read partitioned data
- Partition pruning (scan only specific partitions)
- Regional sales analysis
- Product category performance
- Store performance ranking
- Payment method analysis
- Daily sales trends
- High-value customer analysis
- Partition efficiency comparison
- Monthly growth rate analysis

**Execute:**
```bash
./02-hive-partitioning.sh
```

**Key Learning Points:**
- Hive partitioning: key=value directory structure
- Avoid unnecessary directory scans with partition pruning
- Standard approach compatible with Spark, Presto, Athena
- Multi-level partitioning support (year/month/day)
- Automatic partition column detection
- Add partitions without schema changes
- Data organization and query optimization

**Real-World Use Cases:**
- Data Lake organization (S3, HDFS, GCS)
- Multi-engine data sharing (Spark + ClickHouse)
- Time-series data management
- Geographic data partitioning
- Multi-tenant data isolation
- ETL pipeline optimization
- Compliance data retention
- Cost-effective data archiving

**Partition Pattern Examples:**
```
/data/year=2024/month=12/day=01/
/data/country=US/region=West/
/data/tenant_id=123/date=2024-12-01/
/data/event_type=purchase/hour=14/
```

**Performance Benefits:**
- **Reduced I/O:** Skip irrelevant partitions
- **Query speed:** Read only necessary data
- **Organization:** Intuitive directory structure
- **Scalability:** Efficiently handle petabyte-scale data

---

#### 3. Temporary Data on S3 (03-temp-data-s3)

**New Feature:** Use S3 instead of local disk for temporary data storage

**Test Content:**
- Understanding temporary data concept
- S3 temporary data configuration methods
- Large dataset generation (500,000 events)
- Large JOIN operations (using temporary storage)
- High cardinality GROUP BY aggregation
- Large-scale DISTINCT operations
- Complex window functions
- Large-scale ORDER BY sorting
- Session analysis (complex queries)
- Product performance analysis (multi-JOIN)
- User cohort analysis

**Execute:**
```bash
./03-temp-data-s3.sh
```

**Key Learning Points:**
- Temporary data is generated during query execution (JOIN, GROUP BY, ORDER BY, etc.)
- Before 25.8: Local disk only, space constraints
- After 25.8: S3 available, unlimited capacity
- Automatic spillover when memory exceeds
- Transparent operation to queries
- S3-optimized I/O patterns
- Automatic temporary data cleanup

**Operations Requiring Temporary Data:**
1. Large JOINs (hash tables)
2. High cardinality GROUP BY
3. Large data sorting (ORDER BY)
4. Window functions
5. DISTINCT operations
6. Aggregations exceeding memory limits

**Configuration Example:**
```xml
<storage_configuration>
    <disks>
        <s3_disk>
            <type>s3</type>
            <endpoint>https://bucket.s3.amazonaws.com/temp/</endpoint>
        </s3_disk>
    </disks>
</storage_configuration>
```

```sql
SET max_bytes_before_external_group_by = 10000000000;  -- 10GB
SET max_bytes_before_external_sort = 10000000000;       -- 10GB
SET temporary_data_policy = 'temp_policy';
```

**Real-World Use Cases:**
- Ad-hoc analysis of large datasets
- Complex multi-table JOINs
- High cardinality aggregations
- Data exploration and discovery
- Machine learning feature engineering
- Full dataset quality checks
- Overcome local disk constraints
- Cost-effective large-scale processing

**Benefits:**
- Can exceed local disk limits
- Better resource utilization
- Cost efficiency (S3 cheaper than local SSD)
- No manual temporary data management
- Improved query success rate

---

#### 4. Enhanced UNION ALL with _table Virtual Column (04-union-all-table)

**New Feature:** _table virtual column for source table identification in UNION ALL

**Test Content:**
- Create multi-region sales tables (US, EU, Asia, LATAM)
- Insert regional sales data
- Use UNION ALL with _table column
- Global sales analysis
- Regional daily sales trends
- Regional product performance
- Customer distribution analysis
- Filter by source table
- Cross-region performance comparison
- Weekly trend analysis
- Data lineage tracking
- Multi-currency aggregation

**Execute:**
```bash
./04-union-all-table.sh
```

**Key Learning Points:**
- _table virtual column identifies source table in UNION ALL results
- Can use _table in WHERE, GROUP BY, ORDER BY
- Enable data lineage tracking
- Source-based aggregation and filtering
- Multi-table query audit trails
- Minimal overhead

**Syntax Examples:**
```sql
SELECT *, 'table1' AS _table FROM table1
UNION ALL
SELECT *, 'table2' AS _table FROM table2

-- Filter by _table
WHERE _table = 'table1'

-- Group by _table
GROUP BY _table

-- Order by _table
ORDER BY _table, revenue DESC
```

**Real-World Use Cases:**
- Multi-region data integration
- Year-based table union (historical data)
- Multi-tenant data queries
- Federated query results
- Data migration validation
- Cross-shard analysis
- Audit and compliance
- Data governance

**Key Benefits:**
- Data lineage tracking
- Source identification in merged results
- Filter by source table
- Source-based aggregation
- Multi-table query audit trails
- Debugging and troubleshooting

---

#### 5. Data Lake Enhancements (05-data-lake-features)

**New Feature:** Iceberg CREATE/DROP, Delta Lake writes, time travel

**Test Content:**
- Data Lake overview and feature description
- Product catalog data generation (10,000 products)
- Export to Data Lake in Parquet format
- Read data from Data Lake
- Version management simulation (v1, v2, v3)
- Time travel - version comparison
- Delta Lake style incremental updates
- Iceberg style partitioning
- Schema evolution simulation
- Multi-version queries
- Data Lake metadata queries
- Point-in-time queries
- Version-based audit trails

**Execute:**
```bash
./05-data-lake-features.sh
```

**Key Learning Points:**
- Apache Iceberg table CREATE/DROP
- Delta Lake write support
- ACID transaction guarantees
- Schema evolution (without rewriting)
- Query historical versions with time travel
- Version comparison and auditing
- Metadata optimization
- Multi-format integration (Parquet, Iceberg, Delta)

**Time Travel Examples:**
```sql
-- Iceberg: Point-in-time query
SELECT * FROM iceberg_table
FOR SYSTEM_TIME AS OF '2024-12-01';

-- Delta Lake: Specific version query
SELECT * FROM delta_table
VERSION AS OF 42;

-- Timestamp-based query
SELECT * FROM delta_table
TIMESTAMP AS OF '2024-12-01 00:00:00';
```

**Real-World Use Cases:**
- Data Lake analytics
  - Direct S3/HDFS queries
  - Multi-format support
  - Partition pruning

- Data engineering:
  - ETL pipelines
  - Data quality checks
  - Schema evolution

- Data science:
  - Feature engineering
  - Historical analysis
  - Experiment tracking

- Compliance and auditing:
  - Regulatory compliance with time travel
  - Audit trails
  - Data lineage

- Real-time analytics:
  - Streaming + batch
  - Incremental updates
  - ACID guarantees

**Integration Examples:**
- **ClickHouse + Spark:** Share Iceberg tables
- **ClickHouse + Presto:** Federated queries
- **ClickHouse + Airflow:** ETL orchestration
- **ClickHouse + dbt:** Data transformation
- **ClickHouse + Kafka:** Streaming ingestion

**Performance Tips:**
- Use partitioning for large datasets
- Leverage time travel for debugging
- Implement schema evolution carefully
- Monitor metadata operations
- Optimize partition strategy
- Improve storage efficiency with compression
- Optimize file size (128MB-1GB)

### 🔧 Management

#### ClickHouse Connection Info

- **Web UI**: http://localhost:2508/play
- **HTTP API**: http://localhost:2508
- **TCP**: localhost:25081
- **User**: default (no password)

#### Useful Commands

```bash
# Check ClickHouse status
cd ../oss-mac-setup
./status.sh

# Connect to CLI
./client.sh 2508

# View logs
docker logs clickhouse-25-8

# Stop
./stop.sh

# Complete removal
./stop.sh --cleanup
```

### 📂 File Structure

```
25.8/
├── README.md                      # This document
├── 00-setup.sh                    # ClickHouse 25.8 installation script
├── 01-new-parquet-reader.sh       # New Parquet Reader test execution
├── 01-new-parquet-reader.sql      # New Parquet Reader SQL
├── 02-hive-partitioning.sh        # Hive-style partitioning test execution
├── 02-hive-partitioning.sql       # Hive-style partitioning SQL
├── 03-temp-data-s3.sh             # S3 temporary data test execution
├── 03-temp-data-s3.sql            # S3 temporary data SQL
├── 04-union-all-table.sh          # UNION ALL test execution
├── 04-union-all-table.sql         # UNION ALL SQL
├── 05-data-lake-features.sh       # Data Lake features test execution
├── 05-data-lake-features.sql      # Data Lake features SQL
├── 06-minio-integration.sh        # MinIO integration test execution
└── 06-minio-integration.sql       # MinIO integration SQL
```

### 🎓 Learning Path

#### For Beginners
1. **00-setup.sh** - Understand environment setup
2. **01-new-parquet-reader** - Learn Parquet file reading and performance improvements
3. **04-union-all-table** - Basics of multi-table integration

#### For Intermediate Users
1. **02-hive-partitioning** - Understand partitioning strategies
2. **03-temp-data-s3** - Learn large-scale query optimization
3. **05-data-lake-features** - Explore Data Lake integration

#### For Advanced Users
- Combine all features to implement end-to-end Data Lake pipelines
- Design real production scenarios
- Performance benchmarking and optimization
- Multi-engine integration (Spark, Presto, ClickHouse)

### 💡 Feature Comparison

#### ClickHouse 25.8 vs Previous Versions

| Feature | Before 25.8 | ClickHouse 25.8 | Improvement |
|---------|-------------|-----------------|-------------|
| Parquet Reader | Standard | 1.81x faster | 81% faster |
| Parquet Column Pruning | Basic | 99.98% less scan | Drastically reduced I/O |
| Hive Partitioning | Manual | Native support | Standard compatibility |
| Temporary Data | Local disk only | S3 support | Unlimited capacity |
| UNION ALL | Basic | _table column | Source tracking |
| Iceberg Tables | Read-only | CREATE/DROP | Full management |
| Delta Lake | Read-only | Write support | Bidirectional |
| Time Travel | Limited | Full support | Historical queries |

#### Performance Comparison

| Operation | Previous | ClickHouse 25.8 | Benefit |
|-----------|----------|-----------------|---------|
| Parquet full scan | Baseline | 1.81x faster | Speed |
| Parquet selective columns | Many bytes | 0.02% of data | I/O efficiency |
| Hive partition query | Full scan | Partition pruning | Reduced scanning |
| Large JOIN | Memory limited | S3 spillover | Unlimited capacity |
| Multi-table union | No tracking | Source identification | Data lineage |
| Data Lake writes | Limited | Full ACID | Data integrity |

### 🔍 Additional Resources

- **Official Release Blog**: [ClickHouse 25.8 Release](https://clickhouse.com/blog/clickhouse-release-25-08)
- **ClickHouse Documentation**: [docs.clickhouse.com](https://clickhouse.com/docs)
- **Release Notes**: [Changelog 2025](https://clickhouse.com/docs/whats-new/changelog)
- **GitHub Repository**: [ClickHouse GitHub](https://github.com/ClickHouse/ClickHouse)
- **Data Lake Formats**:
  - [Apache Iceberg](https://iceberg.apache.org/)
  - [Delta Lake](https://delta.io/)
  - [Apache Parquet](https://parquet.apache.org/)

### 📝 Notes

- Each script can be executed independently
- Read and modify SQL files directly to experiment
- Test data is generated within each SQL file
- Cleanup is commented out by default
- Thorough testing recommended before production use
- Data Lake features may require appropriate storage configuration

### 🔒 Security Considerations

**When accessing Data Lake:**
- Manage S3/GCS/Azure credentials securely
- Use environment variables or IAM roles
- Data encryption (in transit and at rest)
- Access control and permission management
- Enable audit logging

**When using temporary data:**
- S3 bucket access control
- Set up automatic temporary data cleanup
- Cost monitoring
- Consider network bandwidth

### ⚡ Performance Tips

**Parquet Reader optimization:**
- SELECT only necessary columns
- Filter rows with WHERE conditions
- Maintain appropriate file size (128MB-1GB)
- Choose compression algorithm (Snappy, ZSTD)

**Hive Partitioning optimization:**
- Choose partition keys matching query patterns
- Maintain appropriate partition count (not too many or too few)
- Include partition keys in WHERE conditions
- Leverage partition pruning

**Temporary data optimization:**
- Set appropriate memory thresholds
- Perform large operations during off-peak hours
- Monitor S3 usage costs
- Leverage local cache

**UNION ALL optimization:**
- Partition pruning with _table column
- Exclude unnecessary tables
- Leverage index keys

**Data Lake optimization:**
- Partition time-series data by date
- Leverage metadata caching
- Optimize file size
- Utilize predicate pushdown

### 🚀 Production Deployment

#### Best Practices

```sql
-- Check partition information
SELECT
    partition,
    name,
    rows,
    bytes_on_disk
FROM system.parts
WHERE table = 'your_table'
  AND active = 1;

-- Monitor running queries
SELECT
    query_id,
    user,
    query,
    elapsed,
    memory_usage
FROM system.processes
WHERE query NOT LIKE '%system.processes%';

-- Check disk usage
SELECT
    name,
    path,
    formatReadableSize(free_space) AS free,
    formatReadableSize(total_space) AS total
FROM system.disks;
```

### 🛠 Management Commands

#### ClickHouse Management

```bash
# Check ClickHouse status
cd ../oss-mac-setup
./status.sh

# Connect to ClickHouse CLI
./client.sh 2508

# Stop ClickHouse
./stop.sh

# Restart ClickHouse
./start.sh
```

#### Data Lake (MinIO + Nessie) Management

```bash
# Access MinIO web console
# In browser: http://localhost:19001
# Credentials: admin / password123

# Stop MinIO and Nessie
cd ../datalake-minio-catalog
docker-compose down

# Restart MinIO and Nessie
docker-compose up -d minio nessie minio-setup

# Complete MinIO data removal
docker-compose down -v

# Check container logs
docker-compose logs -f minio
docker-compose logs -f nessie
```

#### Full Environment Reconfiguration

```bash
# 1. Stop and clean all services
cd ../oss-mac-setup
./stop.sh

cd ../datalake-minio-catalog
docker-compose down -v

# 2. Full restart
cd ../25.8
./00-setup.sh
```

#### Data Verification

```bash
# Check files stored in MinIO
docker exec -it minio mc ls myminio/warehouse/

# Check ClickHouse tables
docker exec -it clickhouse-25-8 clickhouse-client -q "SHOW TABLES"

# Check ClickHouse database size
docker exec -it clickhouse-25-8 clickhouse-client -q "SELECT database, formatReadableSize(sum(bytes)) as size FROM system.parts GROUP BY database"
```

#### Migration Strategy

1. **Validate in test environment**
   - Test all new features
   - Performance benchmarking
   - Establish rollback plan

2. **Gradual rollout**
   - Start with small datasets
   - Monitor and measure performance
   - Immediate response on issues

3. **Monitoring**
   - Track query performance
   - Monitor resource usage
   - Check errors and warnings

### 🤝 Contributing

If you have improvements or additional examples for this lab:
1. Register an issue
2. Submit a Pull Request
3. Share feedback

### 📄 License

MIT License - Free to learn and modify

---

**Happy Learning! 🚀**

For questions or issues, please refer to the main [clickhouse-hols README](../../README.md).

---

## 한국어

ClickHouse 25.8 신기능 테스트 및 학습 환경입니다. 이 디렉토리는 ClickHouse 25.8에서 새롭게 추가된 기능들을 실습하고 반복 학습할 수 있도록 구성되어 있으며, **MinIO 기반 Data Lake 환경이 통합**되어 있습니다.

### 📋 개요

ClickHouse 25.8은 새로운 Parquet Reader (1.81배 빠른 성능), Data Lake 통합 강화, Hive-style 파티셔닝, S3 임시 데이터 저장, 그리고 향상된 UNION ALL 기능을 포함합니다.

### 🎯 주요 기능

1. **New Parquet Reader** - 1.81배 빠른 성능, 99.98% 적은 데이터 스캔
2. **MinIO Integration** - S3 호환 스토리지를 통한 Data Lake 구현
3. **Data Lake Enhancements** - Iceberg CREATE/DROP, Delta Lake 쓰기, 시간 여행
4. **Hive-Style Partitioning** - partition_strategy 파라미터, 디렉토리 기반 파티셔닝
5. **Temporary Data on S3** - 로컬 디스크 대신 S3를 임시 데이터 저장소로 활용
6. **Enhanced UNION ALL** - _table 가상 컬럼 지원

### 🚀 빠른 시작

#### 사전 요구사항

- macOS (with Docker Desktop)
- [oss-mac-setup](../oss-mac-setup/) 환경 구성
- [datalake-minio-catalog](../datalake-minio-catalog/) 자동 배포 (setup 스크립트가 처리)

#### 설정 및 실행

```bash
# 1. ClickHouse 25.8 + MinIO Data Lake 설치 및 시작
cd local/25.8
./00-setup.sh   # ClickHouse 25.8, MinIO, Nessie를 모두 배포합니다

# 2. 각 기능별 테스트 실행
./01-new-parquet-reader.sh      # 로컬 파일 기반 Parquet Reader 테스트
./06-minio-integration.sh       # MinIO S3 통합 테스트 (★ 추천)
./02-hive-partitioning.sh
./03-temp-data-s3.sh
./04-union-all-table.sh
./05-data-lake-features.sh
```

#### 배포되는 항목

`./00-setup.sh` 실행 시 다음이 자동으로 배포됩니다:

1. **MinIO** (포트 19000, 19001)
   - S3 호환 객체 스토리지
   - 웹 콘솔: http://localhost:19001
   - 자격증명: admin / password123

2. **Nessie** (포트 19120)
   - Git-like 데이터 카탈로그
   - REST API: http://localhost:19120

3. **ClickHouse 25.8** (포트 2508, 25081)
   - 웹 UI: http://localhost:2508/play
   - TCP 포트: 25081

#### 수동 실행 (SQL만)

SQL 파일을 직접 실행하려면:

```bash
# ClickHouse 클라이언트 접속
cd ../oss-mac-setup
./client.sh 2508

# SQL 파일 실행
cd ../25.8
source 01-new-parquet-reader.sql
```

### 📚 기능 상세

#### 0. MinIO Integration (06-minio-integration) ★ 추천

**새로운 기능:** ClickHouse 25.8 + MinIO S3 호환 스토리지를 통한 실전 Data Lake 구현

**테스트 내용:**
- 50,000개 이커머스 주문 데이터 생성
- MinIO로 Parquet 형식 데이터 내보내기
- S3 함수로 MinIO에서 데이터 읽기
- 컬럼 프루닝 최적화 (99.98% 적은 데이터 스캔)
- 국가별 파일 분할 및 와일드카드 쿼리
- 일일 매출 분석 (14일)
- 제품 카테고리 성능 분석
- 고객 세분화 분석 (VIP, Premium)

**실행:**
```bash
./06-minio-integration.sh
```

**주요 학습 포인트:**
- S3 호환 스토리지 (MinIO)와 ClickHouse 통합
- `s3()` 함수를 통한 데이터 읽기/쓰기
- 새로운 Parquet Reader의 실제 성능 (1.81배 빠름)
- 컬럼 프루닝을 통한 최소 데이터 스캔
- 와일드카드를 사용한 다중 파일 쿼리
- 로컬 개발 환경에서의 Data Lake 구현

**실무 활용:**
- 로컬 Data Lake 개발 및 테스트
- S3 마이그레이션 전 로컬 검증
- 비용 효율적인 데이터 저장소
- 데이터 분석 파이프라인 프로토타입
- 이커머스 매출 분석 대시보드
- 고객 행동 분석 및 세분화

**데이터셋:**
- 50,000개 주문 (8개 국가, 5,000명 고객)
- 8개 제품 카테고리
- 4가지 주문 상태
- 38M+ 총 매출

---

#### 1. New Parquet Reader (01-new-parquet-reader)

**새로운 기능:** 1.81배 빠른 성능과 99.98% 적은 데이터 스캔을 제공하는 새로운 Parquet Reader

**테스트 내용:**
- E-commerce 이벤트 데이터셋 생성 (100,000 행)
- Parquet 파일 내보내기
- 새로운 Parquet Reader로 읽기
- Column pruning 최적화 (필요한 컬럼만 읽기)
- 복잡한 분석 쿼리 성능
- 변환율 퍼널 분석
- 사용자 행동 분석
- 디바이스 및 채널 성능 분석
- 지리적 분석
- 제품 카테고리 성능
- 시간대별 활동 패턴

**실행:**
```bash
./01-new-parquet-reader.sh
# 또는
cat 01-new-parquet-reader.sql | docker exec -i clickhouse-25-8 clickhouse-client --multiline --multiquery
```

**주요 학습 포인트:**
- 새로운 Parquet Reader는 기존 대비 1.81배 빠른 성능
- Column pruning으로 99.98% 적은 데이터 스캔
- 필요한 컬럼만 읽어 메모리 효율성 향상
- Parquet v2 포맷 완전 지원
- 대규모 Parquet 파일의 메모리 사용량 감소
- 중첩된 구조체 및 배열 지원 개선

**실무 활용:**
- Data Lake 쿼리 가속화
- S3/GCS/Azure의 Parquet 파일 직접 분석
- ETL 파이프라인 최적화
- 대용량 로그 파일 분석
- 데이터 웨어하우스 연합 쿼리
- 기계 학습 특성 엔지니어링
- 실시간 분석 대시보드
- 비용 효율적인 cold storage 쿼리

**성능 비교:**
| 작업 | 이전 버전 | ClickHouse 25.8 | 개선 |
|------|----------|-----------------|------|
| 전체 Parquet 스캔 | 기준 | 1.81배 빠름 | 81% 향상 |
| 선택적 컬럼 읽기 | 많은 데이터 스캔 | 99.98% 적은 스캔 | 거의 0.02%만 스캔 |
| 메모리 사용량 | 높음 | 대폭 감소 | 효율성 향상 |

---

#### 2. Hive-Style Partitioning (02-hive-partitioning)

**새로운 기능:** partition_strategy 파라미터로 Hive-style 디렉토리 구조 지원

**테스트 내용:**
- 판매 트랜잭션 데이터 생성 (100,000 행)
- Hive-style 파티셔닝으로 데이터 내보내기 (year=YYYY/month=MM/)
- 파티션된 데이터 읽기
- 파티션 프루닝 (특정 파티션만 스캔)
- 지역별 판매 분석
- 제품 카테고리 성능
- 매장 성능 순위
- 결제 방법 분석
- 일별 판매 트렌드
- 고가치 고객 분석
- 파티션 효율성 비교
- 월별 성장률 분석

**실행:**
```bash
./02-hive-partitioning.sh
```

**주요 학습 포인트:**
- Hive partitioning: key=value 디렉토리 구조
- 파티션 프루닝으로 불필요한 디렉토리 스캔 회피
- Spark, Presto, Athena와 호환되는 표준 방식
- 다단계 파티셔닝 지원 (year/month/day)
- 자동 파티션 컬럼 감지
- 스키마 변경 없이 파티션 추가 가능
- 데이터 조직화 및 쿼리 최적화

**실무 활용:**
- Data Lake 조직화 (S3, HDFS, GCS)
- 다중 엔진 데이터 공유 (Spark + ClickHouse)
- 시계열 데이터 관리
- 지리적 데이터 파티셔닝
- 멀티 테넌트 데이터 격리
- ETL 파이프라인 최적화
- 규정 준수 데이터 보관
- 비용 효율적인 데이터 아카이빙

**파티션 패턴 예시:**
```
/data/year=2024/month=12/day=01/
/data/country=US/region=West/
/data/tenant_id=123/date=2024-12-01/
/data/event_type=purchase/hour=14/
```

**성능 이점:**
- **I/O 감소:** 관련 없는 파티션 건너뛰기
- **쿼리 속도:** 필요한 데이터만 읽기
- **조직화:** 직관적인 디렉토리 구조
- **확장성:** 페타바이트급 데이터 효율적 처리

---

#### 3. Temporary Data on S3 (03-temp-data-s3)

**새로운 기능:** 로컬 디스크 대신 S3를 임시 데이터 저장소로 사용 가능

**테스트 내용:**
- 임시 데이터 개념 이해
- S3 임시 데이터 구성 방법
- 대규모 데이터셋 생성 (500,000 이벤트)
- 대규모 JOIN 연산 (임시 저장소 사용)
- 높은 카디널리티 GROUP BY 집계
- 대규모 DISTINCT 연산
- 복잡한 윈도우 함수
- 대규모 ORDER BY 정렬
- 세션 분석 (복잡한 쿼리)
- 제품 성능 분석 (다중 JOIN)
- 사용자 코호트 분석

**실행:**
```bash
./03-temp-data-s3.sh
```

**주요 학습 포인트:**
- 임시 데이터는 쿼리 실행 중 생성됨 (JOIN, GROUP BY, ORDER BY 등)
- 25.8 이전: 로컬 디스크만 사용, 공간 제약
- 25.8 이후: S3 사용 가능, 무제한 용량
- 메모리 초과 시 자동 spillover
- 쿼리에 투명하게 동작
- S3에 최적화된 I/O 패턴
- 임시 데이터 자동 정리

**임시 데이터가 필요한 작업:**
1. 대규모 JOIN (해시 테이블)
2. 높은 카디널리티 GROUP BY
3. 대용량 데이터 정렬 (ORDER BY)
4. 윈도우 함수
5. DISTINCT 연산
6. 메모리 제한 초과 집계

**설정 예시:**
```xml
<storage_configuration>
    <disks>
        <s3_disk>
            <type>s3</type>
            <endpoint>https://bucket.s3.amazonaws.com/temp/</endpoint>
        </s3_disk>
    </disks>
</storage_configuration>
```

```sql
SET max_bytes_before_external_group_by = 10000000000;  -- 10GB
SET max_bytes_before_external_sort = 10000000000;       -- 10GB
SET temporary_data_policy = 'temp_policy';
```

**실무 활용:**
- 대규모 데이터셋 애드혹 분석
- 복잡한 다중 테이블 JOIN
- 높은 카디널리티 집계
- 데이터 탐색 및 발견
- 기계 학습 특성 엔지니어링
- 전체 데이터셋 품질 검사
- 로컬 디스크 제약 극복
- 비용 효율적인 대용량 처리

**이점:**
- 로컬 디스크 한계 초과 가능
- 더 나은 리소스 활용
- 비용 효율성 (S3가 로컬 SSD보다 저렴)
- 수동 임시 데이터 관리 불필요
- 쿼리 성공률 향상

---

#### 4. Enhanced UNION ALL with _table Virtual Column (04-union-all-table)

**새로운 기능:** UNION ALL에서 _table 가상 컬럼으로 소스 테이블 식별 가능

**테스트 내용:**
- 다중 지역 판매 테이블 생성 (US, EU, Asia, LATAM)
- 지역별 판매 데이터 삽입
- UNION ALL과 _table 컬럼 사용
- 글로벌 판매 분석
- 지역별 일별 판매 트렌드
- 지역별 제품 성능
- 고객 분포 분석
- 소스 테이블별 필터링
- 지역 간 성능 비교
- 주간 트렌드 분석
- 데이터 계보 추적
- 다중 통화 집계

**실행:**
```bash
./04-union-all-table.sh
```

**주요 학습 포인트:**
- _table 가상 컬럼이 UNION ALL 결과에서 소스 테이블 식별
- WHERE, GROUP BY, ORDER BY에서 _table 사용 가능
- 데이터 계보 추적 가능
- 소스별 집계 및 필터링
- 다중 테이블 쿼리 감사 추적
- 최소한의 오버헤드

**구문 예시:**
```sql
SELECT *, 'table1' AS _table FROM table1
UNION ALL
SELECT *, 'table2' AS _table FROM table2

-- _table로 필터링
WHERE _table = 'table1'

-- _table로 그룹화
GROUP BY _table

-- _table로 정렬
ORDER BY _table, revenue DESC
```

**실무 활용:**
- 다중 지역 데이터 통합
- 연도별 테이블 union (히스토리컬 데이터)
- 멀티 테넌트 데이터 쿼리
- 연합 쿼리 결과
- 데이터 마이그레이션 검증
- 샤드 간 분석
- 감사 및 규정 준수
- 데이터 거버넌스

**주요 이점:**
- 데이터 계보 추적
- 병합된 결과에서 소스 식별
- 소스 테이블별 필터링
- 소스별 집계
- 다중 테이블 쿼리 감사 추적
- 디버깅 및 문제 해결

---

#### 5. Data Lake Enhancements (05-data-lake-features)

**새로운 기능:** Iceberg CREATE/DROP, Delta Lake 쓰기, 시간 여행 (time travel)

**테스트 내용:**
- Data Lake 개요 및 기능 설명
- 제품 카탈로그 데이터 생성 (10,000 제품)
- Parquet 형식으로 Data Lake 내보내기
- Data Lake에서 데이터 읽기
- 버전 관리 시뮬레이션 (v1, v2, v3)
- 시간 여행 - 버전 비교
- Delta Lake 스타일 증분 업데이트
- Iceberg 스타일 파티셔닝
- 스키마 진화 시뮬레이션
- 다중 버전 쿼리
- Data Lake 메타데이터 쿼리
- 특정 시점 쿼리 (Point-in-Time)
- 버전별 감사 추적

**실행:**
```bash
./05-data-lake-features.sh
```

**주요 학습 포인트:**
- Apache Iceberg 테이블 생성/삭제
- Delta Lake 쓰기 지원
- ACID 트랜잭션 보장
- 스키마 진화 (재작성 없이)
- 시간 여행로 히스토리컬 버전 쿼리
- 버전 비교 및 감사
- 메타데이터 최적화
- 다중 포맷 통합 (Parquet, Iceberg, Delta)

**시간 여행 예시:**
```sql
-- Iceberg: 특정 시점 쿼리
SELECT * FROM iceberg_table
FOR SYSTEM_TIME AS OF '2024-12-01';

-- Delta Lake: 특정 버전 쿼리
SELECT * FROM delta_table
VERSION AS OF 42;

-- 타임스탬프 기반 쿼리
SELECT * FROM delta_table
TIMESTAMP AS OF '2024-12-01 00:00:00';
```

**실무 활용:**
- Data Lake 분석
  - S3/HDFS 직접 쿼리
  - 다중 포맷 지원
  - 파티션 프루닝

- 데이터 엔지니어링:
  - ETL 파이프라인
  - 데이터 품질 검사
  - 스키마 진화

- 데이터 과학:
  - 특성 엔지니어링
  - 히스토리컬 분석
  - 실험 추적

- 규정 준수 및 감사:
  - 시간 여행로 규정 준수
  - 감사 추적
  - 데이터 계보

- 실시간 분석:
  - 스트리밍 + 배치
  - 증분 업데이트
  - ACID 보장

**통합 예시:**
- **ClickHouse + Spark:** Iceberg 테이블 공유
- **ClickHouse + Presto:** 연합 쿼리
- **ClickHouse + Airflow:** ETL 오케스트레이션
- **ClickHouse + dbt:** 데이터 변환
- **ClickHouse + Kafka:** 스트리밍 수집

**성능 팁:**
- 대규모 데이터셋에 파티셔닝 사용
- 시간 여행을 디버깅에 활용
- 스키마 진화를 신중하게 구현
- 메타데이터 작업 모니터링
- 파티션 전략 최적화
- 압축으로 저장 효율성 향상
- 파일 크기 최적화 (128MB-1GB)

### 🔧 관리

#### ClickHouse 접속 정보

- **Web UI**: http://localhost:2508/play
- **HTTP API**: http://localhost:2508
- **TCP**: localhost:25081
- **User**: default (no password)

#### 유용한 명령어

```bash
# ClickHouse 상태 확인
cd ../oss-mac-setup
./status.sh

# CLI 접속
./client.sh 2508

# 로그 확인
docker logs clickhouse-25-8

# 중지
./stop.sh

# 완전 삭제
./stop.sh --cleanup
```

### 📂 파일 구조

```
25.8/
├── README.md                      # 이 문서
├── 00-setup.sh                    # ClickHouse 25.8 설치 스크립트
├── 01-new-parquet-reader.sh       # New Parquet Reader 테스트 실행
├── 01-new-parquet-reader.sql      # New Parquet Reader SQL
├── 02-hive-partitioning.sh        # Hive-style 파티셔닝 테스트 실행
├── 02-hive-partitioning.sql       # Hive-style 파티셔닝 SQL
├── 03-temp-data-s3.sh             # S3 임시 데이터 테스트 실행
├── 03-temp-data-s3.sql            # S3 임시 데이터 SQL
├── 04-union-all-table.sh          # UNION ALL 테스트 실행
├── 04-union-all-table.sql         # UNION ALL SQL
├── 05-data-lake-features.sh       # Data Lake 기능 테스트 실행
├── 05-data-lake-features.sql      # Data Lake 기능 SQL
├── 06-minio-integration.sh        # MinIO 통합 테스트 실행
└── 06-minio-integration.sql       # MinIO 통합 SQL
```

### 🎓 학습 경로

#### 초급 사용자
1. **00-setup.sh** - 환경 구성 이해
2. **01-new-parquet-reader** - Parquet 파일 읽기와 성능 개선 학습
3. **04-union-all-table** - 다중 테이블 통합 기초

#### 중급 사용자
1. **02-hive-partitioning** - 파티셔닝 전략 이해
2. **03-temp-data-s3** - 대용량 쿼리 최적화 학습
3. **05-data-lake-features** - Data Lake 통합 탐색

#### 고급 사용자
- 모든 기능을 조합하여 엔드투엔드 Data Lake 파이프라인 구현
- 실제 프로덕션 시나리오 설계
- 성능 벤치마킹 및 최적화
- 다중 엔진 통합 (Spark, Presto, ClickHouse)

### 💡 기능 비교

#### ClickHouse 25.8 vs Previous Versions

| Feature | Before 25.8 | ClickHouse 25.8 | Improvement |
|---------|-------------|-----------------|-------------|
| Parquet Reader | Standard | 1.81x faster | 81% faster |
| Parquet Column Pruning | Basic | 99.98% less scan | Drastically reduced I/O |
| Hive Partitioning | Manual | Native support | Standard compatibility |
| Temporary Data | Local disk only | S3 support | Unlimited capacity |
| UNION ALL | Basic | _table column | Source tracking |
| Iceberg Tables | Read-only | CREATE/DROP | Full management |
| Delta Lake | Read-only | Write support | Bidirectional |
| Time Travel | Limited | Full support | Historical queries |

#### Performance Comparison

| Operation | Previous | ClickHouse 25.8 | Benefit |
|-----------|----------|-----------------|---------|
| Parquet full scan | Baseline | 1.81x faster | Speed |
| Parquet selective columns | Many bytes | 0.02% of data | I/O efficiency |
| Hive partition query | Full scan | Partition pruning | Reduced scanning |
| Large JOIN | Memory limited | S3 spillover | Unlimited capacity |
| Multi-table union | No tracking | Source identification | Data lineage |
| Data Lake writes | Limited | Full ACID | Data integrity |

### 🔍 추가 자료

- **Official Release Blog**: [ClickHouse 25.8 Release](https://clickhouse.com/blog/clickhouse-release-25-08)
- **ClickHouse Documentation**: [docs.clickhouse.com](https://clickhouse.com/docs)
- **Release Notes**: [Changelog 2025](https://clickhouse.com/docs/whats-new/changelog)
- **GitHub Repository**: [ClickHouse GitHub](https://github.com/ClickHouse/ClickHouse)
- **Data Lake Formats**:
  - [Apache Iceberg](https://iceberg.apache.org/)
  - [Delta Lake](https://delta.io/)
  - [Apache Parquet](https://parquet.apache.org/)

### 📝 참고사항

- 각 스크립트는 독립적으로 실행 가능합니다
- SQL 파일을 직접 읽고 수정하여 실험해보세요
- 테스트 데이터는 각 SQL 파일 내에서 생성됩니다
- 정리(cleanup)는 기본적으로 주석 처리되어 있습니다
- 프로덕션 환경 적용 전 충분한 테스트를 권장합니다
- Data Lake 기능은 적절한 스토리지 구성이 필요할 수 있습니다

### 🔒 보안 고려사항

**Data Lake 접근 시:**
- S3/GCS/Azure 자격 증명을 안전하게 관리
- 환경 변수 또는 IAM 역할 사용
- 데이터 암호화 (전송 중 및 저장 시)
- 접근 제어 및 권한 관리
- 감사 로깅 활성화

**임시 데이터 사용 시:**
- S3 버킷 액세스 제어
- 임시 데이터 자동 정리 설정
- 비용 모니터링
- 네트워크 대역폭 고려

### ⚡ 성능 팁

**Parquet Reader 최적화:**
- 필요한 컬럼만 SELECT
- WHERE 조건으로 행 필터링
- 적절한 파일 크기 유지 (128MB-1GB)
- 압축 알고리즘 선택 (Snappy, ZSTD)

**Hive Partitioning 최적화:**
- 쿼리 패턴에 맞는 파티션 키 선택
- 파티션 수를 적절히 유지 (너무 많거나 적지 않게)
- 파티션 키를 WHERE 조건에 포함
- 파티션 프루닝 활용

**임시 데이터 최적화:**
- 적절한 메모리 임계값 설정
- 오프피크 시간에 대용량 작업 수행
- S3 사용 비용 모니터링
- 로컬 캐시 활용

**UNION ALL 최적화:**
- _table 컬럼으로 파티션 프루닝
- 불필요한 테이블 제외
- 인덱스 키 활용

**Data Lake 최적화:**
- 시계열 데이터는 날짜로 파티셔닝
- 메타데이터 캐싱 활용
- 파일 크기 최적화
- Predicate pushdown 활용

### 🚀 프로덕션 배포

#### Best Practices

```sql
-- 파티션 정보 확인
SELECT
    partition,
    name,
    rows,
    bytes_on_disk
FROM system.parts
WHERE table = 'your_table'
  AND active = 1;

-- 실행 중인 쿼리 모니터링
SELECT
    query_id,
    user,
    query,
    elapsed,
    memory_usage
FROM system.processes
WHERE query NOT LIKE '%system.processes%';

-- 디스크 사용량 확인
SELECT
    name,
    path,
    formatReadableSize(free_space) AS free,
    formatReadableSize(total_space) AS total
FROM system.disks;
```

### 🛠 관리 명령어

#### ClickHouse 관리

```bash
# ClickHouse 상태 확인
cd ../oss-mac-setup
./status.sh

# ClickHouse CLI 접속
./client.sh 2508

# ClickHouse 중지
./stop.sh

# ClickHouse 재시작
./start.sh
```

#### Data Lake (MinIO + Nessie) 관리

```bash
# MinIO 웹 콘솔 접속
# 브라우저에서: http://localhost:19001
# 자격증명: admin / password123

# MinIO 및 Nessie 중지
cd ../datalake-minio-catalog
docker-compose down

# MinIO 및 Nessie 재시작
docker-compose up -d minio nessie minio-setup

# MinIO 데이터 완전 삭제
docker-compose down -v

# 컨테이너 로그 확인
docker-compose logs -f minio
docker-compose logs -f nessie
```

#### 전체 환경 재구성

```bash
# 1. 모든 서비스 중지 및 정리
cd ../oss-mac-setup
./stop.sh

cd ../datalake-minio-catalog
docker-compose down -v

# 2. 전체 재시작
cd ../25.8
./00-setup.sh
```

#### 데이터 확인

```bash
# MinIO에 저장된 파일 확인
docker exec -it minio mc ls myminio/warehouse/

# ClickHouse 테이블 확인
docker exec -it clickhouse-25-8 clickhouse-client -q "SHOW TABLES"

# ClickHouse 데이터베이스 크기 확인
docker exec -it clickhouse-25-8 clickhouse-client -q "SELECT database, formatReadableSize(sum(bytes)) as size FROM system.parts GROUP BY database"
```

#### 마이그레이션 전략

1. **테스트 환경에서 검증**
   - 모든 새 기능 테스트
   - 성능 벤치마킹
   - 롤백 계획 수립

2. **점진적 롤아웃**
   - 작은 데이터셋부터 시작
   - 모니터링 및 성능 측정
   - 문제 발생 시 즉시 대응

3. **모니터링**
   - 쿼리 성능 추적
   - 리소스 사용량 모니터링
   - 에러 및 경고 확인

### 🤝 기여

이 랩에 대한 개선 사항이나 추가 예제가 있다면:
1. 이슈 등록
2. Pull Request 제출
3. 피드백 공유

### 📄 라이선스

MIT License - 자유롭게 학습 및 수정 가능

---

**Happy Learning! 🚀**

질문이나 이슈가 있으면 메인 [clickhouse-hols README](../../README.md)를 참조하세요.
