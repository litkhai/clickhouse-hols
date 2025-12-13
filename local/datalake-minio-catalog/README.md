# Data Lake with MinIO and Multiple Catalogs

**English** | [한국어](README.ko.md)

A complete setup for running a local data lake environment with MinIO object storage and 5 data catalogs: Nessie, Hive Metastore, Iceberg REST, Polaris, and Unity Catalog.

**🔗 Integrated with:** [ClickHouse 25.8+ Labs](../25.8/) - Fully tested with ClickHouse 25.10 and 25.11

---

## 🚀 Quick Start

### Method 1: Single Catalog (setup.sh)

Recommended for focused work with one catalog

```bash
# 1. Configure (select 1 catalog)
./setup.sh --configure

# 2. Start
./setup.sh --start

# 3. Try example
./examples/basic-s3-read-write.sh
```

### Method 2: Multiple Catalogs (setup-multi-catalog.sh)

Recommended for comparing/testing multiple catalogs simultaneously

```bash
# 1. Start all catalogs
./setup-multi-catalog.sh --start

# Or start specific catalogs
./setup-multi-catalog.sh --start nessie unity hive

# 2. Try example
./examples/basic-s3-read-write.sh
```

---

## 📖 Features

- **MinIO Object Storage**: S3-compatible storage (ports 19000 API, 19001 Console)
- **5 Data Catalog Options**:
  - **Nessie** (Default): Git-like versioning (port 19120)
  - **Hive Metastore**: Traditional, widely supported (port 9083)
  - **Iceberg REST**: Standard REST API (port 8181)
  - **Polaris**: Apache Polaris (ports 8182, 8183)
  - **Unity Catalog**: Databricks-compatible (port 8080)
- **Apache Iceberg**: Table format for huge analytic datasets
- **Jupyter Notebooks**: Interactive data exploration (port 8888)
- **ClickHouse Integration**: Fully tested with 25.10 and 25.11

---

## 🎯 Usage Recommendations by Scenario

### Scenario 1: Focus on One Catalog
**Recommended**: Use `setup.sh`

```bash
./setup.sh --configure  # Select Unity Catalog
./setup.sh --start
```

**Benefits**:
- Resource efficient
- Focused on one catalog
- Simple configuration

### Scenario 2: Compare and Test Catalogs
**Recommended**: Use `setup-multi-catalog.sh`

```bash
./setup-multi-catalog.sh --start nessie unity hive
```

**Benefits**:
- Run multiple catalogs simultaneously
- Easy feature comparison
- Comprehensive testing

### Scenario 3: Development and Experimentation
**Recommended**: Use both tools as needed

```bash
# Main work: Use setup.sh for Unity Catalog
./setup.sh --start  # Unity only

# Comparison tests: Use setup-multi-catalog.sh
./setup-multi-catalog.sh --start nessie unity
```

---

## 📁 Project Structure

```
datalake-minio-catalog/
│
├── 🔧 Core Setup Scripts
│   ├── setup.sh                    # Single catalog setup
│   ├── setup-multi-catalog.sh      # Multi-catalog setup
│   ├── config.env                  # Single catalog config
│   ├── config-multi-catalog.env    # Multi-catalog config
│   └── docker-compose.yml          # Docker services
│
├── 📚 Documentation
│   ├── README.md (this file)       # English docs
│   ├── README.ko.md                # Korean docs
│   └── docs/                       # Detailed docs
│
├── 🧪 Tests
│   └── tests/
│       ├── test-catalogs.sh        # All catalogs test
│       └── test-unity-deltalake.sh # Unity + Delta Lake test
│
├── 💡 Examples
│   └── examples/
│       ├── basic-s3-read-write.sh  # Basic S3 operations
│       └── delta-lake-simple.sh    # Delta Lake example
│
└── 📓 Jupyter Notebooks
    └── notebooks/
```

---

## 🎮 Command Guide

### setup.sh (Single Catalog)

```bash
# Configure (required)
./setup.sh --configure

# Start
./setup.sh --start

# Stop
./setup.sh --stop

# Status
./setup.sh --status

# Clean data
./setup.sh --clean
```

### setup-multi-catalog.sh (Multiple Catalogs)

```bash
# Start all catalogs
./setup-multi-catalog.sh --start

# Start specific catalogs
./setup-multi-catalog.sh --start nessie unity

# Stop
./setup-multi-catalog.sh --stop

# Status
./setup-multi-catalog.sh --status

# Configure (optional - has defaults)
./setup-multi-catalog.sh --configure
```

---

## 🔍 Service Endpoints

After starting services, access via:

### MinIO
- **Console UI**: http://localhost:19001
- **API Endpoint**: http://localhost:19000
- **Credentials**: admin / password123

### Data Catalogs

| Catalog | Endpoint | Port |
|---------|----------|------|
| **Nessie** | http://localhost:19120 | 19120 |
| **Hive** | thrift://localhost:9083 | 9083 |
| **Iceberg REST** | http://localhost:8181 | 8181 |
| **Polaris** | http://localhost:8182 | 8182, 8183 |
| **Unity** | http://localhost:8080 | 8080 |

### Jupyter Notebook
- **URL**: http://localhost:8888 (no password)

---

## 💡 Usage Examples

### Example 1: Basic S3 Read/Write

```bash
# Start MinIO + catalog
./setup.sh --start

# Run example
./examples/basic-s3-read-write.sh
```

### Example 2: Delta Lake Operations

```bash
# Start Unity Catalog
./setup.sh --configure  # Select Unity
./setup.sh --start

# Run Delta Lake example
./examples/delta-lake-simple.sh
```

### Example 3: Catalog Comparison

```bash
# Start 3 catalogs simultaneously
./setup-multi-catalog.sh --start nessie unity hive

# Run comparison test
./tests/test-catalogs.sh
```

---

## 🧪 ClickHouse Integration Testing

### Tested Versions

| Version | Unity Catalog | Delta Lake | Status | Recommendation |
|---------|--------------|------------|--------|----------------|
| **25.11.2.24** | ✅ Full support | ✅ Full support | ✅ All tests passed | **Recommended** |
| **25.10.3.100** | ✅ Basic support | ⚠️ Limited support | ⚠️ 80% tests passed | Use with caution |

### Unity Catalog + Delta Lake Testing

```bash
# 1. Start Unity Catalog
./setup.sh --configure  # Select Unity
./setup.sh --start

# 2. Start ClickHouse
cd ../oss-mac-setup
./set.sh 25.11 && ./start.sh
cd ../datalake-minio-catalog

# 3. Run integration test
./tests/test-unity-deltalake.sh

# 4. View results
cat docs/test-results/test-results-*.md
```

Detailed comparison: [docs/COMPARISON-25.10-vs-25.11.md](docs/COMPARISON-25.10-vs-25.11.md)

---

## 📊 Catalog Comparison

| Feature | Nessie | Hive | Iceberg REST | Polaris | Unity |
|---------|--------|------|--------------|---------|-------|
| **Versioning** | ✅ Git-like | ❌ | Limited | ✅ | ✅ |
| **Time Travel** | ✅ | ❌ | ✅ | ✅ | ✅ |
| **Branching** | ✅ | ❌ | ❌ | ✅ | ❌ |
| **ACID** | ✅ | Limited | ✅ | ✅ | ✅ |
| **Maturity** | Modern | Very mature | Modern | New | Modern |
| **Best For** | Version control | Legacy systems | Standard API | Iceberg-focused | Databricks-compatible |

---

## 🔄 Workflow Examples

### Workflow 1: Quick Test

```bash
# Method A: Single catalog
./setup.sh --configure && ./setup.sh --start
./examples/basic-s3-read-write.sh

# Method B: Multiple catalogs
./setup-multi-catalog.sh --start
./examples/basic-s3-read-write.sh
```

### Workflow 2: Unity Catalog Deep Dive

```bash
# Start Unity only
./setup.sh --configure  # Select Unity
./setup.sh --start

# Start ClickHouse and test
cd ../oss-mac-setup && ./set.sh 25.11 && ./start.sh
cd ../datalake-minio-catalog
./tests/test-unity-deltalake.sh
```

### Workflow 3: Catalog Comparison Analysis

```bash
# Start all catalogs
./setup-multi-catalog.sh --start

# Start ClickHouse
cd ../oss-mac-setup && ./set.sh 25.11 && ./start.sh
cd ../datalake-minio-catalog

# Run comprehensive test
./tests/test-catalogs.sh
```

---

## 🐛 Troubleshooting

### Services won't start

```bash
# Check Docker
docker ps

# Check logs
docker logs minio
docker logs unity-catalog

# Check status
./setup.sh --status
./setup-multi-catalog.sh --status
```

### Port conflicts

```bash
# Check port usage
lsof -i :19000

# Reconfigure ports
./setup.sh --configure
# or
./setup-multi-catalog.sh --configure
```

### ClickHouse connection issues

```sql
-- From Docker container: use host.docker.internal
SELECT * FROM s3(
    'http://host.docker.internal:19000/warehouse/data.parquet',
    'admin', 'password123', 'Parquet'
);

-- From host: use localhost
SELECT * FROM s3(
    'http://localhost:19000/warehouse/data.parquet',
    'admin', 'password123', 'Parquet'
);
```

---

## 📚 Documentation

### English Documentation
- **[README.md](README.md)** (this file) - Main documentation
- **[docs/QUICKSTART_GUIDE.md](docs/QUICKSTART_GUIDE.md)** - Quick start
- **[docs/SPARK_SETUP.md](docs/SPARK_SETUP.md)** - Spark integration
- **[docs/UNITY_DELTALAKE_TEST_GUIDE.md](docs/UNITY_DELTALAKE_TEST_GUIDE.md)** - Unity testing
- **[docs/COMPARISON-25.10-vs-25.11.md](docs/COMPARISON-25.10-vs-25.11.md)** - Version comparison

### Korean Documentation (한글 문서)
- **[README.ko.md](README.ko.md)** - 한글 메인 문서
- **[docs/NAVIGATION_GUIDE.md](docs/NAVIGATION_GUIDE.md)** - 프로젝트 탐색 가이드

---

## 🎯 Recommendations Summary

| Use Case | Recommended Tool | Reason |
|----------|-----------------|--------|
| **Single catalog work** | `setup.sh` | Resource efficient, focused |
| **Catalog comparison** | `setup-multi-catalog.sh` | Simultaneous execution, easy comparison |
| **Unity deep testing** | `setup.sh` + Unity | Focused testing environment |
| **Comprehensive testing** | `setup-multi-catalog.sh` | All catalogs at once |
| **Development/Experimentation** | Use both | Flexible environment switching |

---

## ✨ Version History

### v3.1 (2025-12-13) - Multi-Catalog Support
- ✨ Added `setup-multi-catalog.sh` - Run multiple catalogs simultaneously
- 📚 Bilingual documentation (Korean/English)
- 🎯 Purpose-specific usage guides

### v3.0 (2025-12-13) - Reorganization
- 📁 Separated tests, examples, docs
- 🧹 Cleaned up project structure

### v2.0 (2025-12)
- Added Polaris and Unity Catalog
- ClickHouse 25.10/25.11 testing

### v1.0
- Initial release with 3 catalogs

---

## 📖 Resources

- [MinIO Documentation](https://min.io/docs/minio/linux/index.html)
- [Apache Iceberg](https://iceberg.apache.org/)
- [Project Nessie](https://projectnessie.org/)
- [Apache Polaris](https://polaris.apache.org/)
- [Unity Catalog](https://github.com/unitycatalog/unitycatalog)
- [ClickHouse S3 Integration](https://clickhouse.com/docs/en/engines/table-engines/integrations/s3)

---

## 📝 License

Educational purposes demonstration project

---

## 🆘 Support

- **Quick help**: `./setup.sh --help` or `./setup-multi-catalog.sh --help`
- **Documentation**: [docs/](docs/) directory
- **Testing**: Run `./tests/test-catalogs.sh`
- **Logs**: `docker logs <service-name>`
