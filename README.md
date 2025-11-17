# ClickHouse Hands-On Labs (HOLs)

A collection of practical, hands-on laboratory exercises for learning and exploring ClickHouse - the fast open-source column-oriented database management system.

## 🎯 Purpose

These hands-on labs are designed to provide practical experience with:
- **ClickHouse OSS** (Open Source Software)
- **ClickHouse Cloud** (Managed service)

Whether you're a beginner learning ClickHouse fundamentals or an experienced user exploring advanced features, these labs offer structured, step-by-step exercises to build your skills with real-world scenarios.

## 📚 Available Labs

### 1. [oss-mac-setup](oss-mac-setup/)
**Created:** November 2025
**Purpose:** Quick setup for running ClickHouse OSS (Open Source) on macOS

Development environment optimized for macOS with Docker, featuring:
- Custom seccomp security profile to fix `get_mempolicy` errors on macOS
- Version control with support for specific ClickHouse versions or latest
- Docker named volumes for persistent data storage
- Easy management scripts for start/stop/cleanup operations
- Multiple access interfaces (Web UI, HTTP API, TCP)

**Use Cases:**
- Local ClickHouse development on macOS
- Testing ClickHouse features before cloud deployment
- Learning ClickHouse fundamentals in a safe local environment

**Quick Start:**
```bash
cd oss-mac-setup
./set.sh        # Setup with latest version
./start.sh      # Start ClickHouse
./client.sh     # Connect to CLI
```

---

### 2. [tpcds](tpcds/)
**Created:** November 2025 *(Under Development)*
**Purpose:** TPC-DS benchmark for ClickHouse performance testing

Industry-standard decision support benchmark for evaluating ClickHouse performance:
- Complete TPC-DS schema with 24 tables (7 fact tables, 17 dimension tables)
- 99 analytical query templates covering various patterns
- Automated data generation and loading scripts
- Sequential and parallel query execution
- Performance metrics and result analysis

**Use Cases:**
- Benchmarking ClickHouse performance at different scale factors
- Testing query optimization and tuning
- Comparing performance across different ClickHouse versions or configurations
- Stress testing production environments

**Quick Start:**
```bash
cd tpcds
./00-set.sh --interactive     # Configure environment
./01-create-schema.sh         # Create schema
./03-load-data.sh --source s3 # Load data from S3
./04-run-queries-sequential.sh # Run benchmark
```

---

### 3. [datalake-minio-catalog](datalake-minio-catalog/)
**Created:** November 2025
**Purpose:** Local data lake environment with MinIO and multiple catalog options

Complete data lake stack running locally with Docker:
- **MinIO**: S3-compatible object storage for data lake storage
- **Multiple Catalog Options**: Nessie (Git-like), Hive Metastore, or Iceberg REST
- **Apache Iceberg**: Modern table format with ACID guarantees
- **Jupyter Notebooks**: Interactive data exploration with pre-configured examples
- **Sample Data**: Pre-loaded JSON and Parquet datasets

**Use Cases:**
- Learning data lake architecture and Apache Iceberg concepts
- Testing ClickHouse integration with S3-compatible storage
- Experimenting with different catalog implementations
- Prototyping data lake solutions before cloud deployment

**Quick Start:**
```bash
cd datalake-minio-catalog
./setup.sh --configure  # Choose catalog type
./setup.sh --start      # Start all services
# Access Jupyter at http://localhost:8888
# Access MinIO Console at http://localhost:9001
```

---

### 4. [terraform-minio-on-aws](terraform-minio-on-aws/)
**Created:** November 2025
**Purpose:** Deploy single-node MinIO server on AWS EC2 with Terraform

Production-ready MinIO deployment on AWS infrastructure:
- **Ubuntu 22.04 LTS**: Following MinIO's official recommendations
- **Automated Deployment**: One-command deployment with `deploy.sh`
- **Configurable Resources**: Instance type and EBS volume size
- **Security Groups**: Pre-configured firewall rules for MinIO API/Console/SSH
- **Optional Elastic IP**: Stable public IP for production use
- **Health Monitoring**: Automated health checks and detailed installation logs

**Use Cases:**
- Deploying S3-compatible object storage on AWS
- Creating MinIO infrastructure for ClickHouse Cloud integration
- Testing ClickHouse S3 functions with real cloud storage
- Cost-effective alternative to AWS S3 for specific workloads

**Quick Start:**
```bash
cd terraform-minio-on-aws
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
./deploy.sh   # Automated deployment
./destroy.sh  # Cleanup when done
```

---

### 5. [terraform-glue-s3-chc-integration](terraform-glue-s3-chc-integration/)
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

---

## 🛠 Prerequisites

### General Requirements
- macOS, Linux, or Windows with WSL2
- Docker and Docker Compose
- Basic command-line knowledge

### Specific Requirements by Lab
- **oss-mac-setup**: Docker Desktop for Mac
- **tpcds**: ClickHouse client, bash, sufficient disk space
- **datalake-minio-catalog**: Python 3.8+, 20GB+ disk space
- **terraform-minio-on-aws**: Terraform, AWS CLI, AWS account, EC2 key pair
- **terraform-glue-s3-chc-integration**: Terraform, AWS CLI, AWS account, ClickHouse Cloud account

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

**Recommended progression for beginners:**

1. **Start with [oss-mac-setup](oss-mac-setup/)** → Learn basic ClickHouse operations locally
2. **Try [datalake-minio-catalog](datalake-minio-catalog/)** → Understand data lake concepts and S3 integration
3. **Explore [tpcds](tpcds/)** → Learn about ClickHouse performance and query optimization
4. **Deploy [terraform-minio-on-aws](terraform-minio-on-aws/)** → Experience cloud infrastructure deployment
5. **Advanced: [terraform-glue-s3-chc-integration](terraform-glue-s3-chc-integration/)** → Master ClickHouse Cloud + AWS integration

## 🇰🇷 한국어 정보 (Korean Information)

ClickHouse에 대한 더 많은 정보와 한국어 리소스는 [clickhouse.kr](https://clickhouse.kr)에서 확인하실 수 있습니다.

If you are Korean, you can get more information from [clickhouse.kr](https://clickhouse.kr).

## 🤝 Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## 📝 License

MIT License - See individual lab directories for specific license information.

