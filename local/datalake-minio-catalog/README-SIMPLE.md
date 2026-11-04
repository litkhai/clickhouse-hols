# Data Lake with MinIO and Catalogs - Simplified Setup

## 🎯 What's New in Version 3.1

- ✨ **Multiple catalogs simultaneously** - Run all 5 catalogs at once!
- 🚀 **Simplified setup** - One command to start everything
- 📦 **Optional configuration** - Sensible defaults, configure only if needed
- 🧹 **Cleaner structure** - Legacy scripts moved out of the way

---

## ⚡ Quick Start (30 seconds)

```bash
# Start everything with defaults
./setup-multi-catalog.sh --start

# Try an example
./examples/basic-s3-read-write.sh
```

**That's it!** MinIO and all catalogs are running.

---

## 📖 Complete Guide

### Prerequisites

- Docker & Docker Compose
- 20GB+ disk space
- A ClickHouse server with `DataLakeCatalog` (the lab tests use 26.10.3.7; `tests/test-datalakecatalog.sh` starts its own)

### Step-by-Step

#### 1. Optional: Configure

```bash
./setup-multi-catalog.sh --configure
```

Sets storage size and ports. **Skip this to use defaults.**

#### 2. Start Services

**Option A: Start everything (recommended for testing)**
```bash
./setup-multi-catalog.sh --start
```

**Option B: Start specific catalogs**
```bash
# Just Unity and Nessie
./setup-multi-catalog.sh --start unity nessie

# Just Hive
./setup-multi-catalog.sh --start hive

# Nessie, Iceberg, and Polaris
./setup-multi-catalog.sh --start nessie iceberg polaris
```

#### 3. Verify

```bash
./setup-multi-catalog.sh --status
```

#### 4. Try Examples

```bash
# Basic S3 operations
./examples/basic-s3-read-write.sh

# Parquet analytics (name is historical, no Delta Lake engine)
./examples/delta-lake-simple.sh

# Test catalogs
./tests/test-catalogs.sh
```

---

## 🎮 Commands

| Command | Description |
|---------|-------------|
| `./setup-multi-catalog.sh --start` | Start all catalogs |
| `./setup-multi-catalog.sh --start nessie unity` | Start specific catalogs |
| `./setup-multi-catalog.sh --stop` | Stop all services |
| `./setup-multi-catalog.sh --status` | Check status |
| `./setup-multi-catalog.sh --configure` | Interactive config |
| `./setup-multi-catalog.sh --clean` | Remove all data |
| `./setup-multi-catalog.sh --help` | Show help |

---

## 🗂️ Available Catalogs

Start **one or more** catalogs:

| Name | Keyword | Port | Description |
|------|---------|------|-------------|
| **Nessie** | `nessie` | 19120 | Git-like versioning |
| **Hive Metastore** | `hive` | 9083 | Traditional catalog |
| **Iceberg REST** | `iceberg` | 8181 | REST API |
| **Polaris** | `polaris` | 8182, 8183 | Apache Polaris |
| **Unity Catalog** | `unity` | 8080 | Databricks-compatible |

### Examples:

```bash
# All catalogs (for comprehensive testing)
./setup-multi-catalog.sh --start

# Modern catalogs only
./setup-multi-catalog.sh --start nessie unity polaris

# Traditional catalog
./setup-multi-catalog.sh --start hive

# Mix and match
./setup-multi-catalog.sh --start nessie hive unity
```

---

## 🌐 Service Endpoints

After starting services:

### MinIO (Always Running)
- **Console**: http://localhost:19001
- **API**: http://localhost:19000
- **Login**: admin / password123

### Catalogs (If Started)
- **Nessie**: http://localhost:19120
- **Hive**: thrift://localhost:9083
- **Iceberg REST**: http://localhost:8181
- **Polaris API**: http://localhost:8182
- **Polaris Mgmt**: http://localhost:8183
- **Unity**: http://localhost:8080

### Jupyter (Always Running)
- **URL**: http://localhost:8888

---

## 📁 Project Structure

```
datalake-minio-catalog/
│
├── setup-multi-catalog.sh   # 🌟 Multi-catalog setup (USE THIS)
├── setup.sh                 # Single-catalog setup (one catalog at a time)
├── GETTING_STARTED.md       # 🌟 Quick start guide
│
├── examples/                # Learning examples
│   ├── basic-s3-read-write.sh
│   └── delta-lake-simple.sh
│
├── tests/                   # Test scripts
│   ├── test-catalogs.sh
│   └── test-unity-deltalake.sh
│
├── docs/                    # Documentation
│   ├── NAVIGATION_GUIDE.md
│   ├── UNITY_DELTALAKE_TEST_GUIDE.md
│   └── COMPARISON-25.10-vs-25.11.md
│
├── notebooks/               # Jupyter notebooks
├── sample-data/             # Sample datasets
├── examples/                # Example scripts
└── tests/                   # Test scripts
```

---

## 🔄 Workflow Examples

### Workflow 1: Test Everything

```bash
# 1. Start all services
./setup-multi-catalog.sh --start

# 2. Check status
./setup-multi-catalog.sh --status

# 3. Try examples
./examples/basic-s3-read-write.sh
./examples/delta-lake-simple.sh

# 4. Run tests
./tests/test-catalogs.sh
```

### Workflow 2: Unity Catalog + ClickHouse

```bash
# 1. Start MinIO + Unity
./setup-multi-catalog.sh --start unity

# 2. Start ClickHouse 25.11
cd ../oss-docker
./set.sh 25.11 && ./start.sh
cd ../datalake-minio-catalog

# 3. Run the Unity health / storage check (not the catalog read test)
./tests/test-unity-deltalake.sh

# 4. View results (written next to the script, git-ignored)
cat tests/test-results-unity-deltalake-*.md
```

### Workflow 3: Development with Specific Catalogs

```bash
# Start only what you need
./setup-multi-catalog.sh --start nessie iceberg

# Develop and test
# ...

# Add more catalogs without restarting
./setup-multi-catalog.sh --start unity

# Stop when done
./setup-multi-catalog.sh --stop
```

---

## 🆚 Old vs New Setup

| Feature | setup.sh (Old) | setup-multi-catalog.sh (New) |
|---------|----------------|----------------------|
| **Multiple catalogs** | ❌ One at a time | ✅ Multiple simultaneously |
| **Default config** | ❌ Must configure | ✅ Has sensible defaults |
| **Ease of use** | ⚠️ Complex | ✅ Simple |
| **Flexibility** | ⚠️ Limited | ✅ Mix and match catalogs |
| **Status** | Legacy | **Recommended** |

### Migration Example

**Old way:**
```bash
./setup.sh --configure
# Select 1: Nessie
./setup.sh --start

# To try Unity, must reconfigure and restart
./setup.sh --stop
./setup.sh --configure
# Select 5: Unity
./setup.sh --start
```

**New way:**
```bash
# Start both at once!
./setup-multi-catalog.sh --start nessie unity

# Or start everything
./setup-multi-catalog.sh --start
```

---

## 🎓 Learning Path

### Beginner
1. [GETTING_STARTED.md](GETTING_STARTED.md)
2. `./examples/basic-s3-read-write.sh`
3. Jupyter notebooks: http://localhost:8888

### Intermediate
1. `./examples/delta-lake-simple.sh`
2. [docs/QUICKSTART_GUIDE.md](docs/QUICKSTART_GUIDE.md)
3. `./tests/test-catalogs.sh`

### Advanced
1. [docs/UNITY_DELTALAKE_TEST_GUIDE.md](docs/UNITY_DELTALAKE_TEST_GUIDE.md)
2. [docs/SPARK_SETUP.md](docs/SPARK_SETUP.md)
3. [docs/COMPARISON-25.10-vs-25.11.md](docs/COMPARISON-25.10-vs-25.11.md)

---

## 🔧 Configuration

### Automatic (Recommended)
```bash
# Uses defaults, just start
./setup-multi-catalog.sh --start
```

### Custom
```bash
# Interactive configuration
./setup-multi-catalog.sh --configure

# Or edit config-multi-catalog.env manually
nano config-multi-catalog.env
```

### Default Settings

| Setting | Default Value |
|---------|--------------|
| MinIO Storage | 20G |
| MinIO API Port | 19000 |
| MinIO Console Port | 19001 |
| Nessie Port | 19120 |
| Hive Port | 9083 |
| Iceberg REST Port | 8181 |
| Polaris Ports | 8182, 8183 |
| Unity Port | 8080 |

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
./setup-multi-catalog.sh --status
```

### Port conflicts

```bash
# Check what's using a port
lsof -i :19000

# Reconfigure with different ports
./setup-multi-catalog.sh --configure
```

### Can't connect to catalog

```bash
# Check if catalog is running
./setup-multi-catalog.sh --status

# Test connectivity
curl http://localhost:19120/api/v2/config  # Nessie
curl http://localhost:8080/api/2.1/unity-catalog/catalogs  # Unity
```

### Clean start

```bash
# Stop and remove all data
./setup-multi-catalog.sh --clean

# Start fresh
./setup-multi-catalog.sh --start
```

---

## 📚 Documentation

- **[GETTING_STARTED.md](GETTING_STARTED.md)** - Quick start (START HERE)
- **[README.md](README.md)** - Full documentation
- **[docs/NAVIGATION_GUIDE.md](docs/NAVIGATION_GUIDE.md)** - Find your way around
- **[docs/UNITY_DELTALAKE_TEST_GUIDE.md](docs/UNITY_DELTALAKE_TEST_GUIDE.md)** - Unity testing
- **[docs/COMPARISON-25.10-vs-25.11.md](docs/COMPARISON-25.10-vs-25.11.md)** - Historical comparison (2025-12-13, not re-run)

---

## 🎯 Key Improvements in v3.1

### Before (v2.0)
- ❌ One catalog at a time
- ❌ Must stop and reconfigure to switch
- ❌ Complex configuration process
- ❌ No default settings

### After (v3.1)
- ✅ Multiple catalogs simultaneously
- ✅ Mix and match any catalogs
- ✅ Simple one-command start
- ✅ Sensible defaults

### Example: Testing 3 Catalogs

**Before:**
```bash
# Test Nessie
./setup.sh --configure  # Select Nessie
./setup.sh --start
./tests/test-catalogs.sh
./setup.sh --stop

# Test Unity
./setup.sh --configure  # Select Unity
./setup.sh --start
./tests/test-catalogs.sh
./setup.sh --stop

# Test Hive
./setup.sh --configure  # Select Hive
./setup.sh --start
./tests/test-catalogs.sh
./setup.sh --stop
```

**After:**
```bash
# Test all 3 at once!
./setup-multi-catalog.sh --start nessie unity hive
./tests/test-catalogs.sh
```

---

## 🌟 Why Use This?

### For Learning
- ✅ Try different catalogs easily
- ✅ Compare catalog features side-by-side
- ✅ No need to restart for different catalogs

### For Testing
- ✅ Test multiple catalogs in one session
- ✅ Verify catalog integration with ClickHouse
- ✅ Run comprehensive test suites

### For Development
- ✅ Start only what you need
- ✅ Add more catalogs on the fly
- ✅ Fast iteration

---

## 🆘 Get Help

```bash
# Show help
./setup-multi-catalog.sh --help

# Check status
./setup-multi-catalog.sh --status

# Read guide
cat GETTING_STARTED.md
```

---

## 📊 ClickHouse Integration

### Verified version

`tests/test-datalakecatalog.sh` (ClickHouse reads seeded rows through each catalog with `DataLakeCatalog`) was run on ClickHouse 26.10.3.7 on 2026-11-04; see [README.md](README.md) for what was and was not checked. `tests/test-catalogs.sh` and `tests/test-unity-deltalake.sh` are health / storage checks only (ClickHouse does not read through a catalog there). The earlier 25.10 / 25.11 pass-rate table was removed: it came from those health checks and was not re-run. Historical record: [docs/COMPARISON-25.10-vs-25.11.md](docs/COMPARISON-25.10-vs-25.11.md) (2025-12-13).

### Quick Test

```bash
# 1. Start catalogs
./setup-multi-catalog.sh --start unity nessie

# 2. Start ClickHouse
cd ../oss-docker && ./set.sh 25.11 && ./start.sh
cd ../datalake-minio-catalog

# 3. Health / storage check
./tests/test-unity-deltalake.sh
```

---

## 🔄 What Changed from v2.0

### New Files
- `setup-multi-catalog.sh` - New multi-catalog setup script
- `GETTING_STARTED.md` - Quick start guide
- `config-multi-catalog.env` - New config format
- `README-SIMPLE.md` - This file

### Helper Scripts
- `generate_parquet.py` - Generates the sample Parquet datasets
- `register_data.py` - Registers the generated data in a catalog
- `quickstart.sh` - One-command start for a single catalog (uses `setup.sh`)

### Still There
- `setup.sh` - Single-catalog setup (still works)
- `config.env` - Old config (still works)
- All tests, examples, docs - Same locations

---

## 📝 Version History

### v3.1 (2025-12-13) - Simplified Setup
- ✨ Multiple catalogs simultaneously
- ✨ Simplified configuration
- ✨ Default settings
- ✨ One-command start

### v3.0 (2025-12-13) - Reorganization
- 📁 Separated tests, examples, docs
- 📚 Improved documentation

### v2.0 (2025-12)
- Added Polaris and Unity Catalog
- ClickHouse 25.10/25.11 testing (s3() / health checks, see the note in docs/COMPARISON-25.10-vs-25.11.md)

### v1.0
- Initial release with 3 catalogs

---

## ⚖️ License

Educational purposes demonstration project.

---

**Recommendation**: Use `setup-multi-catalog.sh` for new deployments. `setup.sh` remains for single-catalog use.

**Quick Links**:
- [Getting Started](GETTING_STARTED.md)
- [Examples](examples/)
- [Tests](tests/)
- [Documentation](docs/)
