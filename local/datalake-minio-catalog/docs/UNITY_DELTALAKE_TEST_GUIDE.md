# Unity Catalog + MinIO Health / Storage Check Guide

## Overview

> **Updated 2026-11-04.** `tests/test-unity-deltalake.sh` is a health / storage check, not a catalog-integration test. It checks that the Unity Catalog API answers and that ClickHouse can write and read plain Parquet on MinIO with `s3()`. ClickHouse does not read through Unity, and no Delta Lake engine is used. The check that ClickHouse reads seeded rows through Unity (`DataLakeCatalog`) is `tests/test-datalakecatalog.sh unity` (ClickHouse 26.10.3.7). The 2025-12-13 25.10 / 25.11 results in [COMPARISON-25.10-vs-25.11.md](COMPARISON-25.10-vs-25.11.md) came from the earlier version of this script and were not re-run.

This guide describes how to run the check against any ClickHouse container.

## Prerequisites

### Required Components

1. **Docker & Docker Compose**
   - Docker Desktop installed and running
   - Minimum 8GB RAM allocated to Docker

2. **A ClickHouse container**
   - Running in Docker
   - Named `clickhouse-25-10` or `clickhouse-25-11`, or pass its name in `CLICKHOUSE_CONTAINER`
   - It reaches MinIO at `host.docker.internal:<MINIO_PORT>`

3. **Unity Catalog**
   - Started via this project's setup script
   - Running on port 8080 (default)

4. **MinIO Object Storage**
   - Running on port 19000 (API) and 19001 (Console)
   - Configured for S3-compatible access

## Quick Start

### Step 1: Configure Unity Catalog

```bash
cd local/datalake-minio-catalog

# Configure for Unity Catalog (option 5)
./setup.sh --configure

# Start all services
./setup.sh --start
```

When prompted:
- **MinIO storage size**: `20G` (or as needed)
- **MinIO API port**: `19000`
- **MinIO Console port**: `19001`
- **Catalog Type**: Select `5` for Unity Catalog
- **Unity Catalog port**: `8080`

### Step 2: Start ClickHouse (25.10 / 25.11 containers are found automatically; otherwise set `CLICKHOUSE_CONTAINER`)

```bash
# For ClickHouse 25.11
cd ../oss-docker
./set.sh 25.11
./start.sh

# OR for ClickHouse 25.10
cd ../oss-docker
./set.sh 25.10
./start.sh
```

### Step 3: Verify Services

```bash
# Check service status
./setup.sh --status

# Expected output:
# - minio (port 19000, 19001)
# - unity-catalog (port 8080)
# - jupyter (port 8888)
```

### Step 4: Run the check

```bash
cd local/datalake-minio-catalog

# CATALOG_TYPE=unity, CLICKHOUSE_CONTAINER, MINIO_PORT, UNITY_PORT can come from the environment
./tests/test-unity-deltalake.sh
```

The report is written next to the script as `tests/test-results-unity-deltalake-<timestamp>.md` (git-ignored).

## Test Coverage

The script runs the following checks:

### 1. Unity Catalog - Basic Connectivity
- Tests API connectivity to Unity Catalog
- Validates catalog listing functionality

### 2. ClickHouse - Create source table
- Creates a `Memory` source table in ClickHouse (Unity is not involved)

### 3. MinIO - Write Parquet with s3()
- Writes data from ClickHouse to MinIO as a plain Parquet file (no Delta log)
- Tests S3-compatible storage operations

### 4. MinIO - Read Parquet with s3()
- Reads Parquet data from MinIO
- Validates data integrity
- Performs aggregations

### 5. MinIO - Append a second Parquet file
- Writes a second file
- Validates incremental data loading

### 6. MinIO - Query Parquet with filters
- Tests filter pushdown
- Validates WHERE clause optimization
- Performs aggregations on filtered data

### 7. MinIO - Parquet schema
- Validates schema inference
- Tests DESCRIBE TABLE functionality
- Checks data type mapping

### 8. MinIO - Large Parquet dataset
- Writes 10,000 rows
- Measures write/read performance
- Tests query performance on large datasets

### 9. MinIO - Parquet data types
- Tests all supported data types:
  - Integer types (Int8, Int16, Int32, Int64)
  - Floating point (Float32, Float64)
  - String
  - Date and DateTime
  - Boolean

### 10. Cleanup Test Resources
- Removes all test tables
- Cleans up test data

## Understanding Test Results

### Markdown Report

After test execution, a markdown report is generated with the following format:

```
test-results-unity-deltalake-YYYYMMDD-HHMMSS.md
```

The report includes:
- **Environment Information**: ClickHouse version, ports, configuration
- **Test Summary**: Pass/fail/skip counts, total execution time
- **Test Results**: Detailed results for each test
- **Key Findings**: Overall assessment
- **Scope**: what the script does and does not check

### Success Criteria

✅ **All tests passed** indicates:
- The Unity Catalog API answers
- ClickHouse `s3()` can write and read plain Parquet on MinIO
- The listed data types round-trip through Parquet

It does **not** show that ClickHouse reads through Unity Catalog or that Delta Lake works; use `tests/test-datalakecatalog.sh unity` for that.

❌ **Some tests failed** indicates:
- Review the markdown report for details
- Check service logs for errors
- Verify network connectivity
- Ensure proper permissions

## Troubleshooting

### Issue: ClickHouse container not found

**Error:**
```
ClickHouse container not found (set CLICKHOUSE_CONTAINER, or start clickhouse-25-10/25-11)
```

**Solution:**
```bash
cd ../oss-docker
./set.sh 25.11  # or 25.10
./start.sh
```

### Issue: Unity Catalog not responding

**Error:**
```
Unity Catalog is not responding on port 8080
```

**Solution:**
```bash
# Check if Unity Catalog is the active catalog
cat config.env | grep CATALOG_TYPE

# If not unity, reconfigure:
./setup.sh --configure  # Select option 5
./setup.sh --restart
```

### Issue: MinIO connection failed

**Error:**
```
MinIO is not responding on port 19000
```

**Solution:**
```bash
# Restart MinIO
./setup.sh --restart

# Or check MinIO logs
docker logs minio
```

### Issue: Permission denied writing to S3

**Error:**
```
Access Denied (S3_ERROR)
```

**Solution:**
- Verify MinIO credentials in `config.env`
- Check MinIO bucket permissions:
  ```bash
  # The MinIO images have no shell; run one mc call with the alias in MC_HOST_myminio
  docker run --rm --network <compose-project>_datalake \
    -e MC_HOST_myminio=http://admin:password123@minio:9000 \
    --entrypoint /usr/bin/mc \
    cgr.dev/chainguard/minio-client@sha256:1dccd2a6fd59914a98ac2d9dad95e552c91243cb0bd7242aaa224802df4b3432 \
    ls myminio/warehouse
  ```

### Issue: Cannot connect to ClickHouse

**Error:**
```
Cannot connect to ClickHouse
```

**Solution:**
```bash
# Check ClickHouse status
docker ps | grep clickhouse

# Check ClickHouse logs
docker logs clickhouse-25-11  # or clickhouse-25-10

# Test connection
docker exec clickhouse-25-11 clickhouse-client --query "SELECT 1"
```

## Advanced Usage

### Running Specific Tests

To run individual tests, you can modify the main() function in the script:

```bash
# Edit test-unity-deltalake.sh
vim test-unity-deltalake.sh

# Comment out tests you don't want to run
# Example: comment test_performance_large_dataset
```

### Custom Data Volumes

To test with larger datasets:

```bash
# Edit the performance test section in test-unity-deltalake.sh
# Change: FROM numbers(10000)
# To: FROM numbers(1000000)  # 1 million rows
```

### Checking the Parquet files in MinIO

Access MinIO Console:
1. Open browser: http://localhost:19001
2. Login: admin / password123
3. Navigate to: warehouse/unity-catalog/delta-test/

Or use the MinIO client (the images have no shell, so run one `mc` call):
```bash
docker run --rm --network <compose-project>_datalake \
  -e MC_HOST_myminio=http://admin:password123@minio:9000 \
  --entrypoint /usr/bin/mc \
  cgr.dev/chainguard/minio-client@sha256:1dccd2a6fd59914a98ac2d9dad95e552c91243cb0bd7242aaa224802df4b3432 \
  ls myminio/warehouse/unity-catalog/delta-test/
```

## Versions and timings

No version comparison or timing table is kept here: the old 25.10 / 25.11 notes and the "expected performance" table were not backed by a recorded run. The 2025-12-13 results are in [COMPARISON-25.10-vs-25.11.md](COMPARISON-25.10-vs-25.11.md) (historical). The version the catalog read path was verified on is in the README.

## Integration with Spark

For Spark integration with Delta Lake and Unity Catalog, see:
- [SPARK_SETUP.md](SPARK_SETUP.md)
- Jupyter notebook: [04_spark_iceberg_nessie.ipynb](../notebooks/04_spark_iceberg_nessie.ipynb)

## Next Steps

After successful testing:

1. **Explore Delta Lake Features**
   - Time travel queries
   - ACID transactions
   - Schema evolution

2. **Production Deployment**
   - Configure production Unity Catalog
   - Set up proper authentication
   - Enable encryption

3. **Performance Tuning**
   - Optimize Parquet block size
   - Configure partition strategies
   - Tune S3 connection pools

4. **Monitoring**
   - Set up metrics collection
   - Configure alerting
   - Monitor query performance

## Resources

- [Unity Catalog Documentation](https://www.unitycatalog.io/)
- [Delta Lake Documentation](https://delta.io/)
- [ClickHouse S3 Integration](https://clickhouse.com/docs/en/engines/table-engines/integrations/s3)
- [MinIO Documentation](https://min.io/docs/minio/linux/index.html)

## Support

For issues or questions:
1. Check the troubleshooting section
2. Review service logs
3. Consult the markdown test report
4. Check ClickHouse documentation

---

*Last updated: 2026-11-04 (script relabelled as a health / storage check; first written 2025-12-13)*
