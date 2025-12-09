# ClickHouse Hands-On Labs (HOLs)

[English](#english) | [한국어](#한국어)

---

## English

A collection of practical, hands-on laboratory exercises for learning and exploring ClickHouse - the fast open-source column-oriented database management system.

## 🎯 Purpose

These hands-on labs are designed to provide practical experience with:
- **ClickHouse OSS** (Open Source Software)
- **ClickHouse Cloud** (Managed service)

Whether you're a beginner learning ClickHouse fundamentals or an experienced user exploring advanced features, these labs offer structured, step-by-step exercises to build your skills with real-world scenarios.

## 📁 Repository Structure

```
clickhouse-hols/
├── local/          # Local environment setups
│   ├── oss-mac-setup/           # ClickHouse OSS on macOS
│   └── datalake-minio-catalog/  # Local data lake with MinIO
├── chc/            # ClickHouse Cloud integrations
│   ├── api/        # API testing and integration
│   ├── kafka/      # Kafka/Confluent integrations
│   ├── lake/       # Data lake integrations (Glue, MinIO)
│   └── s3/         # S3 integration examples
├── tpcds/          # TPC-DS benchmark
└── workload/       # Performance testing workloads
    ├── sql-lab-delete-benchmark/  # DELETE operation benchmark
    └── sql-lab-gnome-variants/    # Genomics data workload
```

## 📚 Available Labs

### 🏠 Local Environment (`local/`)

#### 1. [local/oss-mac-setup](local/oss-mac-setup/)
**Purpose:** Quick setup for running ClickHouse OSS (Open Source) on macOS

Development environment optimized for macOS with Docker, featuring:
- Custom seccomp security profile to fix `get_mempolicy` errors on macOS
- Version control with support for specific ClickHouse versions or latest
- Docker named volumes for persistent data storage
- Easy management scripts for start/stop/cleanup operations
- Multiple access interfaces (Web UI, HTTP API, TCP)

**Quick Start:**
```bash
cd local/oss-mac-setup
./set.sh        # Setup with latest version
./start.sh      # Start ClickHouse
./client.sh     # Connect to CLI
```

---

#### 2. [local/25.6](local/25.6/) - ClickHouse 25.6 New Features
**Purpose:** Learn and test ClickHouse 25.6 new features

Features tested:
- CoalescingMergeTree table engine
- Time and Time64 data types
- Bech32 encoding functions
- lag/lead window functions
- Consistent snapshot across queries

**Quick Start:**
```bash
cd local/25.6
./00-setup.sh  # Deploy ClickHouse 25.6
./01-coalescingmergetree.sh
./02-time-datatypes.sh
```

---

#### 3. [local/25.7](local/25.7/) - ClickHouse 25.7 New Features
**Purpose:** Learn and test ClickHouse 25.7 new features

Features tested:
- SQL UPDATE/DELETE operations (up to 1000x faster)
- count() aggregation optimization (20-30% faster)
- JOIN performance improvements (up to 1.8x faster)
- Bulk UPDATE performance

**Quick Start:**
```bash
cd local/25.7
./00-setup.sh  # Deploy ClickHouse 25.7
./01-sql-update-delete.sh
```

---

#### 4. [local/25.8](local/25.8/) - ClickHouse 25.8 New Features
**Purpose:** Learn and test ClickHouse 25.8 new features with MinIO Data Lake integration

Features tested:
- **New Parquet Reader** (1.81x faster, 99.98% less data scanned)
- **MinIO Integration** (S3-compatible storage)
- Column pruning optimization
- Multiple file querying with wildcards
- E-commerce analytics on data lake
- Data Lake enhancements (Iceberg, Delta Lake concepts)

**Quick Start:**
```bash
cd local/25.8
./00-setup.sh              # Deploys ClickHouse 25.8 + MinIO + Nessie
./06-minio-integration.sh  # Test MinIO S3-compatible storage
```

**What's Included:**
- Automatic MinIO and Nessie deployment
- 50,000 sample e-commerce orders
- Parquet export/import tests
- Daily sales analytics
- Customer segmentation analysis

---

#### 5. [local/25.9](local/25.9/) - ClickHouse 25.9 New Features
**Purpose:** Learn and test ClickHouse 25.9 new features

Features tested:
- **Automatic Global Join Reordering** (statistics-based join optimization)
- **New Text Index** (experimental full-text search)
- **Streaming Secondary Indices** (faster query startup)
- **arrayExcept Function** (efficient array filtering)

**Quick Start:**
```bash
cd local/25.9
./00-setup.sh              # Deploy ClickHouse 25.9
./01-join-reordering.sh    # Test join optimization
./02-text-index.sh         # Test full-text search
./03-streaming-indices.sh  # Test streaming indices
./05-array-except.sh       # Test array function
```

---

#### 6. [local/25.10](local/25.10/) - ClickHouse 25.10 New Features
**Purpose:** Learn and test ClickHouse 25.10 new features

Features tested:
- QBit data type for vector search
- Negative LIMIT/OFFSET
- JOIN improvements
- LIMIT BY ALL
- Auto statistics

---

#### 7. [local/datalake-minio-catalog](local/datalake-minio-catalog/)
**Purpose:** Local data lake environment with MinIO and multiple catalog options

Complete data lake stack running locally with Docker:
- **MinIO**: S3-compatible object storage for data lake storage
- **Multiple Catalog Options**: Nessie (Git-like), Hive Metastore, or Iceberg REST
- **Apache Iceberg**: Modern table format with ACID guarantees
- **Jupyter Notebooks**: Interactive data exploration with pre-configured examples
- **Sample Data**: Pre-loaded JSON and Parquet datasets

**Quick Start:**
```bash
cd local/datalake-minio-catalog
./setup.sh --configure  # Choose catalog type
./setup.sh --start      # Start all services
# Access Jupyter at http://localhost:8888
# Access MinIO Console at http://localhost:9001
```

---

### ☁️ ClickHouse Cloud Integration (`chc/`)

#### API Testing

##### [chc/api/chc-api-test](chc/api/chc-api-test/)
**Purpose:** ClickHouse Cloud API testing and integration examples

Comprehensive API testing suite for ClickHouse Cloud:
- REST API examples with Python
- Authentication and connection handling
- Query execution and result processing
- Performance testing and monitoring

**Quick Start:**
```bash
cd chc/api/chc-api-test
cp .env.example .env
# Edit .env with your CHC credentials
python3 apitest.py
```

---

#### Kafka/Confluent Integration

##### [chc/kafka/terraform-confluent-aws](chc/kafka/terraform-confluent-aws/)
**Purpose:** Confluent Cloud Kafka integration with ClickHouse Cloud

##### [chc/kafka/terraform-confluent-aws-nlb-ssl](chc/kafka/terraform-confluent-aws-nlb-ssl/)
**Purpose:** Secure Kafka connection using AWS NLB with SSL/TLS

##### [chc/kafka/terraform-confluent-aws-connect-sink](chc/kafka/terraform-confluent-aws-connect-sink/)
**Purpose:** Kafka Connect Sink connector for streaming data to ClickHouse Cloud

---

#### Data Lake Integration

##### [chc/lake/terraform-minio-on-aws](chc/lake/terraform-minio-on-aws/)
**Purpose:** Deploy single-node MinIO server on AWS EC2 with Terraform

Production-ready MinIO deployment on AWS infrastructure:
- Ubuntu 22.04 LTS with automated deployment
- Configurable instance type and EBS volume size
- Security groups and optional Elastic IP
- Health monitoring and installation logs

**Quick Start:**
```bash
cd chc/lake/terraform-minio-on-aws
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
./deploy.sh   # Automated deployment
```

---

##### [chc/lake/terraform-glue-s3-chc-integration](chc/lake/terraform-glue-s3-chc-integration/)
**Created:** November 2025
**Purpose:** ClickHouse Cloud integration with AWS Glue Catalog using Apache Iceberg

**⚠️ Important:** This lab demonstrates ClickHouse Cloud 25.8's current DataLakeCatalog capabilities with known limitations.

Automated infrastructure for ClickHouse Cloud + AWS Glue + Iceberg integration:
- **S3 Storage**: Encrypted bucket for Apache Iceberg data
- **AWS Glue Database**: Metadata catalog for Iceberg tables
- **PyIceberg**: Proper Iceberg v2 table creation with Glue catalog support
- **Sample Data**: Pre-configured `sales_orders` table with partitioning
- **One-Command Deployment**: Automated setup with `deploy.sh`
- **Credential Management**: Secure environment variable handling

**Current Limitations (ClickHouse Cloud 25.8):**
- ❌ `glue_database` parameter not supported in DataLakeCatalog
- ❌ IAM role-based authentication not supported (must use access keys)
- ✅ DataLakeCatalog automatically discovers all Glue databases in the region

**Future Enhancements:** Once ClickHouse Cloud adds support for `glue_database` and IAM roles, this setup will be updated accordingly.

**Use Cases:**
- Integrating ClickHouse Cloud with AWS Glue Data Catalog
- Querying Apache Iceberg tables from ClickHouse
- Database-level catalog integration (mount entire Glue database)
- Testing DataLakeCatalog engine capabilities and limitations

**Quick Start:**
```bash
cd terraform-glue-s3-chc-integration
./deploy.sh  # Prompts for AWS credentials, deploys everything
# Copy the SQL output and run in ClickHouse Cloud console
./destroy.sh # Cleanup when done
```

**Technical Architecture:**
```
ClickHouse Cloud (DataLakeCatalog)
    ↓ (AWS Credentials)
AWS Glue Catalog (clickhouse_iceberg_db)
    ↓ (Table Metadata)
S3 Bucket (Apache Iceberg Data)
    ↓ (Parquet Files)
Sample Table: sales_orders (10 records, partitioned by date)
```

**Quick Start:**
```bash
cd chc/lake/terraform-glue-s3-chc-integration
./deploy.sh  # Prompts for AWS credentials, deploys everything
```

---

#### S3 Integration

##### [chc/s3/terraform-chc-secures3-aws](chc/s3/terraform-chc-secures3-aws/)
**Purpose:** Secure ClickHouse Cloud S3 integration using IAM role-based authentication

Production-ready S3 access for ClickHouse Cloud:
- IAM role-based authentication (no access keys)
- Read & write permissions for SELECT, INSERT, export
- S3 Table Engine support
- Multiple format support (Parquet, CSV, JSON)
- Encryption, versioning, and security

**Quick Start:**
```bash
cd chc/s3/terraform-chc-secures3-aws
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
./deploy.sh   # Interactive deployment
```

---

##### [chc/s3/terraform-chc-secures3-aws-direct-attach](chc/s3/terraform-chc-secures3-aws-direct-attach/)
**Purpose:** Direct IAM policy attachment for ClickHouse Cloud S3 access

Alternative approach using direct policy attachment to ClickHouse Cloud IAM role.

---

### 📊 Benchmarks & Workloads

#### [tpcds/](tpcds/)
**Purpose:** TPC-DS benchmark for ClickHouse performance testing

Industry-standard decision support benchmark:
- Complete TPC-DS schema with 24 tables
- 99 analytical query templates
- Automated data generation and loading
- Sequential and parallel query execution
- Performance metrics and analysis

**Quick Start:**
```bash
cd tpcds
./00-set.sh --interactive
./01-create-schema.sh
./03-load-data.sh --source s3
./04-run-queries-sequential.sh
```

---

### 🔬 Performance Testing (`workload/`)

#### [workload/sql-lab-delete-benchmark](workload/sql-lab-delete-benchmark/)
**Purpose:** DELETE operation performance benchmark

Comprehensive DELETE operation testing:
- Various DELETE patterns and scenarios
- Performance metrics collection
- Comparison of different deletion strategies
- Impact analysis on query performance

**Quick Start:**
```bash
cd workload/sql-lab-delete-benchmark
# Execute SQL scripts in order: 01 through 05
```

---

#### [workload/sql-lab-gnome-variants](workload/sql-lab-gnome-variants/)
**Purpose:** Genomics data workload testing

Real-world genomics data processing scenarios:
- Genome variant analysis
- Large-scale genomics data handling
- Performance optimization for scientific workloads

**Quick Start:**
```bash
cd workload/sql-lab-gnome-variants
# Execute SQL scripts in order: 01 through 05
```

---

## 🛠 Prerequisites

### General Requirements
- macOS, Linux, or Windows with WSL2
- Docker and Docker Compose
- Basic command-line knowledge

### Specific Requirements
- **Local Labs**: Docker Desktop, Python 3.8+
- **Cloud Labs**: Terraform, AWS CLI, AWS account
- **ClickHouse Cloud Labs**: ClickHouse Cloud account
- **Benchmarks**: ClickHouse client, sufficient disk space

## 🚀 Getting Started

1. **Clone this repository:**
   ```bash
   git clone https://github.com/yourusername/clickhouse-hols.git
   cd clickhouse-hols
   ```

2. **Choose a lab** from the list above based on your learning goals

3. **Follow the Quick Start** instructions in each lab's directory

4. **Read the detailed README** in each lab for comprehensive documentation

## 📖 Learning Path

### For Beginners
1. **[local/oss-mac-setup](local/oss-mac-setup/)** - Learn ClickHouse basics locally
2. **[local/datalake-minio-catalog](local/datalake-minio-catalog/)** - Explore data lake concepts
3. **[tpcds](tpcds/)** - Understand performance and benchmarking

### For Cloud Users
1. **[chc/api/chc-api-test](chc/api/chc-api-test/)** - Learn ClickHouse Cloud API
2. **[chc/s3/terraform-chc-secures3-aws](chc/s3/terraform-chc-secures3-aws/)** - Secure S3 integration
3. **[chc/lake/terraform-glue-s3-chc-integration](chc/lake/terraform-glue-s3-chc-integration/)** - AWS Glue integration

### For Advanced Users
1. **[chc/kafka](chc/kafka/)** - Real-time data streaming
2. **[workload](workload/)** - Performance testing and optimization

## 🤝 Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## 📝 License

MIT License - See individual lab directories for specific license information.

---

## 한국어

ClickHouse 학습 및 탐구를 위한 실무적이고 실용적인 실습 환경 모음입니다.

### 🎯 목적

이 실습은 다음을 통한 실무 경험을 제공합니다:
- **ClickHouse OSS** (오픈소스 소프트웨어)
- **ClickHouse Cloud** (관리형 서비스)

초보자가 ClickHouse 기본을 배우거나 고급 기능을 탐구하는 숙련된 사용자 모두를 위해, 이 실습은 실제 시나리오와 함께 단계별 구조화된 연습을 제공합니다.

### 📁 저장소 구조

```
clickhouse-hols/
├── local/          # 로컬 환경 설정
│   ├── oss-mac-setup/           # macOS용 ClickHouse OSS
│   └── datalake-minio-catalog/  # MinIO를 사용한 로컬 데이터 레이크
├── chc/            # ClickHouse Cloud 통합
│   ├── api/        # API 테스트 및 통합
│   ├── kafka/      # Kafka/Confluent 통합
│   ├── lake/       # 데이터 레이크 통합 (Glue, MinIO)
│   ├── tool/       # 도구 (costkeeper, ch2otel)
│   └── s3/         # S3 통합 예제
├── tpcds/          # TPC-DS 벤치마크
├── usecase/        # 사용 사례 (customer360)
└── workload/       # 성능 테스트 워크로드
    ├── delete-benchmark/  # DELETE 작업 벤치마크
    └── projection/        # Projection 성능 테스트
```

### 📚 사용 가능한 실습

#### 🏠 로컬 환경 (`local/`)

##### 1. [local/oss-mac-setup](local/oss-mac-setup/)
**목적:** macOS에서 ClickHouse OSS (오픈소스) 실행을 위한 빠른 설정

macOS용으로 최적화된 Docker를 사용한 개발 환경:
- macOS에서 `get_mempolicy` 오류를 해결하기 위한 사용자 정의 seccomp 보안 프로필
- 특정 ClickHouse 버전 또는 최신 버전 지원을 통한 버전 관리
- 지속적인 데이터 저장을 위한 Docker 명명된 볼륨
- 시작/중지/정리 작업을 위한 간편한 관리 스크립트
- 다중 액세스 인터페이스 (Web UI, HTTP API, TCP)

##### 2. [local/25.6](local/25.6/) - ClickHouse 25.6 신기능
**목적:** ClickHouse 25.6 신기능 학습 및 테스트

##### 3. [local/25.7](local/25.7/) - ClickHouse 25.7 신기능
**목적:** ClickHouse 25.7 신기능 학습 및 테스트

##### 4. [local/25.8](local/25.8/) - ClickHouse 25.8 신기능
**목적:** MinIO 데이터 레이크 통합을 통한 ClickHouse 25.8 신기능 학습 및 테스트

##### 5. [local/25.9](local/25.9/) - ClickHouse 25.9 신기능
**목적:** ClickHouse 25.9 신기능 학습 및 테스트

##### 6. [local/datalake-minio-catalog](local/datalake-minio-catalog/)
**목적:** MinIO 및 다중 카탈로그 옵션을 사용한 로컬 데이터 레이크 환경

Docker를 사용하여 로컬에서 실행되는 완전한 데이터 레이크 스택:
- **MinIO**: 데이터 레이크 저장소를 위한 S3 호환 객체 스토리지
- **다중 카탈로그 옵션**: Nessie (Git-like), Hive Metastore, 또는 Iceberg REST
- **Apache Iceberg**: ACID 보장을 제공하는 최신 테이블 형식
- **Jupyter Notebooks**: 사전 구성된 예제를 통한 대화형 데이터 탐색
- **샘플 데이터**: 사전 로드된 JSON 및 Parquet 데이터셋

#### ☁️ ClickHouse Cloud 통합 (`chc/`)

##### 도구 (`chc/tool/`)

###### [chc/tool/costkeeper](chc/tool/costkeeper/)
**목적:** ClickHouse Cloud 비용 모니터링 및 알림 시스템

ClickHouse Cloud의 비용과 리소스 사용량을 실시간으로 모니터링하고 이상 징후 발생 시 자동으로 Alert를 생성하는 시스템:
- 100% ClickHouse Cloud 네이티브 (Refreshable Materialized View 기반)
- 15분 단위 메트릭 수집 (데이터 손실 방지)
- 실시간 비용 모니터링 및 효율성 분석
- 자동 Alert 시스템 (INFO, WARNING, CRITICAL 3단계)

###### [chc/tool/ch2otel](chc/tool/ch2otel/)
**목적:** ClickHouse 시스템 메트릭을 OpenTelemetry로 자동 변환

ClickHouse Cloud 시스템 메트릭과 로그를 OpenTelemetry 표준 형식으로 자동 변환:
- 자동 변환 - 시스템 메트릭을 OTEL 형식으로 변환
- 표준 준수 - OpenTelemetry Logs, Traces, Metrics 완전 지원
- 자기 서비스 - Collector 불필요, CHC 내부에서 완전 동작

##### API 테스트

###### [chc/api/chc-api-test](chc/api/chc-api-test/)
**목적:** ClickHouse Cloud API 테스트 및 통합 예제

#### Kafka/Confluent 통합

###### [chc/kafka/](chc/kafka/)
ClickHouse Cloud와 Kafka 통합을 위한 다양한 시나리오

##### 데이터 레이크 통합

###### [chc/lake/terraform-glue-s3-chc-integration](chc/lake/terraform-glue-s3-chc-integration/)
**목적:** Apache Iceberg를 사용한 ClickHouse Cloud와 AWS Glue Catalog 통합

##### S3 통합

###### [chc/s3/terraform-chc-secures3-aws](chc/s3/terraform-chc-secures3-aws/)
**목적:** IAM 역할 기반 인증을 사용한 안전한 ClickHouse Cloud S3 통합

### 📊 벤치마크 및 워크로드

#### [tpcds/](tpcds/)
**목적:** ClickHouse 성능 테스트를 위한 TPC-DS 벤치마크

#### [workload/delete-benchmark](workload/delete-benchmark/)
**목적:** DELETE 작업 성능 벤치마크

#### [workload/projection](workload/projection/)
**목적:** Projection 성능 테스트 및 학습

#### [usecase/customer360](usecase/customer360/)
**목적:** 대규모 고객 360도 분석 종합 실습

### 🛠 사전 요구사항

#### 일반 요구사항
- macOS, Linux, 또는 WSL2를 사용하는 Windows
- Docker 및 Docker Compose
- 기본 명령줄 지식

#### 특정 요구사항
- **로컬 실습**: Docker Desktop, Python 3.8+
- **클라우드 실습**: Terraform, AWS CLI, AWS 계정
- **ClickHouse Cloud 실습**: ClickHouse Cloud 계정
- **벤치마크**: ClickHouse client, 충분한 디스크 공간

### 🚀 시작하기

1. **이 저장소 복제:**
   ```bash
   git clone https://github.com/yourusername/clickhouse-hols.git
   cd clickhouse-hols
   ```

2. **학습 목표에 따라 실습 선택**

3. **각 실습 디렉토리의 빠른 시작 지침 따르기**

4. **종합 문서를 위한 각 실습의 상세한 README 읽기**

### 📖 학습 경로

#### 초보자를 위한 경로
1. **[local/oss-mac-setup](local/oss-mac-setup/)** - 로컬에서 ClickHouse 기본 학습
2. **[local/datalake-minio-catalog](local/datalake-minio-catalog/)** - 데이터 레이크 개념 탐색
3. **[tpcds](tpcds/)** - 성능 및 벤치마킹 이해

#### 클라우드 사용자를 위한 경로
1. **[chc/api/chc-api-test](chc/api/chc-api-test/)** - ClickHouse Cloud API 학습
2. **[chc/s3/terraform-chc-secures3-aws](chc/s3/terraform-chc-secures3-aws/)** - 안전한 S3 통합
3. **[chc/lake/terraform-glue-s3-chc-integration](chc/lake/terraform-glue-s3-chc-integration/)** - AWS Glue 통합

#### 고급 사용자를 위한 경로
1. **[chc/kafka](chc/kafka/)** - 실시간 데이터 스트리밍
2. **[workload](workload/)** - 성능 테스트 및 최적화
3. **[chc/tool/costkeeper](chc/tool/costkeeper/)** - 비용 모니터링 및 최적화

### 🤝 기여

기여를 환영합니다! 문제를 제출하거나 풀 리퀘스트를 자유롭게 제출해 주세요.

### 📝 라이선스

MIT License - 특정 라이선스 정보는 각 실습 디렉토리를 참조하세요.

### 📚 추가 리소스

ClickHouse에 대한 더 많은 정보와 한국어 리소스는 [clickhouse.kr](https://clickhouse.kr)에서 확인하실 수 있습니다.

