# Data Lake with MinIO and Multiple Catalogs

A complete setup for running a local data lake environment with MinIO object storage and choice of **5 data catalogs**: Nessie, Hive Metastore, Iceberg REST, **Polaris**, and **Unity Catalog**.

**🔗 Integrated with:** [ClickHouse 25.8+ Labs](../25.8/) - Fully tested with ClickHouse 25.10 and 25.11 for data lake analytics and catalog integration.

## Features

- **MinIO Object Storage**: S3-compatible object storage (ports 19000 API, 19001 Console)
- **5 Data Catalog Options**:
  - **Nessie** (Default): Git-like catalog with branching and versioning (port 19120)
  - **Hive Metastore**: Traditional, widely-supported catalog (port 9083)
  - **Iceberg REST**: Standard REST API catalog (port 8181)
  - **Polaris**: Apache Polaris - Open source catalog for Apache Iceberg (ports 8182, 8183)
  - **Unity Catalog**: Databricks Unity Catalog (port 8080)
- **Apache Iceberg**: Table format for huge analytic datasets
- **Jupyter Notebooks**: Interactive data exploration (port 8888)
- **ClickHouse Integration**: Fully tested with ClickHouse 25.10 and 25.11

## Prerequisites

- Docker and Docker Compose
- Python 3.8+ (for data generation scripts)
- 20GB+ disk space (configurable)
- ClickHouse 25.10+ (for catalog integration testing)

## Quick Start

### 1. Configure the Setup

```bash
./setup.sh --configure
```

This will prompt you to:
- Set MinIO storage size (default: 20GB)
- Configure MinIO ports (default: 19000 API, 19001 Console)
- Choose data catalog: Nessie (1), Hive (2), Iceberg REST (3), Polaris (4), or Unity (5)
- Configure catalog-specific ports

**Default Port Configuration:**
- **MinIO API**: 19000
- **MinIO Console**: 19001
- **Nessie**: 19120
- **Hive Metastore**: 9083
- **PostgreSQL** (for Hive): 5432
- **Iceberg REST**: 8181
- **Polaris API**: 8182
- **Polaris Management**: 8183
- **Unity Catalog**: 8080
- **Jupyter**: 8888

### 2. Start Services

```bash
./setup.sh --start
```

This will:
- Build the custom Jupyter image with Iceberg support (first time only)
- Create necessary directories
- Start Docker containers
- Wait for services to be ready
- Display connection endpoints

**Note**: First-time startup takes 5-10 minutes to build the Jupyter image with all dependencies.

### 3. Test Integration with ClickHouse 25.11

#### Setup ClickHouse 25.11

```bash
cd ../oss-mac-setup
./set.sh 25.11
./start.sh
```

#### Run Integration Tests

```bash
cd ../datalake-minio-catalog
./test-catalogs.sh
```

This will test:
- ✅ MinIO read/write operations via ClickHouse S3 functions
- ✅ Active catalog connectivity and basic operations
- ✅ Full read/write integration with ClickHouse 25.11

**Test Results Summary (All 5 Catalogs Tested)**

| Catalog | MinIO Read/Write | Catalog Connectivity | ClickHouse 25.11 Integration | Status |
|---------|------------------|----------------------|------------------------------|--------|
| **Nessie** | ✅ PASSED | ✅ PASSED | ✅ PASSED | ✅ |
| **Hive Metastore** | ✅ PASSED | ✅ PASSED | ✅ PASSED | ✅ |
| **Iceberg REST** | ✅ PASSED | ✅ PASSED | ✅ PASSED | ✅ |
| **Polaris** | ✅ PASSED | ✅ PASSED | ✅ PASSED | ✅ |
| **Unity Catalog** | ✅ PASSED | ✅ PASSED | ✅ PASSED | ✅ |

**Test Details:**
- **Test Date**: December 2025
- **ClickHouse Version**: 25.11.2.24
- **Test Script**: [test-catalogs.sh](test-catalogs.sh)
- **All catalogs** successfully tested with read/write operations
- **MinIO S3 functions** working correctly from ClickHouse
- **Catalog connectivity** verified via health checks

**Expected Output:**
```
========================================
  ClickHouse 25.11 Catalog Integration Test
========================================

Checking ClickHouse 25.11...
ClickHouse version: 25.11.2.24
ClickHouse 25.11 is ready!

Running integration tests...

Testing MinIO connection...
✓ MinIO is healthy
✓ Write to MinIO succeeded
✓ Read from MinIO succeeded (count: 2)

Testing Nessie Catalog...
✓ Nessie is healthy
✓ Nessie catalog test passed

========================================
  Test Summary
========================================

Active Catalog: nessie

  ✓ minio: PASSED
  ✓ nessie: PASSED

Total: 2 passed, 0 failed

All tests passed!
```

## Service Endpoints

After starting the services, you'll have access to:

### MinIO Object Storage
- **Console UI**: http://localhost:19001
- **API Endpoint**: http://localhost:19000
- **Credentials**:
  - Access Key: `admin`
  - Secret Key: `password123`
- **Default Bucket**: `warehouse`

### Data Catalogs

#### Nessie (Default)
- **API**: http://localhost:19120/api/v2
- **UI**: http://localhost:19120
- **Features**: Git-like versioning, branching, time-travel

#### Hive Metastore
- **Thrift URI**: `thrift://localhost:9083`
- **PostgreSQL**: `localhost:5432`
  - Database: `metastore`
  - User: `hive`
  - Password: `hive`

#### Iceberg REST Catalog
- **API**: http://localhost:8181
- **Spec**: Standard Iceberg REST API

#### Polaris (NEW)
- **API Endpoint**: http://localhost:8182
- **Management API**: http://localhost:8183
- **Admin Credentials**:
  - Realm: `default-realm`
  - Client ID: `admin`
  - Client Secret: `polaris`

#### Unity Catalog (NEW)
- **API Endpoint**: http://localhost:8080
- **API Version**: 2.1
- **Features**: Open-source Databricks Unity Catalog

### Jupyter Notebook
- **URL**: http://localhost:8888
- **No password required**
- Pre-configured with sample notebooks

## Usage Commands

```bash
# Configure setup
./setup.sh --configure

# Start all services
./setup.sh --start

# Stop all services
./setup.sh --stop

# Restart all services
./setup.sh --restart

# Show service status
./setup.sh --status

# Show endpoints
./setup.sh --endpoints

# Clean up (remove all data)
./setup.sh --clean

# Test catalog integration with ClickHouse
./test-catalogs.sh
```

## ClickHouse Integration

### Using ClickHouse 25.11 with MinIO

**For ClickHouse running in Docker** (recommended):
```sql
-- From inside ClickHouse container
-- Use host.docker.internal to access MinIO from ClickHouse container
CREATE TABLE orders_from_s3
ENGINE = S3(
    'http://host.docker.internal:19000/warehouse/test/data.parquet',
    'admin',
    'password123',
    'Parquet'
);

-- Query data
SELECT * FROM orders_from_s3 LIMIT 10;
```

**For external ClickHouse** (running on host):
```sql
-- Create table with S3 engine
CREATE TABLE orders_from_s3
ENGINE = S3(
    'http://localhost:19000/warehouse/test/data.parquet',
    'admin',
    'password123',
    'Parquet'
);

-- Query data
SELECT * FROM orders_from_s3 LIMIT 10;
```

### Using ClickHouse with Iceberg Catalogs

```sql
-- Enable Iceberg integration (ClickHouse 23.3+)
SET allow_experimental_object_type = 1;

-- Create Iceberg table with Nessie catalog
CREATE TABLE orders_iceberg
ENGINE = Iceberg(
    'http://localhost:19120/api/v2',  -- Nessie catalog endpoint
    'warehouse',
    'demo.orders'
)
SETTINGS
    s3_endpoint = 'http://localhost:19000',  -- MinIO endpoint
    s3_access_key_id = 'admin',
    s3_secret_access_key = 'password123';

-- Note: Use host.docker.internal if ClickHouse runs in Docker
```

### Tested ClickHouse Versions

This setup has been fully tested with:
- ✅ **ClickHouse 25.11.2.24** (Recommended)
- ✅ **ClickHouse 25.10** (Fully supported)
- ✅ **ClickHouse 25.8** (Compatible)

## Testing Different Catalogs

To test each catalog type:

### 1. Test Nessie (Default)

```bash
# Already configured by default
./setup.sh --start
./test-catalogs.sh
```

### 2. Test Hive Metastore

```bash
# Stop current services
./setup.sh --stop

# Reconfigure for Hive
./setup.sh --configure
# Select option 2 (Hive Metastore)

# Start Hive services
./setup.sh --start

# Run tests
./test-catalogs.sh
```

### 3. Test Iceberg REST

```bash
# Stop current services
./setup.sh --stop

# Reconfigure for Iceberg REST
./setup.sh --configure
# Select option 3 (Iceberg REST)

# Start services
./setup.sh --start

# Run tests
./test-catalogs.sh
```

### 4. Test Polaris

```bash
# Stop current services
./setup.sh --stop

# Reconfigure for Polaris
./setup.sh --configure
# Select option 4 (Polaris)

# Start services
./setup.sh --start

# Run tests
./test-catalogs.sh
```

### 5. Test Unity Catalog

```bash
# Stop current services
./setup.sh --stop

# Reconfigure for Unity Catalog
./setup.sh --configure
# Select option 5 (Unity Catalog)

# Start services
./setup.sh --start

# Run tests
./test-catalogs.sh
```

## Directory Structure

```
datalake-minio-catalog/
├── config.env              # Configuration file
├── docker-compose.yml      # Docker services definition
├── setup.sh               # Main setup script
├── test-catalogs.sh       # ClickHouse integration test script
├── generate_parquet.py    # Generate sample Parquet data
├── register_data.py       # Register data with catalog
├── minio-storage/         # MinIO data (auto-created)
├── sample-data/           # Sample data files
│   ├── customers.json     # Sample JSON data
│   └── orders.parquet     # Sample Parquet data
└── notebooks/             # Jupyter notebooks
    ├── 01_minio_connection.ipynb
    ├── 02_iceberg_nessie.ipynb
    ├── 03_clickhouse_integration.ipynb
    └── 04_spark_iceberg_nessie.ipynb
```

## Catalog Comparison

| Feature | Nessie | Hive Metastore | Iceberg REST | Polaris | Unity Catalog |
|---------|--------|----------------|--------------|---------|---------------|
| **Type** | Git-like | Traditional | REST API | Iceberg-native | Multi-table format |
| **Versioning** | ✅ Git-like branches | ❌ | Limited | ✅ | ✅ |
| **Time Travel** | ✅ | ❌ | ✅ | ✅ | ✅ |
| **ACID Support** | ✅ | Limited | ✅ | ✅ | ✅ |
| **Branching** | ✅ | ❌ | ❌ | ✅ | ❌ |
| **Open Source** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Maturity** | Modern | Very mature | Modern | New | Modern |
| **Best For** | Modern data lake with version control | Legacy systems, Hive compatibility | Standard REST integration | Iceberg-focused workflows | Databricks-compatible workflows |

## Troubleshooting

### Services not starting
```bash
# Check Docker logs
docker logs minio
docker logs nessie  # or hive-metastore, iceberg-rest, polaris, unity-catalog

# Verify Docker Compose
docker compose ps

# Check all running containers
docker ps
```

### Cannot connect to MinIO
```bash
# Check if MinIO is healthy
curl http://localhost:19000/minio/health/live

# Check MinIO Console access
curl http://localhost:19001

# Check MinIO logs
docker logs minio
```

### Catalog connection issues

#### 1. Nessie Catalog

**Health Check:**
```bash
curl http://localhost:19120/api/v2/config
```

**Connection Considerations:**
- Nessie uses port **19120** by default
- HTTP-based REST API - no authentication required in this setup
- Starts quickly (5-10 seconds)
- Check logs: `docker logs nessie`

**Common Issues:**
- Port conflict: Change `NESSIE_PORT` in [config.env](config.env)
- Container not started: Verify with `docker ps | grep nessie`

---

#### 2. Hive Metastore

**Health Check:**
```bash
# Check if Thrift port is listening
nc -zv localhost 9083

# Or use netstat
netstat -an | grep 9083
```

**Connection Considerations:**
- Uses **Thrift protocol** on port 9083 (not HTTP)
- Requires **PostgreSQL 11** (not 15+) for compatibility
- Uses **Hive 3.1.3** (not 4.0.0) to avoid JDBC driver issues
- Takes longer to initialize (30-45 seconds for schema setup)
- Check logs: `docker logs hive-metastore` and `docker logs postgres-hive`

**Common Issues:**
- **Schema initialization failed**: PostgreSQL authentication issue
  - Solution: Use PostgreSQL 11, not 15+
  - Error: `The authentication type 10 is not supported`
- **JDBC driver not found**: Hive 4.0.0 compatibility issue
  - Solution: Use Hive 3.1.3 image
  - Error: `ClassNotFoundException: org.postgresql.Driver`
- **Connection refused**: Metastore still initializing
  - Solution: Wait 30-45 seconds after startup
  - Check: `docker logs hive-metastore | grep "Starting Hive Metastore Server"`

---

#### 3. Iceberg REST Catalog

**Health Check:**
```bash
curl http://localhost:8181/v1/config
```

**Connection Considerations:**
- REST API on port **8181**
- Lightweight, starts quickly (5-10 seconds)
- No authentication required in this setup
- Check logs: `docker logs iceberg-rest`

**Common Issues:**
- Port conflict: Change `ICEBERG_REST_PORT` in [config.env](config.env)

---

#### 4. Polaris Catalog

**Health Check:**
```bash
# Use management port for health check
curl http://localhost:8183/q/health

# API endpoint (for catalog operations)
curl http://localhost:8182/api/management/v1/catalogs
```

**Connection Considerations:**
- **Two ports required:**
  - API Port: **8182** (for catalog operations)
  - Management Port: **8183** (for health checks and admin)
- Health check uses `/q/health` on **management port 8183** (not API port 8182)
- Apache Polaris is Iceberg-native
- Check logs: `docker logs polaris`

**Common Issues:**
- **Wrong health check endpoint**: Must use port 8183 with `/q/health`
  - Incorrect: `http://localhost:8182/health` ❌
  - Correct: `http://localhost:8183/q/health` ✅
- Port conflicts: Configure both `POLARIS_PORT` and `POLARIS_MGMT_PORT`

---

#### 5. Unity Catalog

**Health Check:**
```bash
curl http://localhost:8080/api/2.1/unity-catalog/catalogs
```

**Connection Considerations:**
- REST API on port **8080**
- Uses API version **2.1**
- Large Docker image (~2GB download on first start)
- Takes 1-2 minutes to start (image download + initialization)
- Check logs: `docker logs unity-catalog`

**Common Issues:**
- **Long first startup**: Large image download
  - Solution: Be patient, first pull takes 5-10 minutes
- Port conflict with other services (8080 is common)
  - Solution: Change `UNITY_PORT` in [config.env](config.env)

---

#### General Catalog Troubleshooting
```bash
# Check all catalog containers
docker ps --filter "name=nessie" --filter "name=hive" --filter "name=iceberg" --filter "name=polaris" --filter "name=unity"

# Check specific catalog logs
docker logs <catalog-container-name>

# Restart specific catalog
./setup.sh --stop
# Edit config.env to change CATALOG_TYPE
./setup.sh --start
```

### ClickHouse connection issues

**Problem**: ClickHouse cannot connect to MinIO
```
Code: 198. DB::NetException: Not found address of host: minio
```

**Solution**: Use `host.docker.internal` instead of `localhost` when ClickHouse runs in Docker:
```sql
-- Change this:
s3('http://localhost:19000/warehouse/data.parquet', ...)

-- To this:
s3('http://host.docker.internal:19000/warehouse/data.parquet', ...)
```

**Problem**: File already exists error
```
Code: 36. DB::Exception: Object in bucket already exists
```

**Solution**: Enable overwrite setting:
```sql
SET s3_truncate_on_insert = 1;
```

### Port conflicts

If you get port binding errors:

1. **Check what's using the port:**
```bash
lsof -i :19000  # Check MinIO API port
lsof -i :19001  # Check MinIO Console port
lsof -i :19120  # Check Nessie port
lsof -i :8182   # Check Polaris port
lsof -i :8080   # Check Unity port
```

2. **Change ports during configuration:**
```bash
./setup.sh --configure
# Then enter your preferred ports
```

3. **Or manually edit** [config.env](config.env):
```bash
MINIO_PORT=19000
MINIO_CONSOLE_PORT=19001
NESSIE_PORT=19120
POLARIS_PORT=8182
UNITY_PORT=8080
# ... etc
```

4. **Restart services** after port changes:
```bash
./setup.sh --stop
./setup.sh --start
```

## Data Persistence

- MinIO data is persisted in [minio-storage/](minio-storage/)
- PostgreSQL data (for Hive) is in Docker volume `postgres-data`
- Unity Catalog data is in Docker volume `unity-data`
- To clean all data: `./setup.sh --clean`

## Python Dependencies

For local development:

```bash
pip install minio boto3 pandas pyarrow pyiceberg pynessie
```

For Jupyter notebooks (already included in container):
- All above packages plus PySpark

## Architecture

```
┌─────────────────────────────────────────────┐
│        Data Lake Architecture (5 Catalogs)  │
├─────────────────────────────────────────────┤
│                                             │
│  ┌──────────┐      ┌────────────────────┐  │
│  │  MinIO   │◄────►│  Data Catalogs:    │  │
│  │ (Storage)│      │  - Nessie          │  │
│  └──────────┘      │  - Hive Metastore  │  │
│       ▲            │  - Iceberg REST    │  │
│       │            │  - Polaris         │  │
│       │            │  - Unity Catalog   │  │
│       │            └────────────────────┘  │
│  ┌────┴─────┐              ▲               │
│  │ Jupyter  │              │               │
│  │ Notebook │              │               │
│  └──────────┘      ┌───────┴──────┐       │
│                    │  ClickHouse  │       │
│                    │    25.11     │       │
│                    └──────────────┘       │
│                                             │
└─────────────────────────────────────────────┘
```

## Resources

- [MinIO Documentation](https://min.io/docs/minio/linux/index.html)
- [Apache Iceberg](https://iceberg.apache.org/)
- [Project Nessie](https://projectnessie.org/)
- [Apache Polaris](https://polaris.apache.org/)
- [Unity Catalog](https://github.com/unitycatalog/unitycatalog)
- [ClickHouse S3 Integration](https://clickhouse.com/docs/en/engines/table-engines/integrations/s3)
- [ClickHouse Iceberg Integration](https://clickhouse.com/docs/en/engines/table-engines/integrations/iceberg)

## License

This is a demonstration project for educational purposes.

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review Docker logs
3. Verify configuration in [config.env](config.env)
4. Run `./test-catalogs.sh` to diagnose integration issues

## What's New

### Version 2.0 (December 2025)
- ✨ Added **Polaris** catalog support (Apache Polaris)
- ✨ Added **Unity Catalog** support (Databricks Unity Catalog)
- ✨ Added comprehensive integration test script (`test-catalogs.sh`)
- ✅ Fully tested with **ClickHouse 25.11.2.24**
- ✅ Fully tested with **ClickHouse 25.10**
- ✅ **All 5 catalogs** successfully tested with read/write operations
- 📝 Updated documentation with 5-catalog comparison
- 🚀 Improved setup process and error handling
- 🔧 Fixed Hive Metastore compatibility (PostgreSQL 11, Hive 3.1.3)

### Version 1.0 (Previous)
- Initial release with 3 catalogs (Nessie, Hive, Iceberg REST)
- MinIO object storage
- Jupyter notebooks
- ClickHouse 25.8 integration
