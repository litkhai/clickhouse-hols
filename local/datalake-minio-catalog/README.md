# Data Lake with MinIO and Multiple Catalogs

> **Related notes · 관련 글**: [Data Lake Catalog (25.10+)](https://clickhouse.litkhai.dev/articles/feature/data-lake-catalog-25-10/)

**English** | [한국어](README.ko.md)

A complete setup for running a local data lake environment with MinIO object storage and 5 data catalogs: Nessie, Hive Metastore, Iceberg REST, Polaris, and Unity Catalog.

**🔗 Integrated with:** [ClickHouse 25.8+ Labs](../releases/25.8/) - catalog integration verified on ClickHouse 26.10.3.7 (see "Catalog integration test" below)

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
- **ClickHouse Integration**: `DataLakeCatalog` read test for all five catalogs on 26.10.3.7 (below); older health checks are labelled as such

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
│       ├── test-datalakecatalog.sh # Real test: seed via catalog, read via DataLakeCatalog
│       ├── seed_catalogs.py        # Pinned seed writer (pyiceberg / deltalake)
│       ├── requirements-seed.txt   # Writer pins
│       ├── test-catalogs.sh        # Health / storage check (no catalog integration)
│       └── test-unity-deltalake.sh # Unity API + s3() Parquet check (no Delta engine)
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

### Catalog integration test (`DataLakeCatalog`)

`tests/test-datalakecatalog.sh` is the test that exercises ClickHouse against a catalog. For each catalog it

1. seeds `lab.events` (5 rows: `id` Int64, `name` String, `amount` Float64, `ts` timestamp) **through the catalog itself** with a pinned writer (`seed_catalogs.py` in a digest-pinned `python:3.12-slim` container: pyiceberg 0.12.0 for Nessie, Hive Metastore, Iceberg REST and Polaris; `deltalake` 1.6.6 plus the Unity REST API for Unity Catalog, whose table is Delta),
2. runs `CREATE DATABASE ... ENGINE = DataLakeCatalog(...)` in a ClickHouse container on the lab network,
3. checks `SHOW TABLES`, `count()` = 5, `sum(id)`/`sum(amount)` = 15/152, a filtered query (`amount > 25` returns charlie, delta, echo) and a timestamp value.

A catalog passes only if ClickHouse read the seeded rows through it. The script starts and removes its own stack and ClickHouse container (compose project `dlfix`; `KEEP=1` leaves them up). Host ports come from `config.env` and can be overridden from the environment (`MINIO_PORT`, `MINIO_CONSOLE_PORT`, `POSTGRES_PORT`, `JUPYTER_PORT`, ...).

```bash
tests/test-datalakecatalog.sh                       # all five
tests/test-datalakecatalog.sh nessie polaris        # a subset
FAULT=stop-catalog tests/test-datalakecatalog.sh    # stops each catalog after seeding: must go red
CH_IMAGE=clickhouse/clickhouse-server:26.10.3.7 tests/test-datalakecatalog.sh
```

DDL used (engine settings read from `system.settings`, the server's error messages and the [DataLakeCatalog docs](https://clickhouse.com/docs/engines/database-engines/datalakecatalog), read 2026-11-04). Common settings for the MinIO-backed REST/Hive catalogs: `vended_credentials = 0, aws_access_key_id, aws_secret_access_key, region = 'us-east-1', storage_endpoint = 'http://minio:9000/warehouse'`.

| Catalog | Engine endpoint | `catalog_type` | `SET` needed | Other settings |
|---|---|---|---|---|
| Nessie | `http://nessie:19120/iceberg` | `rest` | `allow_database_iceberg` | `warehouse = 'warehouse'` |
| Iceberg REST (tabulario) | `http://iceberg-rest:8181` | `rest` | `allow_database_iceberg` | `warehouse = 'warehouse'` (required by ClickHouse, ignored by the server) |
| Polaris | `http://polaris:8181/api/catalog` | `rest` | `allow_database_iceberg` | `warehouse = '<catalog>'`, `catalog_credential = 'root:<secret>'`, `auth_scope = 'PRINCIPAL_ROLE:ALL'`, `oauth_server_uri = '.../v1/oauth/tokens'` |
| Hive Metastore | `thrift://hive-metastore:9083` | `hive` | `allow_experimental_database_hms_catalog` | `warehouse = 'hive'` |
| Unity Catalog OSS | `http://unity-catalog:8080/api/2.1/unity-catalog` | `unity` | `allow_database_unity_catalog` | `use_unity_catalog_v2 = 1`, `warehouse = 'lab'`, `catalog_credential`, `storage_endpoint = 'http://minio:9000'`, `region` |

Notes from the run:

- Without `vended_credentials = 0`, reading from the REST catalogs failed with `ACCESS_DENIED` ("S3 access from user queries is not allowed to use the server's own credentials ..."): the default requests credentials vended by the catalog, and Nessie here is not configured to vend any.
- Unity: Unity OSS has no endpoint setting, so the test gives it short-lived MinIO STS credentials through `server.properties` (`UNITY_SERVER_PROPERTIES`), and ClickHouse needs `storage_endpoint` to talk to MinIO. Without it ClickHouse requested `https://s3.eu-central-1.amazonaws.com/warehouse/...` with the vended key and got `403 InvalidAccessKeyId` (`UNITY_STORAGE_ENDPOINT= tests/test-datalakecatalog.sh unity` reproduces it; that run sends a throwaway MinIO key to AWS). The Unity test also passed with `use_unity_catalog_v2 = 0` (`UNITY_V2=0`); the default of the test is `1`, the setting the docs describe for serving Delta and Iceberg.
- Hive Metastore: the image needs `hadoop-aws` on the classpath and `conf/hive-core-site.xml` to resolve `s3a://` table locations (both set in `docker-compose.yml`); the seed registers the table with an explicit `s3a://` location. The `apache/hive:3.1.3` image is amd64 only and runs under emulation on arm64 hosts. Re-creating the metastore container against an existing Postgres volume fails (`initSchema` runs on every start); use `down -v`.

### Pinned versions

Images are pinned (no `:latest`). Digests are the registry index digests read on 2026-11-04.

| Component | Image | Digest / version |
|---|---|---|
| MinIO | `cgr.dev/chainguard/minio@sha256:3c60a2a8...` | `RELEASE.2026-10-23T20-06-51Z` (`minio/minio` can no longer be pulled; Chainguard publishes no version tags, so pinned by digest) |
| MinIO client (bucket setup) | `cgr.dev/chainguard/minio-client@sha256:1dccd2a6...` | no shell: one `mc mb` call with `MC_HOST_myminio` |
| Nessie | `ghcr.io/projectnessie/nessie:0.109.0` | `sha256:61a1a14e...` (the old Docker Hub `projectnessie/nessie` stops at 2024-01) |
| Iceberg REST | `tabulario/iceberg-rest:1.6.0` | `sha256:3b7d31bd...` |
| Polaris | `apache/polaris:1.8.0` | `sha256:347615e7...` |
| Unity Catalog | `unitycatalog/unitycatalog:v0.7.0` | `sha256:cdacdc5e...` |
| Hive Metastore | `apache/hive:3.1.3` | `sha256:d102ba29...` |
| Hive backing DB | `postgres:11.16` | `sha256:5d2aa4a7...` |
| Jupyter base (`Dockerfile.jupyter`) | `jupyter/pyspark-notebook@sha256:58377aaa...` | last published to Docker Hub 2023-10-20 (what `latest` pointed to on 2026-11-04); `boto3==1.43.117` and `pyarrow<26` pinned so the image builds and `pyarrow` imports |
| Seed writer | `python@sha256:b18b261e...` (`python:3.12-slim`) | `tests/requirements-seed.txt` |
| ClickHouse | `clickhouse/clickhouse-server:26.10.3.7` | `sha256:739e099a...` |

**Verified on ClickHouse 26.10.3.7, 2026-11-04** (Docker Desktop, arm64 host): `tests/test-datalakecatalog.sh` end to end for all five catalogs read all five seeded rows (`count()`, sums, a filtered query and a timestamp value matched) through every catalog; with each catalog container stopped after seeding the same test failed for all five (0 passed, 5 failed); Unity without `storage_endpoint` failed (above). The raw output of these runs is not committed. Only the `DataLakeCatalog` read path was verified, not writes through ClickHouse, ClickPipes or other versions.

### Health and storage checks (not catalog integration)

`tests/test-catalogs.sh` checks MinIO (an `s3()` Parquet write and read) and, for the active catalog, only that its health endpoint answers (Hive: port 9083 open) plus a ClickHouse `ENGINE = Memory` table; ClickHouse never connects to a catalog. `tests/test-unity-deltalake.sh` does the same for Unity (API answers, `s3()` Parquet), with no Delta engine and no `DataLakeCatalog`. `CATALOG_TYPE` and `CLICKHOUSE_CONTAINER` can be set in the environment. The earlier "25.11 all tests passed / 25.10 80% passed" table came from these checks, was not re-run, and is not evidence of catalog support, so it was removed. [docs/COMPARISON-25.10-vs-25.11.md](docs/COMPARISON-25.10-vs-25.11.md) predates the new test and was not re-checked.

### Unity Catalog health / storage check

```bash
# 1. Start Unity Catalog
./setup.sh --configure  # Select Unity
./setup.sh --start

# 2. Start ClickHouse
cd ../oss-docker
./set.sh 25.11 && ./start.sh
cd ../datalake-minio-catalog

# 3. Run the Unity health / storage check (not the catalog read test)
./tests/test-unity-deltalake.sh

# 4. View results
cat tests/test-results-*.md   # report written next to the script (git-ignored)
```

Historical comparison (2025-12-13, not re-run): [docs/COMPARISON-25.10-vs-25.11.md](docs/COMPARISON-25.10-vs-25.11.md)

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
cd ../oss-docker && ./set.sh 25.11 && ./start.sh
cd ../datalake-minio-catalog
./tests/test-unity-deltalake.sh
```

### Workflow 3: Catalog Comparison Analysis

```bash
# Start all catalogs
./setup-multi-catalog.sh --start

# Start ClickHouse
cd ../oss-docker && ./set.sh 25.11 && ./start.sh
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
- **[GETTING_STARTED.md](GETTING_STARTED.md)** - First-run walkthrough
- **[README-SIMPLE.md](README-SIMPLE.md)** - Simplified setup path (fewer catalogs)
- **[STRUCTURE_SUMMARY.md](STRUCTURE_SUMMARY.md)** - Directory and service layout
- **[CHANGES_v3.1.md](CHANGES_v3.1.md)** - Changes in v3.1

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

[MIT](../../LICENSE) — same as the rest of the repository.

---

## 🆘 Support

- **Quick help**: `./setup.sh --help` or `./setup-multi-catalog.sh --help`
- **Documentation**: [docs/](docs/) directory
- **Testing**: Run `./tests/test-datalakecatalog.sh` (catalog integration) or `./tests/test-catalogs.sh` (health check)
- **Logs**: `docker logs <service-name>`
