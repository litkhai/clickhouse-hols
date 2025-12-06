# Data Lake with MinIO and Catalog

A complete setup for running a local data lake environment with MinIO object storage and choice of data catalogs (Nessie, Hive Metastore, or Iceberg REST).

**🔗 Integrated with:** [ClickHouse 25.8 Lab](../25.8/) - This data lake is automatically deployed when running the ClickHouse 25.8 lab for testing MinIO integration and new Parquet reader features.

## Features

- **MinIO Object Storage**: S3-compatible object storage (ports 19000 API, 19001 Console)
- **Multiple Catalog Options**:
  - **Nessie** (Default): Git-like catalog with branching and versioning (port 19120)
  - **Hive Metastore**: Traditional, widely-supported catalog (port 9083)
  - **Iceberg REST**: Standard REST API catalog (port 8181)
- **Apache Iceberg**: Table format for huge analytic datasets
- **Jupyter Notebooks**: Interactive data exploration (port 8888)
- **Sample Data**: Pre-loaded JSON and Parquet files
- **ClickHouse Integration**: Ready to use with ClickHouse 25.8+ for data lake analytics

## Prerequisites

- Docker and Docker Compose
- Python 3.8+ (for data generation scripts)
- 20GB+ disk space (configurable)

## Quick Start

### 1. Configure the Setup

```bash
./setup.sh --configure
```

This will prompt you to:
- Set MinIO storage size (default: 20GB)
- Configure MinIO ports (default: 19000 API, 19001 Console)
- Choose data catalog: Nessie (1), Hive (2), or Iceberg REST (3)
- Configure catalog-specific ports

**Default Port Configuration:**
- **MinIO API**: 19000 (compatible with ClickHouse 25.8 lab)
- **MinIO Console**: 19001
- **Nessie**: 19120
- **Hive Metastore**: 9083
- **PostgreSQL** (for Hive): 5432
- **Iceberg REST**: 8181
- **Jupyter**: 8888

### 2. Generate Sample Data

```bash
# Install Python dependencies
pip install pandas pyarrow

# Generate Parquet file
python3 generate_parquet.py
```

### 3. Start Services

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

### 4. Register Sample Data

```bash
# Install Python dependencies
pip install minio pyiceberg

# Upload and register data
python3 register_data.py
```

## Service Endpoints

After starting the services, you'll have access to:

### MinIO Object Storage
- **Console UI**: http://localhost:19001 (default port, configurable)
- **API Endpoint**: http://localhost:19000 (default port, configurable)
- **Credentials**:
  - Access Key: `admin`
  - Secret Key: `password123`
- **Default Bucket**: `warehouse`

**Note**: Ports 19000/19001 are used by default for compatibility with ClickHouse 25.8 lab. You can change these during `./setup.sh --configure`.

### Data Catalogs

#### Nessie (Default)
- **API**: http://localhost:19120/api/v2 (default port, configurable)
- **UI**: http://localhost:19120
- **Features**: Git-like versioning, branching, time-travel

#### Hive Metastore
- **Thrift URI**: `thrift://localhost:9083` (default port, configurable)
- **PostgreSQL**: `localhost:5432` (default port, configurable)
  - Database: `metastore`
  - User: `hive`
  - Password: `hive`

#### Iceberg REST Catalog
- **API**: http://localhost:8181
- **Spec**: Standard Iceberg REST API

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
```

## Directory Structure

```
datalake-minio-catalog/
├── config.env              # Configuration file
├── docker-compose.yml      # Docker services definition
├── setup.sh               # Main setup script
├── generate_parquet.py    # Generate sample Parquet data
├── register_data.py       # Register data with catalog
├── minio-storage/         # MinIO data (auto-created)
├── sample-data/           # Sample data files
│   ├── customers.json     # Sample JSON data
│   └── orders.parquet     # Sample Parquet data
└── notebooks/             # Jupyter notebooks
    ├── 01_minio_connection.ipynb
    └── 02_iceberg_nessie.ipynb
```

## Sample Data

### customers.json
JSON file with 10 customer records including:
- customer_id, name, email, age
- city, registration_date, lifetime_value

### orders.parquet
Parquet file with 100 order records including:
- order_id, customer_id, product_name
- quantity, unit_price, total_amount
- order_date, status

## Python Connection Examples

### MinIO Connection

```python
from minio import Minio

# Note: Use port 19000 (default), or your configured port
client = Minio(
    "localhost:19000",  # Default port for ClickHouse 25.8 compatibility
    access_key="admin",
    secret_key="password123",
    secure=False
)

# List buckets
buckets = client.list_buckets()
for bucket in buckets:
    print(bucket.name)
```

### Iceberg with Nessie

```python
from pyiceberg.catalog import load_catalog

# Note: Use configured ports (defaults: 19120 for Nessie, 19000 for MinIO)
catalog = load_catalog(
    "nessie",
    **{
        "uri": "http://localhost:19120/api/v2",  # Nessie API
        "warehouse": "s3://warehouse/",
        "s3.endpoint": "http://localhost:19000",  # MinIO API
        "s3.access-key-id": "admin",
        "s3.secret-access-key": "password123",
        "s3.path-style-access": "true",
    }
)

# Load table
table = catalog.load_table("demo.orders")
df = table.scan().to_pandas()
```

### Using boto3 (S3-compatible)

```python
import boto3

# Note: Use port 19000 (default), or your configured port
s3 = boto3.client(
    's3',
    endpoint_url='http://localhost:19000',  # MinIO API endpoint
    aws_access_key_id='admin',
    aws_secret_access_key='password123'
)

# List objects
response = s3.list_objects_v2(Bucket='warehouse')
```

## ClickHouse Integration

### Using ClickHouse with MinIO

**For external ClickHouse** (running on host):
```sql
-- Create table with S3 engine using default ports
CREATE TABLE orders_from_s3
ENGINE = S3(
    'http://localhost:19000/warehouse/data/orders.parquet',
    'admin',
    'password123',
    'Parquet'
);

-- Query data
SELECT * FROM orders_from_s3 LIMIT 10;
```

**For ClickHouse running in Docker** (e.g., ClickHouse 25.8 lab):
```sql
-- Use host.docker.internal to access MinIO from ClickHouse container
CREATE TABLE orders_from_s3
ENGINE = S3(
    'http://host.docker.internal:19000/warehouse/data/orders.parquet',
    'admin',
    'password123',
    'Parquet'
);
```

**For comprehensive examples**, see the [ClickHouse 25.8 Lab](../25.8/) which includes:
- 10 test scenarios with MinIO integration
- 50,000 sample e-commerce orders
- Parquet export/import workflows
- Analytics queries on data lake

### Using ClickHouse with Iceberg

```sql
-- Enable Iceberg integration (requires ClickHouse 23.3+)
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

## Jupyter Notebooks

The setup includes pre-configured Jupyter notebooks:

1. **01_minio_connection.ipynb**
   - Connect to MinIO
   - Read JSON and Parquet files
   - Basic data analysis

2. **02_iceberg_nessie.ipynb**
   - Configure Nessie catalog (PyIceberg)
   - Query Iceberg tables
   - Work with Nessie branches

3. **03_clickhouse_integration.ipynb**
   - Connect ClickHouse to MinIO
   - Query data via S3 functions

4. **04_spark_iceberg_nessie.ipynb** ⭐ **Recommended**
   - Full PySpark + Iceberg + Nessie integration
   - Create tables, insert, update, delete
   - Schema evolution and time travel
   - Git-like branching

Access Jupyter at: http://localhost:8888

## Troubleshooting

### Services not starting
```bash
# Check Docker logs
docker logs minio
docker logs nessie  # or hive-metastore, iceberg-rest

# Verify Docker Compose
docker compose ps

# Check all running containers
docker ps
```

### Cannot connect to MinIO
```bash
# Check if MinIO is healthy (use your configured port)
curl http://localhost:19000/minio/health/live

# Check MinIO Console access
curl http://localhost:19001

# Check MinIO logs
docker logs minio

# Verify MinIO is listening on correct ports
docker port minio
```

### Catalog connection issues
```bash
# For Nessie (default port 19120)
curl http://localhost:19120/api/v2/config

# For Iceberg REST (default port 8181)
curl http://localhost:8181/v1/config

# For Hive Metastore (port 9083)
netstat -an | grep 9083

# Check catalog logs
docker logs nessie  # or iceberg-rest, hive-metastore
```

### ClickHouse connection issues

**Problem**: ClickHouse cannot connect to MinIO
```
Code: 198. DB::NetException: Not found address of host: minio
```

**Solution**: Use `host.docker.internal` instead of `localhost` or `minio` when ClickHouse runs in Docker:
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
# ... etc
```

4. **Restart services** after port changes:
```bash
./setup.sh --stop
./setup.sh --start
```

## Switching Catalogs

To switch between catalog types:

1. Stop current services:
   ```bash
   ./setup.sh --stop
   ```

2. Reconfigure:
   ```bash
   ./setup.sh --configure
   ```

3. Start with new catalog:
   ```bash
   ./setup.sh --start
   ```

## Data Persistence

- MinIO data is persisted in [minio-storage/](minio-storage/)
- PostgreSQL data (for Hive) is in Docker volume `postgres-data`
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
│           Data Lake Architecture            │
├─────────────────────────────────────────────┤
│                                             │
│  ┌──────────┐      ┌────────────────┐      │
│  │  MinIO   │◄────►│  Data Catalog  │      │
│  │ (Storage)│      │ (Nessie/Hive/  │      │
│  └──────────┘      │  Iceberg REST) │      │
│       ▲            └────────────────┘      │
│       │                     ▲               │
│       │                     │               │
│  ┌────┴─────┐      ┌───────┴──────┐       │
│  │ Jupyter  │      │  ClickHouse  │       │
│  │ Notebook │      │   (External) │       │
│  └──────────┘      └──────────────┘       │
│                                             │
└─────────────────────────────────────────────┘
```

## Resources

- [MinIO Documentation](https://min.io/docs/minio/linux/index.html)
- [Apache Iceberg](https://iceberg.apache.org/)
- [Project Nessie](https://projectnessie.org/)
- [ClickHouse S3 Integration](https://clickhouse.com/docs/en/engines/table-engines/integrations/s3)

## License

This is a demonstration project for educational purposes.

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review Docker logs
3. Verify configuration in [config.env](config.env)
