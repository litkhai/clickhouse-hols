# ClickHouse Hands-On Labs (HOLs)

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

#### 5. [local/25.10](local/25.10/) - ClickHouse 25.10 New Features
**Purpose:** Learn and test ClickHouse 25.10 new features

Features tested:
- QBit data type for vector search
- Negative LIMIT/OFFSET
- JOIN improvements
- LIMIT BY ALL
- Auto statistics

---

#### 6. [local/datalake-minio-catalog](local/datalake-minio-catalog/)
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

## 🇰🇷 한국어 문서 (Korean Documentation)

한국어 사용자를 위한 상세한 문서는 [README.ko.md](README.ko.md)를 참조하세요.

For detailed Korean documentation, please refer to [README.ko.md](README.ko.md).

ClickHouse에 대한 더 많은 정보와 한국어 리소스는 [clickhouse.kr](https://clickhouse.kr)에서 확인하실 수 있습니다.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## 📝 License

MIT License - See individual lab directories for specific license information.

