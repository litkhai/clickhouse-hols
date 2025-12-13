# PySpark + Iceberg + Nessie Setup

## Overview

This setup provides a complete PySpark environment with Apache Iceberg and Nessie catalog integration.

## What's Included

### Custom Jupyter Image
- **Base**: `jupyter/pyspark-notebook:latest`
- **Iceberg JARs**: Spark runtime, AWS bundle, Hadoop AWS
- **Python Packages**: PyIceberg, PyNessie, MinIO client, Boto3
- **Spark Configuration**: Pre-configured for Nessie catalog

### Key Components

1. **Dockerfile.jupyter**
   - Custom image with all Iceberg dependencies
   - Pre-installed Python packages
   - Automatic Spark configuration

2. **spark-defaults.conf**
   - Nessie catalog configuration
   - S3/MinIO connection settings
   - Iceberg extensions

3. **Notebook: 04_spark_iceberg_nessie.ipynb**
   - Complete working examples
   - CRUD operations
   - Schema evolution
   - Time travel queries
   - Nessie branching

## Port Configuration

The setup uses the following ports:

- **MinIO API**: 19000 (changed from default 9000)
- **MinIO Console**: 19001 (changed from default 9001)
- **Nessie**: 19120
- **Jupyter**: 8888

## First Time Setup

### 1. Build the Image

The first time you start services, Docker will build the custom Jupyter image:

```bash
./setup.sh --start
```

This takes **5-10 minutes** as it downloads:
- Iceberg Spark runtime JARs
- AWS SDK bundles
- Hadoop AWS connectors
- Python packages

### 2. Verify Build

Check that the Jupyter container is running:

```bash
docker ps | grep jupyter
```

You should see the container with a healthy status.

### 3. Access Jupyter

Open http://localhost:8888 in your browser (no password required).

## Using PySpark with Iceberg

### Quick Start

Open notebook `04_spark_iceberg_nessie.ipynb` and run all cells. This notebook demonstrates:

1. **Create Spark Session**
   ```python
   from pyspark.sql import SparkSession

   spark = SparkSession.builder \
       .appName("IcebergNessieDemo") \
       .getOrCreate()
   ```

2. **Create Tables**
   ```python
   df.writeTo("nessie.demo.orders") \
       .using("iceberg") \
       .createOrReplace()
   ```

3. **Query Data**
   ```sql
   SELECT * FROM nessie.demo.orders LIMIT 10
   ```

4. **CRUD Operations**
   - INSERT: `.append()`
   - UPDATE: `UPDATE nessie.demo.orders SET ...`
   - DELETE: `DELETE FROM nessie.demo.orders WHERE ...`

5. **Schema Evolution**
   ```sql
   ALTER TABLE nessie.demo.orders
   ADD COLUMN discount DOUBLE
   ```

6. **Time Travel**
   ```sql
   SELECT * FROM nessie.demo.orders.history
   SELECT * FROM nessie.demo.orders.snapshots
   ```

## Configuration Details

### Spark Catalog (spark-defaults.conf)

```properties
# Nessie Catalog
spark.sql.catalog.nessie=org.apache.iceberg.spark.SparkCatalog
spark.sql.catalog.nessie.catalog-impl=org.apache.iceberg.nessie.NessieCatalog
spark.sql.catalog.nessie.uri=http://nessie:19120/api/v2
spark.sql.catalog.nessie.warehouse=s3://warehouse/

# S3/MinIO Connection
spark.hadoop.fs.s3a.endpoint=http://minio:9000
spark.hadoop.fs.s3a.access.key=admin
spark.hadoop.fs.s3a.secret.key=password123
spark.hadoop.fs.s3a.path.style.access=true
```

### Environment Variables

Set in docker-compose.yml:

```yaml
environment:
  - AWS_ACCESS_KEY_ID=admin
  - AWS_SECRET_ACCESS_KEY=password123
  - AWS_REGION=us-east-1
  - SPARK_CLASSPATH=/usr/local/spark/jars/*
```

## Troubleshooting

### ClassNotFoundException: org.apache.iceberg.spark.SparkCatalog

**Problem**: Iceberg JARs not found in classpath.

**Solution**: Rebuild the Jupyter container:
```bash
docker-compose down
docker-compose up --build -d
```

### Cannot connect to Nessie

**Problem**: Nessie service not reachable.

**Solution**:
1. Check Nessie is running: `docker ps | grep nessie`
2. Check network: `docker network ls | grep datalake`
3. Verify Nessie health: `curl http://localhost:19120/api/v2/config`

### S3 Connection Failed

**Problem**: Cannot connect to MinIO.

**Solution**:
1. Verify MinIO is running: `curl http://localhost:19000/minio/health/live`
2. Check credentials in spark-defaults.conf match config.env
3. Ensure path-style access is enabled

### Permission Denied on JARs

**Problem**: Spark cannot load JAR files.

**Solution**:
```bash
docker exec -it jupyter bash
ls -la /usr/local/spark/jars/iceberg-*
# Should show readable files
```

## JAR Dependencies

The custom image includes these JARs in `/usr/local/spark/jars/`:

1. `iceberg-spark-runtime-3.5_2.12-1.5.0.jar` - Main Iceberg Spark integration
2. `iceberg-aws-bundle-1.5.0.jar` - AWS S3 support for Iceberg
3. `hadoop-aws-3.3.4.jar` - Hadoop S3A filesystem
4. `aws-java-sdk-bundle-1.12.262.jar` - AWS SDK v1
5. `bundle-2.20.18.jar` - AWS SDK v2 bundle
6. `url-connection-client-2.20.18.jar` - AWS SDK v2 HTTP client

## Testing Your Setup

### 1. Test Spark Session

```python
from pyspark.sql import SparkSession
spark = SparkSession.builder.appName("test").getOrCreate()
print(spark.version)
```

### 2. Test Catalog Connection

```python
spark.sql("SHOW CATALOGS").show()
# Should show 'nessie' catalog
```

### 3. Test S3 Access

```python
df = spark.read.parquet("s3a://warehouse/data/orders.parquet")
df.show(5)
```

### 4. Test Iceberg Table Creation

```python
spark.sql("CREATE NAMESPACE IF NOT EXISTS nessie.test")
spark.sql("""
    CREATE TABLE nessie.test.dummy (
        id INT,
        name STRING
    ) USING iceberg
""")
spark.sql("DROP TABLE nessie.test.dummy")
```

## Rebuilding After Changes

If you modify Dockerfile.jupyter or spark-defaults.conf:

```bash
# Stop services
./setup.sh --stop

# Rebuild and start
docker-compose up --build -d

# Or use the setup script
./setup.sh --start
```

## Performance Tips

1. **Increase Spark Memory** (if needed):
   Add to spark-defaults.conf:
   ```properties
   spark.driver.memory=4g
   spark.executor.memory=4g
   ```

2. **Enable Partition Pruning**:
   ```properties
   spark.sql.iceberg.planning.preserve-data-grouping=true
   ```

3. **Configure S3A Performance**:
   ```properties
   spark.hadoop.fs.s3a.connection.maximum=200
   spark.hadoop.fs.s3a.threads.max=20
   ```

## References

- [Apache Iceberg Documentation](https://iceberg.apache.org/)
- [Nessie Documentation](https://projectnessie.org/)
- [PySpark SQL Guide](https://spark.apache.org/docs/latest/sql-programming-guide.html)
- [Iceberg Spark Integration](https://iceberg.apache.org/docs/latest/spark-getting-started/)

## Next Steps

1. Open Jupyter at http://localhost:8888
2. Navigate to `work/04_spark_iceberg_nessie.ipynb`
3. Run all cells to see complete examples
4. Experiment with your own data and queries!
