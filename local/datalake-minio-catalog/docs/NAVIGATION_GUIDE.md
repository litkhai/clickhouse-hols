# Navigation Guide - Data Lake Project

This guide helps you navigate the reorganized project structure and find what you need.

## 🗺️ Quick Navigation

| I want to... | Go to... |
|--------------|----------|
| **Get started quickly** | [README.md](../README.md) → [Quick Start](../README.md#quick-start) |
| **Configure and setup** | [setup.sh](../setup.sh) → `./setup.sh --configure` |
| **Try examples** | [examples/](../examples/) |
| **Run tests** | [tests/](../tests/) |
| **Read documentation** | [docs/](.) |
| **View test results** | `docs/test-results/` |
| **Learn with notebooks** | [notebooks/](../notebooks/) |

---

## 📁 Directory Structure Explained

```
datalake-minio-catalog/
│
├── 🏠 Root Level - Core Setup
│   ├── README.md               ← Start here!
│   ├── setup.sh                ← Main setup script
│   ├── config.env              ← Configuration file
│   └── docker-compose.yml      ← Docker services
│
├── 📚 docs/ - All Documentation
│   ├── NAVIGATION_GUIDE.md     ← This file
│   ├── QUICKSTART_GUIDE.md     ← Detailed setup
│   ├── SPARK_SETUP.md          ← Spark integration
│   ├── UNITY_DELTALAKE_TEST_GUIDE.md  ← Unity testing
│   ├── COMPARISON-25.10-vs-25.11.md   ← Version comparison
│   └── test-results/           ← Test execution reports
│
├── 🧪 tests/ - All Test Scripts
│   ├── test-catalogs.sh        ← Test all catalogs
│   └── test-unity-deltalake.sh ← Unity + Delta Lake test
│
├── 💡 examples/ - Learning Examples
│   ├── basic-s3-read-write.sh  ← Basic S3 operations
│   └── delta-lake-simple.sh    ← Simple Delta Lake
│
├── 📓 notebooks/ - Jupyter Notebooks
│   ├── 01_minio_connection.ipynb
│   ├── 02_iceberg_nessie.ipynb
│   ├── 03_clickhouse_integration.ipynb
│   └── 04_spark_iceberg_nessie.ipynb
│
└── 🗄️ data & config files
    ├── sample-data/
    ├── minio-storage/
    ├── generate_parquet.py
    └── register_data.py
```

---

## 🎯 User Journey Paths

### Path 1: First Time User - Getting Started

```
1. README.md
   ↓
2. ./setup.sh --configure
   ↓
3. ./setup.sh --start
   ↓
4. ./examples/basic-s3-read-write.sh
   ↓
5. docs/QUICKSTART_GUIDE.md (for more details)
```

### Path 2: Testing User - Running Tests

```
1. README.md (prerequisites)
   ↓
2. ./setup.sh --start
   ↓
3. tests/test-catalogs.sh
   ↓
4. docs/test-results/ (view results)
   ↓
5. docs/UNITY_DELTALAKE_TEST_GUIDE.md (advanced testing)
```

### Path 3: Developer - Learning & Integration

```
1. README.md (overview)
   ↓
2. examples/ (try examples)
   ↓
3. notebooks/ (interactive learning)
   ↓
4. docs/SPARK_SETUP.md (advanced integration)
   ↓
5. tests/ (understand test patterns)
```

### Path 4: Researcher - Version Comparison

```
1. docs/COMPARISON-25.10-vs-25.11.md
   ↓
2. docs/test-results/ (detailed results)
   ↓
3. tests/test-unity-deltalake.sh (run own tests)
   ↓
4. docs/UNITY_DELTALAKE_TEST_GUIDE.md (methodology)
```

---

## 📖 Documentation Index

### Getting Started
- **[README.md](../README.md)** - Project overview and quick start
- **[QUICKSTART_GUIDE.md](QUICKSTART_GUIDE.md)** - Detailed setup instructions
- **[config.env](../config.env)** - Configuration reference

### Testing
- **[UNITY_DELTALAKE_TEST_GUIDE.md](UNITY_DELTALAKE_TEST_GUIDE.md)** - Unity Catalog + Delta Lake testing
- **[COMPARISON-25.10-vs-25.11.md](COMPARISON-25.10-vs-25.11.md)** - Version comparison report
- **`test-results/`** - Historical test results

### Advanced
- **[SPARK_SETUP.md](SPARK_SETUP.md)** - Spark integration guide
- **[NAVIGATION_GUIDE.md](NAVIGATION_GUIDE.md)** - This file

---

## 🧪 Test Scripts Guide

### tests/test-catalogs.sh
**Purpose**: Test all 5 catalogs (Nessie, Hive, Iceberg REST, Polaris, Unity)
**Usage**: `./tests/test-catalogs.sh`
**When to use**:
- After initial setup
- After changing catalogs
- To verify integration with ClickHouse
- Before production deployment

**Output**: Terminal output with pass/fail results

### tests/test-unity-deltalake.sh
**Purpose**: Comprehensive Unity Catalog + Delta Lake testing
**Usage**: `./tests/test-unity-deltalake.sh`
**When to use**:
- Testing Unity Catalog specifically
- Comparing ClickHouse versions
- Validating Delta Lake operations
- Performance testing

**Output**: Markdown report in `docs/test-results/`

---

## 💡 Examples Guide

### examples/basic-s3-read-write.sh
**Purpose**: Learn basic S3/MinIO operations
**Level**: Beginner
**What it does**:
- Creates sample data in ClickHouse
- Writes to MinIO (Parquet format)
- Reads back from MinIO
- Performs aggregations

**When to use**:
- First time trying the system
- Learning S3 operations
- Understanding read/write flow

### examples/delta-lake-simple.sh
**Purpose**: Learn Delta Lake operations
**Level**: Intermediate
**What it does**:
- Creates orders dataset
- Exports to Delta Lake format
- Performs analytics queries
- Shows aggregations

**When to use**:
- After understanding basic S3
- Learning Delta Lake
- Building analytics pipelines

---

## 📓 Jupyter Notebooks Guide

| Notebook | Level | Purpose | Prerequisites |
|----------|-------|---------|---------------|
| **01_minio_connection.ipynb** | Beginner | Connect to MinIO | None |
| **02_iceberg_nessie.ipynb** | Intermediate | Iceberg with Nessie | Notebook 01 |
| **03_clickhouse_integration.ipynb** | Intermediate | ClickHouse integration | Notebooks 01-02 |
| **04_spark_iceberg_nessie.ipynb** | Advanced | Spark integration | All previous |

**Access**: http://localhost:8888 (after `./setup.sh --start`)

---

## 🔍 Finding What You Need

### I want to understand how catalogs work
→ [README.md](../README.md#catalog-comparison) (catalog comparison table)
→ [docs/QUICKSTART_GUIDE.md](QUICKSTART_GUIDE.md)

### I want to test Unity Catalog specifically
→ [tests/test-unity-deltalake.sh](../tests/test-unity-deltalake.sh)
→ [docs/UNITY_DELTALAKE_TEST_GUIDE.md](UNITY_DELTALAKE_TEST_GUIDE.md)

### I want to see test results
→ `docs/test-results/`
→ [docs/COMPARISON-25.10-vs-25.11.md](COMPARISON-25.10-vs-25.11.md)

### I want to learn by example
→ [examples/](../examples/)
→ [notebooks/](../notebooks/)

### I want to integrate with Spark
→ [docs/SPARK_SETUP.md](SPARK_SETUP.md)

### I want to troubleshoot issues
→ [README.md](../README.md#troubleshooting)
→ [docs/QUICKSTART_GUIDE.md](QUICKSTART_GUIDE.md)

### I want to compare ClickHouse versions
→ [docs/COMPARISON-25.10-vs-25.11.md](COMPARISON-25.10-vs-25.11.md)
→ `docs/test-results/`

---

## 🚀 Quick Commands Reference

### Setup & Configuration
```bash
./setup.sh --configure    # Interactive configuration
./setup.sh --start        # Start all services
./setup.sh --stop         # Stop all services
./setup.sh --status       # Check status
./setup.sh --endpoints    # Show endpoints
./setup.sh --clean        # Clean all data
```

### Examples (Learning)
```bash
./examples/basic-s3-read-write.sh    # Basic S3 operations
./examples/delta-lake-simple.sh      # Delta Lake example
```

### Tests (Validation)
```bash
./tests/test-catalogs.sh             # Test all catalogs
./tests/test-unity-deltalake.sh      # Unity + Delta Lake test
```

### Jupyter (Interactive)
```bash
# After ./setup.sh --start
open http://localhost:8888
```

---

## 📊 File Type Guide

### Shell Scripts (.sh)
- **setup.sh** - Main setup (root level)
- **tests/*.sh** - Test scripts (in tests/)
- **examples/*.sh** - Example scripts (in examples/)

**Run with**: `./script-name.sh`

### Documentation (.md)
- **README.md** - Main documentation (root level)
- **docs/*.md** - Detailed documentation (in docs/)
- **docs/test-results/*.md** - Test reports (in docs/test-results/)

**View with**: Text editor or GitHub

### Configuration
- **config.env** - Main configuration (edit manually)
- **docker-compose.yml** - Docker services (don't edit)

**Edit with**: Text editor

### Notebooks (.ipynb)
- **notebooks/*.ipynb** - Jupyter notebooks

**Run with**: Jupyter at http://localhost:8888

---

## 🔄 Migration from Old Structure

If you're familiar with the old structure:

| Old Location | New Location | Reason |
|--------------|--------------|--------|
| `./test-catalogs.sh` | `./tests/test-catalogs.sh` | Separation of concerns |
| `./test-unity-deltalake.sh` | `./tests/test-unity-deltalake.sh` | Separation of concerns |
| `./UNITY_DELTALAKE_TEST_GUIDE.md` | `./docs/UNITY_DELTALAKE_TEST_GUIDE.md` | Documentation organization |
| `./COMPARISON-25.10-vs-25.11.md` | `./docs/COMPARISON-25.10-vs-25.11.md` | Documentation organization |
| `./QUICKSTART_GUIDE.md` | `./docs/QUICKSTART_GUIDE.md` | Documentation organization |
| `./SPARK_SETUP.md` | `./docs/SPARK_SETUP.md` | Documentation organization |
| `./test-results-*.md` | `./docs/test-results/*.md` | Archive organization |
| N/A | `./examples/*.sh` | New: Learning examples |
| N/A | `./docs/NAVIGATION_GUIDE.md` | New: This guide |

---

## 📝 Best Practices

### When Starting a New Session
1. Check service status: `./setup.sh --status`
2. If not running: `./setup.sh --start`
3. Try an example: `./examples/basic-s3-read-write.sh`
4. Run tests if needed: `./tests/test-catalogs.sh`

### When Testing
1. Read the test guide first: `docs/UNITY_DELTALAKE_TEST_GUIDE.md`
2. Ensure services are running: `./setup.sh --status`
3. Run tests: `./tests/test-unity-deltalake.sh`
4. Review results: `docs/test-results/`

### When Learning
1. Start with examples: `examples/`
2. Move to notebooks: `notebooks/`
3. Read documentation: `docs/`
4. Try tests: `tests/`

---

## 🆘 Getting Help

1. **Quick reference**: [README.md](../README.md)
2. **Detailed guide**: [docs/QUICKSTART_GUIDE.md](QUICKSTART_GUIDE.md)
3. **Troubleshooting**: [README.md#troubleshooting](../README.md#troubleshooting)
4. **Test guide**: [docs/UNITY_DELTALAKE_TEST_GUIDE.md](UNITY_DELTALAKE_TEST_GUIDE.md)
5. **This guide**: [docs/NAVIGATION_GUIDE.md](NAVIGATION_GUIDE.md)

---

**Last updated**: 2025-12-13
**Version**: 3.0
