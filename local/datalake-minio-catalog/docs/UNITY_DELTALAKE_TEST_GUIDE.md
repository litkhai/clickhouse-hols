# Unity Catalog + Delta Lake Integration Test Guide

## Overview

This guide provides instructions for testing Unity Catalog and Delta Lake read/write operations with ClickHouse versions 25.10 and 25.11.

## Prerequisites

### Required Components

1. **Docker & Docker Compose**
   - Docker Desktop installed and running
   - Minimum 8GB RAM allocated to Docker

2. **ClickHouse 25.10 or 25.11**
   - Running in Docker container
   - Named as `clickhouse-25-10` or `clickhouse-25-11`

3. **Unity Catalog**
   - Started via this project's setup script
   - Running on port 8080 (default)

4. **MinIO Object Storage**
   - Running on port 19000 (API) and 19001 (Console)
   - Configured for S3-compatible access

## Quick Start

### Step 1: Configure Unity Catalog

```bash
cd /Users/kenlee/Documents/GitHub/clickhouse-hols/local/datalake-minio-catalog

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

### Step 2: Start ClickHouse 25.10 or 25.11

```bash
# For ClickHouse 25.11
cd ../oss-mac-setup
./set.sh 25.11
./start.sh

# OR for ClickHouse 25.10
cd ../oss-mac-setup
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

### Step 4: Run Integration Tests

```bash
cd /Users/kenlee/Documents/GitHub/clickhouse-hols/local/datalake-minio-catalog

# Execute the test suite
./test-unity-deltalake.sh
```

## Test Coverage

The test suite includes the following tests:

### 1. Unity Catalog - Basic Connectivity
- Tests API connectivity to Unity Catalog
- Validates catalog listing functionality

### 2. Unity Catalog - Create Delta Lake Table
- Creates a source table in ClickHouse
- Prepares data for Delta Lake export

### 3. Delta Lake - Write to MinIO (Parquet format)
- Writes data from ClickHouse to MinIO
- Uses Parquet format (Delta Lake compatible)
- Tests S3-compatible storage operations

### 4. Delta Lake - Read from MinIO
- Reads Parquet data from MinIO
- Validates data integrity
- Performs aggregations

### 5. Delta Lake - Append New Data
- Tests append operations
- Validates incremental data loading

### 6. Delta Lake - Query with Filters
- Tests filter pushdown
- Validates WHERE clause optimization
- Performs aggregations on filtered data

### 7. Delta Lake - Schema Validation
- Validates schema inference
- Tests DESCRIBE TABLE functionality
- Checks data type mapping

### 8. Delta Lake - Performance Test (Large Dataset)
- Writes 10,000 rows
- Measures write/read performance
- Tests query performance on large datasets

### 9. Delta Lake - Data Type Compatibility
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
- **Recommendations**: Version-specific recommendations

### Success Criteria

✅ **All tests passed** indicates:
- Unity Catalog integration is functional
- Delta Lake read operations work correctly
- Delta Lake write operations work correctly
- Performance is acceptable
- All data types are supported

❌ **Some tests failed** indicates:
- Review the markdown report for details
- Check service logs for errors
- Verify network connectivity
- Ensure proper permissions

## Troubleshooting

### Issue: ClickHouse container not found

**Error:**
```
ClickHouse 25.10 or 25.11 container not found
```

**Solution:**
```bash
cd ../oss-mac-setup
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
  docker exec -it minio-setup sh
  mc alias set myminio http://minio:9000 admin password123
  mc ls myminio/warehouse
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

### Checking Delta Lake Data in MinIO

Access MinIO Console:
1. Open browser: http://localhost:19001
2. Login: admin / password123
3. Navigate to: warehouse/unity-catalog/delta-test/

Or use MinIO CLI:
```bash
docker exec -it minio-setup sh
mc alias set myminio http://minio:9000 admin password123
mc ls myminio/warehouse/unity-catalog/delta-test/
```

## Version-Specific Notes

### ClickHouse 25.11
- Full Unity Catalog support
- Enhanced Delta Lake compatibility
- Improved Parquet read/write performance
- Better S3 integration

### ClickHouse 25.10
- Unity Catalog support available
- Delta Lake read/write functional
- Standard Parquet support
- S3 integration stable

## Performance Benchmarks

Expected performance on standard hardware (M1 Mac, 16GB RAM):

| Test | Rows | Write Time | Read Time | Total Time |
|------|------|------------|-----------|------------|
| Basic Write | 5 | <1s | <1s | 1-2s |
| Basic Read | 5 | N/A | <1s | <1s |
| Large Dataset | 10,000 | 2-3s | 1-2s | 3-5s |
| Query with Filters | 10,000 | N/A | 1-2s | 1-2s |

## Integration with Spark

For Spark integration with Delta Lake and Unity Catalog, see:
- [SPARK_SETUP.md](SPARK_SETUP.md)
- Jupyter notebook: [04_spark_iceberg_nessie.ipynb](notebooks/04_spark_iceberg_nessie.ipynb)

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

*Last updated: 2025-12-13*
